// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ConnextRouter
 * @notice A router implementing Connext specific bridging logic
 */

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IConnext, IXReceiver} from "../interfaces/connext/IConnext.sol";
import {ConnextHandler} from "../routers/ConnextHandler.sol";
import {ConnextReceiver} from "../routers/ConnextReceiver.sol";
import {BaseRouter} from "../abstracts/BaseRouter.sol";
import {IWETH9} from "../abstracts/WETH9.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IVaultPermissions} from "../interfaces/IVaultPermissions.sol";
import {IChief} from "../interfaces/IChief.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IFlasher} from "../interfaces/IFlasher.sol";
import {LibBytes} from "../libraries/LibBytes.sol";

contract ConnextRouter is BaseRouter, IXReceiver {
  using SafeERC20 for IERC20;

  ///////////////////////////////// CUSTOM ERRORS /////////////////////////////////
  error ConnextRouter__setRouter_invalidInput();
  error ConnextRouter__xReceive_notAllowedCaller();
  error ConnextRouter__xReceiver_noValueTransferUseXBundle();
  error ConnextRouter__xBundleConnext_notSelfCalled();
  error ConnextRouter__crossTransffer_checkReceiver();

  ///////////////////////////////// EVENTS /////////////////////////////////
  /**
   * @dev Emitted when a new destination ConnextReciever gets added
   * @param router ConnextReceiver on another chain
   * @param domain the destination domain identifier according Connext nomenclature
   */
  event NewConnextReceiver(address indexed router, uint256 indexed domain);

  /**
   * @dev Emitted when Connext `xCall` is invoked
   * @param transferId the unique identifier of the crosschain transfer
   * @param caller the account that called the function
   * @param receiver the router on destDomain
   * @param destDomain the destination domain identifier according Connext nomenclature
   * @param asset the asset being transferred
   * @param amount the amonut of transferring asset the recipient will receive
   * @param callData the calldata sent to destination router that will get decoded an executed
   */
  event XCalled(
    bytes32 indexed transferId,
    address indexed caller,
    address indexed receiver,
    uint256 destDomain,
    address asset,
    uint256 amount,
    bytes callData
  );

  /**
   * @dev Emitted when the router receives a cross-chain call
   * @param transferId the unique identifier of the crosschain transfer
   * @param originDomain the origin domain identifier according to Connext nomenclature
   * @param success whether the call was successful from xBundle
   * @param asset the asset being transferred
   * @param amount the amonut of transferring asset the recipient will receive
   * @param callData the calldata sent to destination router that will get decoded an executed
   */
  event XReceived(
    bytes32 indexed transferId,
    uint256 indexed originDomain,
    bool success,
    address asset,
    uint256 amount,
    bytes callData
  );

  ///////////////////////////////// CONSTANTS /////////////////////////////////
  IConnext public immutable connext;

  ConnextHandler public immutable handler;
  address public immutable connextReceiver;

  /**
   * @notice A mapping of a domain of another chain and a deployed ConnexReceiver contract
   * @dev For the list of domains supported by Connext
   * https://docs.connext.network/resources/deployments
   */
  mapping(uint256 => address) public receiverByDomain;

  modifier onlySelf() {
    if (msg.sender != address(this)) {
      revert ConnextRouter__xBundleConnext_notSelfCalled();
    }
    _;
  }

  modifier onlyConnextReceiver() {
    if (msg.sender != connextReceiver) {
      revert ConnextRouter__xReceive_notAllowedCaller();
    }
    _;
  }

  ///////////////////////////////// CONSTRUCTOR /////////////////////////////////
  constructor(IWETH9 weth, IConnext connext_, IChief chief) BaseRouter(weth, chief) {
    connext = connext_;
    connextReceiver = address(new ConnextReceiver(address(this)));
    handler = new ConnextHandler(address(this));
    _allowCaller(msg.sender, true);
  }

  ///////////////////////////////// CONNEXT SPECIFIC FUNCTIONS /////////////////////////////////
  /**
   * @notice Called by Connext on destination chain
   * @param transferId the unique identifier of the crosschain transfer
   * @param amount the amount of transferring asset, after slippage, the recipient address receives
   * @param asset the asset being transferred
   * @param originSender the address of the contract or EOA that called xcall on the origin chain
   * @param originDomain the origin domain identifier according to Connext nomenclature
   * @param callData the calldata sent to destination router that will get decoded an executed
   *
   * @dev It does not perform authentication of the calling address. As a result of that,
   * all txns go through Connext's fast path
   * If `xBundle` fails internally, this contract will send the recieved funds to {ConnextHandler}
   *
   * Requirements:
   * - `calldata` parameter must be encoded with the following structure:
   *  > abi.encode(Action[] actions, bytes[] args)
   * - actions: array of serialized actions to execute from available enum {IRouter.Action}
   * - args: array of encoded arguments for each action. See {BaseRouter-internalBundle}
   */
  function xReceive(
    bytes32 transferId,
    uint256 amount,
    address asset,
    address originSender,
    uint32 originDomain,
    bytes memory callData
  )
    external
    onlyConnextReceiver
    returns (bytes memory)
  {
    (Action[] memory actions, bytes[] memory args) = abi.decode(callData, (Action[], bytes[]));

    Snapshot memory tokenToCheck_ = Snapshot(asset, IERC20(asset).balanceOf(address(this)));

    IERC20(asset).safeTransferFrom(connextReceiver, address(this), amount);

    /**
     * @dev Due to the AMM nature of Connext, there could be some slippage
     * incurred on the amount that this contract receives after bridging
     * There is also a routing fee of 0.05% of the bridged amount
     * The slippage can't be calculated upfront so that's why we need to
     * replace `amount` in the encoded args for the first action if
     * the action is Deposit or Payback
     */
    uint256 beforeSlipped;
    (args[0], beforeSlipped) = _accountForSlippage(amount, actions[0], args[0]);

    /**
     * @dev Connext will keep the custody of the bridged amount if the call
     * to `xReceive` fails. That's why we need to ensure the funds are not stuck at Connext
     * Therefore we try/catch instead of calling _bundleInternal directly
     */
    try this.xBundleConnext(actions, args, beforeSlipped, tokenToCheck_) {
      emit XReceived(transferId, originDomain, true, asset, amount, callData);
    } catch {
      IERC20(asset).safeTransfer(address(handler), amount);
      handler.recordFailed(transferId, amount, asset, originSender, originDomain, actions, args);

      emit XReceived(transferId, originDomain, false, asset, amount, callData);
    }

    return "";
  }

  /**
   * @notice Function selector created to allow try-catch procedure in Connext message data
   * passing.Including argument for `beforeSlipped` not available in {BaseRouter-xBundle}
   *
   * @param actions an arrya of actions that will be executed in a row
   * @param args an array of encoded iputs needed to execute each action
   * @param beforeSlipped the amount passed by the origin cross-chain router operation
   * @param tokenToCheck_ the snapshot after xReceive from Connext
   *
   * @dev Requirements:
   * - Must only be called within the context of this same contract
   */
  function xBundleConnext(
    Action[] calldata actions,
    bytes[] calldata args,
    uint256 beforeSlipped,
    Snapshot memory tokenToCheck_
  )
    external
    payable
    onlySelf
  {
    _bundleInternal(actions, args, beforeSlipped, tokenToCheck_);
  }

  /**
   * @dev Decodes and replaces "amount" argument in args with `receivedAmount`
   * in Deposit, or Payback
   *
   */
  function _accountForSlippage(
    uint256 receivedAmount,
    Action action,
    bytes memory args
  )
    private
    pure
    returns (bytes memory newArgs, uint256 beforeSlipped)
  {
    uint256 prevAmount;
    (newArgs, prevAmount) = _replaceAmountArgInAction(action, args, receivedAmount);
    if (prevAmount != receivedAmount) {
      beforeSlipped = prevAmount;
    }
  }

  /**
   * @notice NOTE to Integrators
   * The `beneficiary_` of a `_crossTransfer()` must meet these requirements:
   * - Must be an externally owned account (EOA) or
   * - Must be a contract that implements or is capable of calling:
   * - connext.forceUpateSlippage(TransferInfo, _slippage) add the destination chain
   * Refer to `delegate` argument:
   * https://docs.connext.network/developers/guides/handling-failures#increasing-slippage-tolerance
   */
  /// @inheritdoc BaseRouter
  function _crossTransfer(
    bytes memory params,
    address beneficiary
  )
    internal
    override
    returns (address)
  {
    (
      uint256 destDomain,
      uint256 slippage,
      address asset,
      uint256 amount,
      address receiver,
      address sender
    ) = abi.decode(params, (uint256, uint256, address, uint256, address, address));
    _checkIfAddressZero(receiver);
    /// @dev In a simple _crossTransfer funds should not be left in destination `ConnextRouter`
    if (receiver == receiverByDomain[destDomain]) {
      revert ConnextRouter__crossTransffer_checkReceiver();
    }
    address beneficiary_ = _checkBeneficiary(beneficiary, receiver);

    _safePullTokenFrom(asset, sender, amount);
    /// @dev Reassign if the encoded amount differs from the available balance (for ex. after soft withdraw or payback)
    uint256 balance = IERC20(asset).balanceOf(address(this));
    uint256 amount_ = balance < amount ? balance : amount;
    _safeApprove(asset, address(connext), amount_);

    bytes32 transferId = connext.xcall(
      // _destination: domain ID of the destination chain
      uint32(destDomain),
      // _to: address of the target contract
      receiver,
      // _asset: address of the token contract
      asset,
      // _delegate: address that can revert or forceLocal on destination
      beneficiary_,
      // _amount: amount of tokens to send
      amount_,
      // _slippage: can be anything between 0-10000 because
      // the maximum amount of slippage the user will accept in BPS, 30 == 0.3%
      slippage,
      // _callData: data to execute on the receiving chain
      ""
    );

    emit XCalled(transferId, msg.sender, receiver, destDomain, asset, amount_, "");

    return beneficiary_;
  }

  /**
   * @dev NOTE to integrators
   * The `beneficiary_` , of a `_crossTransfer()` must meet these requirements:
   * - Must be an externally owned account (EOA) or
   * - Must be a contract that implements or is capable of calling:
   *  - connext.forceUpateSlippage(TransferInfo, _slippage) add the destination chain
   * Refer to `delegate` argument:
   * https://docs.connext.network/developers/guides/handling-failures#increasing-slippage-tolerance
   */
  /// @inheritdoc BaseRouter
  function _crossTransferWithCalldata(
    bytes memory params,
    address beneficiary
  )
    internal
    override
    returns (address beneficiary_)
  {
    (
      uint256 destDomain,
      uint256 slippage,
      address asset,
      uint256 amount,
      address sender,
      bytes memory callData
    ) = abi.decode(params, (uint256, uint256, address, uint256, address, bytes));

    (Action[] memory actions, bytes[] memory args) = abi.decode(callData, (Action[], bytes[]));

    beneficiary_ = _checkBeneficiary(beneficiary, _getBeneficiaryFromCalldata(actions, args));

    address to_ = receiverByDomain[destDomain];
    _checkIfAddressZero(to_);

    _safePullTokenFrom(asset, sender, amount);
    _safeApprove(asset, address(connext), amount);

    bytes32 transferId = connext.xcall(
      // _destination: domain ID of the destination chain
      uint32(destDomain),
      // _to: address of the target contract
      to_,
      // _asset: address of the token contract
      asset,
      // _delegate: address that can revert or forceLocal on destination
      beneficiary_,
      // _amount: amount of tokens to send
      amount,
      // _slippage: can be anything between 0-10000 because
      // the maximum amount of slippage the user will accept in BPS, 30 == 0.3%
      slippage,
      // _callData: data to execute on the receiving chain
      callData
    );

    emit XCalled(
      transferId, msg.sender, receiverByDomain[destDomain], destDomain, asset, amount, callData
    );

    return beneficiary_;
  }

  /// @inheritdoc BaseRouter
  function _replaceAmountInCrossAction(
    Action action,
    bytes memory args,
    uint256 updateAmount
  )
    internal
    pure
    override
    returns (bytes memory newArgs, uint256 previousAmount)
  {
    if (action == Action.XTransfer) {
      (
        uint256 destDomain,
        uint256 slippage,
        address asset,
        uint256 amount,
        address receiver,
        address sender
      ) = abi.decode(args, (uint256, uint256, address, uint256, address, address));
      previousAmount = amount;
      newArgs = abi.encode(destDomain, slippage, asset, updateAmount, receiver, sender);
    } else if (action == Action.XTransferWithCall) {
      (
        uint256 destDomain,
        uint256 slippage,
        address asset,
        uint256 amount,
        address sender,
        bytes memory callData
      ) = abi.decode(args, (uint256, uint256, address, uint256, address, bytes));
      previousAmount = amount;
      newArgs = abi.encode(destDomain, slippage, asset, updateAmount, sender, callData);
    }
  }

  /// @inheritdoc BaseRouter
  function _getBeneficiaryFromCalldata(
    Action[] memory actions,
    bytes[] memory args
  )
    internal
    view
    override
    returns (address beneficiary_)
  {
    if (actions[0] == Action.Deposit || actions[0] == Action.Payback) {
      // For Deposit or Payback
      (,, address receiver,) = abi.decode(args[0], (IVault, uint256, address, address));
      beneficiary_ = receiver;
    } else if (actions[0] == Action.Withdraw || actions[0] == Action.Borrow) {
      (,,, address owner) = abi.decode(args[0], (IVault, uint256, address, address));
      beneficiary_ = owner;
    } else if (actions[0] == Action.WithdrawETH) {
      // For WithdrawETH
      (, address receiver) = abi.decode(args[0], (uint256, address));
      beneficiary_ = receiver;
    } else if (actions[0] == Action.PermitBorrow || actions[0] == Action.PermitWithdraw) {
      (, address owner,,,,,,) =
        abi.decode(args[0], (IVault, address, address, uint256, uint256, uint8, bytes32, bytes32));
      beneficiary_ = owner;
    } else if (actions[0] == Action.Flashloan) {
      (,,,, Action[] memory newActions, bytes[] memory newArgs) =
        abi.decode(args[0], (IFlasher, address, uint256, address, Action[], bytes[]));
      beneficiary_ = _getBeneficiaryFromCalldata(newActions, newArgs);
    } else if (actions[0] == Action.XTransfer) {
      (,,,, address receiver,) =
        abi.decode(args[0], (uint256, uint256, address, uint256, address, address));
      beneficiary_ = receiver;
    } else if (actions[0] == Action.XTransferWithCall) {
      (,,,, bytes memory callData) =
        abi.decode(args[0], (uint256, uint256, address, uint256, bytes));

      (Action[] memory actions_, bytes[] memory args_) = abi.decode(callData, (Action[], bytes[]));

      beneficiary_ = _getBeneficiaryFromCalldata(actions_, args_);
    } else if (actions[0] == Action.DepositETH) {
      /// @dev depositETH cannot be actions[0] in ConnextRouter or inner-flashloan actions
      revert BaseRouter__bundleInternal_notFirstAction();
    } else if (actions[0] == Action.Swap) {
      /// @dev Swap cannot be actions[0]
      revert BaseRouter__bundleInternal_notFirstAction();
    }
  }

  /**
   * @notice Anyone can call this function on the origin domain to increase the relayer fee for a transfer
   * @param transferId the unique identifier of the crosschain transfer
   */
  function bumpTransfer(bytes32 transferId) external payable {
    connext.bumpTransfer{value: msg.value}(transferId);
  }

  /**
   * @notice Registers an address of the ConnextReceiver deployed on another chain
   * @param domain unique identifier of a chain as defined in
   * https://docs.connext.network/resources/deployments
   * @param receiver address of ConnecxtRouter deployed on the chain defined by its domain
   * @dev The mapping domain => receiver is used in `xReceive` to verify the origin sender
   * Requirements:
   * - Must be restricted to timelock
   * - `receiver` must not be the zero address
   */
  function setReceiver(uint256 domain, address receiver) external onlyTimelock {
    _checkIfAddressZero(receiver);
    receiverByDomain[domain] = receiver;

    emit NewConnextReceiver(receiver, domain);
  }
}
