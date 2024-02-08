// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title BaseRouter
 * @notice Abstract contract for router functionality
 */

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IChief} from "../interfaces/IChief.sol";
import {IFlasher} from "../interfaces/IFlasher.sol";
import {IVaultPermissions} from "../interfaces/IVaultPermissions.sol";
import {SystemAccessControl} from "../access/SystemAccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IWETH9} from "../abstracts/WETH9.sol";
import {LibBytes} from "../libraries/LibBytes.sol";

abstract contract BaseRouter is ReentrancyGuard, SystemAccessControl, IRouter {
  using SafeERC20 for IERC20;

  ///////////////////////////////// STRUCTS /////////////////////////////////
  /**
   * @dev Contains an address of an ERC-20 and the balance the router holds
   * at a given moment of the transaction (ref. `_tokensToCheck`).
   */
  struct Snapshot {
    address token;
    uint256 balance;
  }

  /**
   * @dev Struct used internally containing the arguments of a IRouter.Action.Permit to store
   * and pass in memory and avoid stack too deep error.
   */
  struct PermitArgs {
    IVaultPermissions vault;
    address owner;
    address receiver;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct BundleStore {
    uint256 len;
    /**
     * @dev Operations in the bundle should "benefit" or be executed
     * on behalft of this account. These are receivers on DEPOSIT and PAYBACK
     * or owners on WITHDRAW and BORROW.
     */
    address beneficiary;
    /**
     * @dev Hash generated during execution of "_bundleInternal()" that should match
     * the signed permit
     * This argument is used in {VaultPermissions-PermitWithdraw} and {VaultPermissions-PermitBorrow}
     */
    bytes32 actionArgsHash;
    uint256 nativeBalance;
    Snapshot[] tokensToCheck;
  }

  ///////////////////////////////// EVENTS /////////////////////////////////
  /**
   * @dev Emitted when `caller` is updated accoriding to `allowed` boolean
   * to perform cross-chain calls
   *
   * @param caller address of the caller
   * @param allowed boolean if `caller` is allowed to perform cross-chain calls
   */
  event AllowCaller(address indexed caller, bool allowed);

  ///////////////////////////////// CUSTOME ERRORS /////////////////////////////////
  error BaseRouter__bundleInternal_notFirstAction();
  error BaseRouter__bundleInternal_paramsMismatch();
  error BaseRouter__bundleInternal_flashloanInvalidRequestor();
  error BaseRouter__bundleInternal_noBalanceChange();
  error BaseRouter__bundleInternal_notBeneficiary();
  error BaseRouter__checkVaultInput_notActiveVault();
  error BaseRouter__bundleInternal_notAllowedSwapper();
  error BaseRouter__checkValidFlasher_notAllowedFlasher();
  error BaseRouter__handlePermit_notPermitAction();
  error BaseRouter__safeTransferETH_transferFailed();
  error BaseRouter__receive_senderNotWETH();
  error BaseRouter__fallback_notAllowed();
  error BaseRouter__allowCaller_noAllowChange();
  error BaseRouter__isInTokenList_snapshotLimitReached();
  error BaseRouter__xBundleFlashloan_insufficientFlashloanBalance();
  error BaseRouter__checkIfAddressZero_invalidZeroAddress();

  ///////////////////////////////// STATE VARIABLE & MODIFIERS /////////////////////////////////
  IWETH9 public immutable WETH9;

  bytes32 private constant ZERO_BYTES32 =
    0x0000000000000000000000000000000000000000000000000000000000000000;

  uint256 private _flashloanEnterStatus;

  // @dev Apply it on entry cross-chain calls functions as required
  mapping(address => bool) public isAllowedCaller;

  modifier onlyValidFlasherNonReentrant() {
    _checkValidFlasher(msg.sender);
    if (_flashloanEnterStatus == _ENTERED) {
      revert ReentrancyGuard_reentrantCall();
    }
    _flashloanEnterStatus = _ENTERED;
    _;
    _flashloanEnterStatus = _NOT_ENTERED;
  }

  ///////////////////////////////// CONSTRUCTOR /////////////////////////////////
  /**
   * @notice Constructor of a new {BaseRouter} instance
   * @param weth wrapper of the native token
   * @param chief_ address of the {Chief} contract
   */
  constructor(IWETH9 weth, IChief chief_) payable {
    __SystemAccessControl_init(address(chief_));
    WETH9 = weth;
    _flashloanEnterStatus = _NOT_ENTERED;
  }

  ///////////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////////
  /// @inheritdoc IRouter
  function xBundle(
    Action[] calldata actions,
    bytes[] calldata args
  )
    external
    payable
    override
    nonReentrant
  {
    _bundleInternal(actions, args, 0, Snapshot(address(0), 0));
  }

  ///////////////////////////////// INTERNAL & PRIVATE FUNCTIONS /////////////////////////////////
  /**
   * @dev Revert if flasher is not valid flash at {Chief}
   * @param flasher address of the flasher
   */
  function _checkValidFlasher(address flasher) internal view {
    if (!chief.allowedFlasher(flasher)) {
      revert BaseRouter__checkValidFlasher_notAllowedFlasher();
    }
  }

  /**
   * @dev Executes a bundle of actions
   * Requirements:
   * - Must not leave any balance in this contract after all actions
   * - Must call `_checkNoBalanceChange()` after all `actions` are executed
   * - Must call `_addTokenToList()` in `actions` that involve token transfers
   * - Must clear `_beneficiary` from storage after all `actions` are executed
   *
   * @param actions an array of actions that will be executed in a row
   * @param args an array of encoded inputs needed to execute each action
   * @param beforeSlipped amount passed by the origin cross-chain router operation
   * @param tokenToCheck_ snapshot token balance awareness required from parent calls
   */
  function _bundleInternal(
    Action[] memory actions,
    bytes[] memory args,
    uint256 beforeSlipped,
    Snapshot memory tokenToCheck_
  )
    internal
  {
    BundleStore memory store;

    store.len = actions.length;
    if (store.len != args.length) {
      revert BaseRouter__bundleInternal_paramsMismatch();
    }

    /**
     * @dev Stores token balances of this contract at a given moment
     * It is used to ensure that there are no changes in balances at the end of tx
     */
    store.tokensToCheck = new Snapshot[](10);

    /// @dev Add token to check from parent calls
    if (tokenToCheck_.token != address(0)) {
      store.tokensToCheck[0] = tokenToCheck_;
    }

    store.nativeBalance = address(this).balance - msg.value;

    for (uint256 i; i < store.len;) {
      Action action = actions[i];
      if (action == Action.Deposit) {
        // Deposit
        (IVault vault, uint256 amount, address receiver, address sender) =
          abi.decode(args[i], (IVault, uint256, address, address));

        _checkVaultInput(address(vault));

        address token = vault.asset();
        store.beneficiary = _checkBeneficiary(store.beneficiary, receiver);
        _addTokenToList(token, store.tokensToCheck);
        _addTokenToList(address(vault), store.tokensToCheck);
        _safePullTokenFrom(token, sender, amount);
        _safeApprove(token, address(vault), amount);

        vault.deposit(amount, receiver);
      } else if (action == Action.Withdraw) {
        // Withdraw
        (bool replace, bytes memory nextArgs) = _handleWithdrawAction(actions, args, store, i);
        if (replace) args[i + 1] = nextArgs;
      }
    }
  }

  function _checkVaultInput(address vault_) internal view {
    if (!chief.isVaultActive(vault_)) {
      revert BaseRouter__checkVaultInput_notActiveVault();
    }
  }

  /**
   * @dev when bundling multiple actions assure that we act for a single beneficiary
   * receivers on DEPOSIT and PAYBACK or owners on WITHDRAW and BORROW
   * must be the same user
   *
   * @param user address to verify is the beneficiary
   */
  function _checkBeneficiary(address beneficiary, address user) internal pure returns (address) {
    if (beneficiary == address(0)) {
      return user;
    } else if (beneficiary != user) {
      revert BaseRouter__bundleInternal_notBeneficiary();
    } else {
      return user;
    }
  }

  /**
   * @dev Adds a token and balance to a Snapshot and returns it
   * Requirements:
   * - Must check if token has already been added
   *
   * @param token address of ERC-20 to be pushed
   * @param tokenList to add token
   */
  function _addTokenToList(address token, Snapshot[] memory tokenList) private view {
    (bool isInList, uint256 latestIndex) = _isInTokenList(token, tokenList);
    if (!isInList) {
      tokenList[latestIndex] = Snapshot(token, IERC20(token).balanceOf(address(this)));
    }
  }

  /**
   * @dev Returns "true" and the `latestIndex` where a zero-address exists
   * @param token address of ERC-20 to be checked
   * @param tokenList to check
   */
  function _isInTokenList(
    address token,
    Snapshot[] memory tokenList
  )
    private
    pure
    returns (bool value, uint256 latestIndex)
  {
    uint256 len = tokenList.length;
    for (uint256 i; i < len;) {
      if (token == tokenList[i].token) {
        return (true, 0); // leave when the token is already in the list
      }
      if (tokenList[i].token == address(0)) {
        return (false, i); // return if the first empty slot is found
      }
      unchecked {
        ++i;
      }
    }
    // revert if looped through the entire list and found no match or empty slot
    revert BaseRouter__isInTokenList_snapshotLimitReached();
  }

  /**
   * @dev Helper function to pull ERC-20 token from a sender address after some checks
   * The checks are needed becuase when we bundle multiple actions
   * it can happen the router already holds the assets in question
   * for example, when we withdraw from a vault and deposit to another
   *
   * @param token address of the ERC-20 token to pull
   * @param sender address of the sender
   * @param amount amount of `token` to pull
   */
  function _safePullTokenFrom(address token, address sender, uint256 amount) internal {
    if (amount == 0) return;
    if (sender != address(this) && sender == msg.sender) {
      ERC20(token).safeTransferFrom(sender, address(this), amount);
    }
  }

  /**
   * @dev Helper function to approve ERC-20 transfers
   * @param token ERC-20 address to approve
   * @param to address to approve as a spender
   * @param amount amount to approved
   */
  function _safeApprove(address token, address to, uint256 amount) internal {
    if (amount == 0) return;
    ERC20(token).safeIncreaseAllowance(to, amount);
  }

  /**
   * @dev Handles withdraw actions logic flow. When there may be further actions
   * requiring to replace the `amount` argument, it handles the replacement
   *
   * Requirements:
   * - Check if next action is type that requires `amount` argument update else proceed as normal
   */
  function _handleWithdrawAction(
    Action[] memory actions,
    bytes[] memory args,
    BundleStore memory store,
    uint256 i
  )
    private
    returns (bool replace, bytes memory updatedArgs)
  {
    (IVault vault, uint256 amount, address receiver, address owner) =
      abi.decode(args[i], (IVault, uint256, address, address));
  }
}
