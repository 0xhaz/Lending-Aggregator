// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title Chief
 * @notice Controls vault deploy factories, deployed flashers, vault ratingss and core access control
 * @dev Deployments of new vaults are done through this contract that also stores the addresses of all deployed vaults
 */

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {TimelockController} from
  "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {CoreRoles} from "./access/CoreRoles.sol";
import {IChief} from "./interfaces/IChief.sol";
import {AddrMapper} from "./helpers/AddrMapper.sol";
import {IPausableVault} from "./interfaces/IPausableVault.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";

contract Chief is CoreRoles, AccessControl, IChief {
  using Address for address;

  ////////////////// EVENTS //////////////////
  /**
   * @dev Emitted when the deployments of new vaults is allowed/disallowed
   * @param allowed "true" if allowed, "false" if disallowed
   */
  event AllowPermissionlesDeployments(bool allowed);

  /**
   * @dev Emitted when `vault` is set the be active or not
   * @param vault address to set
   * @param active boolean
   */
  event SetVaultStatus(address vault, bool active);

  /**
   * @dev Emitted when a new flasher is allowed/disallowed
   * @param flasher address of the flasher
   * @param allowed "true" if allowed, "false" if disallowed
   */
  event AllowFlasher(address indexed flasher, bool allowed);

  /**
   * @dev Emitted when a new swapper is allowed/disallowed
   * @param swapper address of the swapper
   * @param allowed "true" if allowed, "false" if disallowed
   */
  event AllowSwapper(address indexed swapper, bool allowed);

  /**
   * @dev Emitted when a new factory is allowed/disallowed
   * @param factory address of the factory
   * @param allowed "true" if allowed, "false" if disallowed
   */
  event AllowVaultFactory(address indexed factory, bool allowed);

  /**
   * @dev Emitted when a new `timelock` is set
   * @param timelock address of the timelock
   */
  event UpdateTimelock(address indexed timelock);

  /**
   * @dev Emitted when a new rating is attributed to a vault
   * @param vault address of the vault
   * @param newRating value of the new rating
   */
  event ChangeSafetyRating(address indexed vault, uint256 newRating);

  /**
   * @notice Emits when a new vault is deployed
   * @param vault address of the new vault
   * @param factory address of the factory used to deploy the vault
   * @param rating initial rating of the new vault
   */
  event DeployVault(address indexed vault, address indexed factory, uint256 rating);

  ////////////////// CUSTOM ERRORS //////////////////
  // @dev Custom Errors
  error Chief__checkInput_zeroAddress();
  error Chief__setVaultStatus_noStatusChange();
  error Chief__allowFlasher_noAllowChange();
  error Chief__allowVaultFactory_noAllowChange();
  error Chief__deployVault_factoryNotAllowed();
  error Chief__deployVault_missingRole(address account, bytes32 role);
  error Chief__onlyTimelock_callerIsNotTimelock();
  error Chief__setSafetyRating_notActiveVault();
  error Chief__checkRatingValue_notInRange();
  error Chief__allowSwapper_noAllowChange();

  /**
   * @dev When `permissionlessDeployments` is 'false', only addresses with this role
   * can deploy new vaults
   */
  bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

  address public timelock;
  address public addrMapper;

  /// @dev Control who can deploy new vaults through the `deployVault` function
  bool public permissionlessDeployments;

  mapping(address => bool) public isVaultActive;
  mapping(address => uint256) public vaultSafetyRating;

  mapping(address => bool) public allowedVaultFactory;
  mapping(address => bool) public allowedFlasher;
  mapping(address => bool) public allowedSwapper;

  modifier onlyTimelock() {
    if (msg.sender != timelock) {
      revert Chief__onlyTimelock_callerIsNotTimelock();
    }
    _;
  }

  constructor(bool deployTimelock, bool deployAddrMapper) {
    _grantRole(DEPLOYER_ROLE, msg.sender);
    _grantRole(HOUSE_KEEPER_ROLE, msg.sender);
    _grantRole(PAUSER_ROLE, address(this));
    _grantRole(UNPAUSER_ROLE, address(this));
    if (deployTimelock) _deployTimelockController();
    if (deployAddrMapper) _deployAddrMapper();
  }

  ////////////////// EXTERNAL FUNCTIONS //////////////////
  /**
   * @notice Changes the status of `vault`, while triggering corresponding "pause" actions
   * @param vault to change state
   * @param active boolean
   * @dev Refer to internal function for implementation
   * Requirements:
   * - Must be called from timelock
   * - Must check `active` argument does change current stat
   * - Must pause Deposit action in `vault`
   * - Must pause Borrow action if `vault` is a {BorrowingVault}
   */
  function setVaultStatus(address vault, bool active) external onlyTimelock {
    _setVaultStatus(vault, active);
  }

  /**
   * @notice Sets a new timelock
   * @param newTimelock address of the new timelock
   * @dev Requirements:
   * - Must be restricted to timelock
   * - Revokes `DEFAULT_ADMIN_ROLE` from the existing timelock
   * - Grants `DEFAULT_ADMIN_ROLE` to the new timelock
   * - Must be a non-zero address
   * - Emits a `UpdateTimelock` event
   */
  function setTimelock(address newTimelock) external onlyTimelock {
    _checkInputIsNotZeroAddress(newTimelock);
    // Revoke admin role from current timelock
    _revokeRole(DEFAULT_ADMIN_ROLE, timelock);
    // Assign `timelock` to the new timelock
    timelock = newTimelock;
    // Grant admin role to new timelock
    _grantRole(DEFAULT_ADMIN_ROLE, timelock);
    emit UpdateTimelock(newTimelock);
  }

  /**
   * @notice Sets `permissionlessDeployments`
   * @param allowed anyone can deploy a vault when true
   * otherwise only addresses with `DEPLOYER_ROLE` can deploy
   * @dev Requirements:
   * - Must be restricted to timelock
   * - Emits a `AllowPermissionlesDeployments` event
   */
  function setPermissionlessDeployments(bool allowed) external onlyTimelock {
    permissionlessDeployments = allowed;
    emit AllowPermissionlesDeployments(allowed);
  }

  /**
   * @notice Deploys a new vault through a factory, attribute an initial rating and store new vault's address in `_vaults`
   * @param factory allowed vault factory contract
   * @param deployData encoded data that will be used in the factory to create a new vault
   * @param rating initial rating of the new vault
   *
   * @dev Requirements:
   * - Must be allowed factory
   * - msg.sender must have `DEPLOYER_ROLE` if `permissionlessDeployments` is false
   * - `rating` must be in range [1,100]
   * - Emits a `DeployVault` event
   */
  function deployVault(
    address factory,
    bytes calldata deployData,
    uint256 rating
  )
    external
    returns (address vault)
  {
    if (!allowedVaultFactory[factory]) revert Chief__deployVault_factoryNotAllowed();
    if (!permissionlessDeployments && !hasRole(DEPLOYER_ROLE, msg.sender)) {
      revert Chief__deployVault_missingRole(msg.sender, DEPLOYER_ROLE);
    }
    _checkRatingValue(rating);
    vault = IVaultFactory(factory).deployVault(deployData);

    vaultSafetyRating[vault] = rating;
    _setVaultStatus(vault, true);

    emit DeployVault(vault, factory, rating);
  }

  /**
   * @notice Sets `vaultSafetyRating` for `vault`
   * @param vault address of the vault whose rating will be changed
   * @param newRating a new value for the rating
   * @dev Requirements:
   * - Emits a `ChangeSafetyRating` event
   * - only timelock can change rating
   * - `newRating` must be in range [1,100]
   * - `vault` is a non-zero address and is contained in `_vaults`
   */
  function setSafetyRating(address vault, uint256 newRating) external onlyTimelock {
    if (!isVaultActive[vault]) revert Chief__setSafetyRating_notActiveVault();

    _checkRatingValue(newRating);
    vaultSafetyRating[vault] = newRating;

    emit ChangeSafetyRating(vault, newRating);
  }

  /**
   * @notice Sets `flasher` as an authorized address for flashloan operations
   * @param flasher address of the flasher to allow/disallow
   * @param allowed "true" to allow, "false" to disallow
   * @dev Requirements:
   * - `flasher` is a non-zero address
   * - `allowed` is different from current state
   * - Emits a `AllowFlasher` event
   */
  function allowFlasher(address flasher, bool allowed) external onlyTimelock {
    _checkInputIsNotZeroAddress(flasher);
    if (allowedFlasher[flasher] == allowed) revert Chief__allowFlasher_noAllowChange();

    allowedFlasher[flasher] = allowed;

    emit AllowFlasher(flasher, allowed);
  }

  /**
   * @notice Sets `swapper` as an authorized address for swap operations
   * @param swapper address of the swapper to allow/disallow
   * @param allowed "true" to allow, "false" to disallow
   * @dev Requirements:
   * - `swapper` is a non-zero address
   * - `allowed` is different from current state
   * - Emits a `AllowSwapper` event
   */
  function allowSwapper(address swapper, bool allowed) external onlyTimelock {
    _checkInputIsNotZeroAddress(swapper);
    if (allowedSwapper[swapper] == allowed) revert Chief__allowSwapper_noAllowChange();

    allowedSwapper[swapper] = allowed;

    emit AllowSwapper(swapper, allowed);
  }

  /**
   * @notice Sets `factory` as an authorized address for vault deployments
   * @param factory address of the factory to allow/disallow
   * @param allowed "true" to allow, "false" to disallow
   * @dev Requirements:
   * - `allowed` is different from current state
   * - Emits a `AllowVaultFactory` event
   */
  function allowVaultFactory(address factory, bool allowed) external onlyTimelock {
    _checkInputIsNotZeroAddress(factory);
    if (allowedVaultFactory[factory] == allowed) revert Chief__allowVaultFactory_noAllowChange();

    allowedVaultFactory[factory] = allowed;
    emit AllowVaultFactory(factory, allowed);
  }

  /**
   * @notice Force pause all actions in `vault`
   * @param vaults address of the vault to pause
   * @dev Requirements:
   * - Must be restricted to `PAUSER_ROLE`
   */
  function pauseForceVaults(IPausableVault[] calldata vaults) external onlyRole(PAUSER_ROLE) {
    bytes memory data = abi.encodeWithSelector(IPausableVault.pauseForceAll.selector);
    _changePauseState(vaults, data);
  }

  /**
   * @notice Force unpause all actions in `vault`
   * @param vaults address of the vault to unpause
   * @dev Requirements:
   * - Must be restricted to `UNPAUSER_ROLE`
   */
  function unpauseForceVaults(IPausableVault[] calldata vaults) external onlyRole(UNPAUSER_ROLE) {
    bytes memory data = abi.encodeWithSelector(IPausableVault.unpauseForceAll.selector);
    _changePauseState(vaults, data);
  }

  /**
   * @notice Pauses specific action in all vault in `_vaults`
   * @param action enum: {0:Deposit, 1:Withdraw, 2:Borrow, 3:Payback}
   * @dev Requirements:
   * - Must be restricted to `PAUSER_ROLE`
   * - `action` in all vaults must not be paused; otherwise revert
   */
  function pauseActionInVaults(
    IPausableVault[] calldata vaults,
    IPausableVault.VaultActions action
  )
    external
    onlyRole(PAUSER_ROLE)
  {
    bytes memory data = abi.encodeWithSelector(IPausableVault.pause.selector, action);
    _changePauseState(vaults, data);
  }

  /**
   * @notice Unpauses specific action in all vault in `_vaults`
   * @param action enum: {0:Deposit, 1:Withdraw, 2:Borrow, 3:Payback}
   * @dev Requirements:
   * - Must be restricted to `UNPAUSER_ROLE`
   * - `action` in all vaults must be paused; otherwise revert
   */
  function unpauseActionInVaults(
    IPausableVault[] calldata vaults,
    IPausableVault.VaultActions action
  )
    external
    onlyRole(UNPAUSER_ROLE)
  {
    bytes memory data = abi.encodeWithSelector(IPausableVault.unpause.selector, action);
    _changePauseState(vaults, data);
  }

  ////////////////// INTERNAL FUNCTIONS //////////////////
  /**
   * @dev Deploys {TimelockController} and sets `timelock` to the new address
   */
  function _deployTimelockController() internal {
    address[] memory admins = new address[](1);
    admins[0] = msg.sender;
    timelock = address(new TimelockController{salt: "0x00"}(1 days, admins, admins, address(0)));
    _grantRole(DEFAULT_ADMIN_ROLE, timelock);
  }

  /**
   * @dev Deploys {AddrMapper} contract during deployment
   */
  function _deployAddrMapper() internal {
    addrMapper = address(new AddrMapper{salt: "0x00"}(address(this)));
  }

  /**
   * @dev Refer to {Chief-setVaultStatus}
   * @param vault to change state
   * @param active boolean
   */
  function _setVaultStatus(address vault, bool active) internal {
    _checkInputIsNotZeroAddress(vault);
    if (isVaultActive[vault] == active) revert Chief__setVaultStatus_noStatusChange();

    isVaultActive[vault] = active;

    // Pause Deposit and Borrow actions if corresponding and applicable to `vault`
    if (active == false) {
      vaultSafetyRating[vault] = 0;
      IPausableVault(vault).pause(IPausableVault.VaultActions.Deposit);

      //   If `vault` is a {BorrowingVault}
      if (IVault(vault).debtAsset() != address(0)) {
        IPausableVault(vault).pause(IPausableVault.VaultActions.Borrow);
      }
    }
    emit SetVaultStatus(vault, active);
  }

  /**
   * @dev Reverts if `input` is zero address
   * @param input address to check
   */
  function _checkInputIsNotZeroAddress(address input) internal pure {
    if (input == address(0)) revert Chief__checkInput_zeroAddress();
  }

  /**
   * @dev Checks if `rating` is in range [1,100]
   * @param rating value to verify is in the accepted range
   */
  function _checkRatingValue(uint256 rating) internal pure {
    if (rating == 0 || rating > 100) revert Chief__checkRatingValue_notInRange();
  }

  /**
   * @dev Changes the pause state of `vaults` by calling `data` on each vault
   * @param vaults array of vaults to change state
   * @param data encoded data to call on each vault
   */
  function _changePauseState(IPausableVault[] calldata vaults, bytes memory data) internal {
    uint256 alength = vaults.length;
    for (uint256 i; i < alength;) {
      address(vaults[i]).functionCall(data, "Chief::_changePauseState: call failed");
      unchecked {
        ++i;
      }
    }
  }
}
