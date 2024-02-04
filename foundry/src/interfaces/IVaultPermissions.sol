// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IVaultPermissions
 * @notice Defines interface for {Vault} extended with
 * signed permit operations for `withdraw()` and `borrow()` allowance
 */

interface IVaultPermissions {
  /**
   * @dev Emitted when `asset` withdraw allowance is set
   * @param owner who is setting allowance
   * @param operator who can execute the use of allowance
   * @param receiver who can spend the allowance
   * @param amount of allowance given
   */
  event WithdrawApproval(address indexed owner, address operator, address receiver, uint256 amount);

  /**
   * @dev Emitted when `debtAsset` borrow allowance is set
   * @param owner who provides allowance
   * @param operator who can exeecute the use of allowance
   * @param receiver who can spend the allowance
   * @param amount of allowance given
   */
  event BorrowApproval(address indexed owner, address operator, address receiver, uint256 amount);

  /// @dev Based on {IERC20Permit-DOMAIN_SEPARATOR}
  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() external returns (bytes32);

  /**
   * @notice Returns the current amount of withdraw allowance for `owner` to `receiver`
   * that can be executed by `operator`. This is similar to {IERC20-allowance} for BaseVault
   * assets, instead of token-shares
   *
   * @param owner who is providing the allowance
   * @param operator who can execute the use of allowance
   * @param receiver who can spend the allowance
   * @dev Requirements:
   * - Must replaice {IERC4626-allowance} in vault implementations
   */
  function withdrawAllowance(
    address owner,
    address operator,
    address receiver
  )
    external
    view
    returns (uint256);

  /**
   * @notice Returns the current amount of borrow allowance for `owner` to `receiver`
   * that can be executed by `operator`. This is similar to {IERC20-allowance} for
   * BaseVault-debtAssets.
   *
   * @param owner who is providing the allowance
   * @param operator who can execute the use of allowance
   * @param receiver who can spend the allowance
   */
  function borrowAllowance(
    address owner,
    address operator,
    address receiver
  )
    external
    view
    returns (uint256);

  /**
   * @dev Automically increases the `withdrawAllowance` granted to `receiver` and
   * executable by `operator` by the caller. Based on {ERC20-incraseAllowance} for assets
   * @param operator who is setting the allowance
   * @param receiver who can spend the allowance
   * @param byAmount amount to increase allowance by
   * @dev Requirements:
   * - Must emit a {WithdrawApproval} event indicating the updated allowance
   * - Must check `operator` and `receiver` is not zero address
   */
  function increaseWithdrawAllowance(
    address operator,
    address receiver,
    uint256 byAmount
  )
    external
    returns (bool);

  /**
   * @dev Automically decreases the `withdrawAllowance` granted to `receiver` and
   * executable by `operator` by the caller. Based on {ERC20-decreaseAllowance} for assets
   * @param operator who is setting the allowance
   * @param receiver who can spend the allowance
   * @param byAmount amount to decrease allowance by
   * @dev Requirements:
   * - Must emit a {WithdrawApproval} event indicating the updated allowance
   * - Must check `operator` and `receiver` is not zero address
   * - Must check `operator` and `receiver` have `borrowAllowance` greater than or equal
   *   to `byAmount`
   */
  function decreaseWithdrawAllowance(
    address operator,
    address receiver,
    uint256 byAmount
  )
    external
    returns (bool);

  /**
   * @dev Automically increases the `borrowAllowance` granted to `receiver` and
   * executable by `operator` by the caller. Based on {ERC20-incraseAllowance} for debtAssets
   * @param operator who is setting the allowance
   * @param receiver who can spend the allowance
   * @param byAmount amount to increase allowance by
   * @dev Requirements:
   * - Must emit a {BorrowApproval} event indicating the updated allowance
   * - Must check `operator` and `receiver` is not zero address
   * - Must check `operator` and `receiver` have `borrowAllowance` greater than or equal
   */
  function increaseBorrowAllowance(
    address operator,
    address receiver,
    uint256 byAmount
  )
    external
    returns (bool);

  /**
   * @dev Automically decreases the `borrowAllowance` granted to `receiver` and
   * executable by `operator` by the caller. Based on {ERC20-decreaseAllowance} for debtAssets
   * @param operator who is setting the allowance
   * @param receiver who can spend the allowance
   * @param byAmount amount to decrease allowance by
   * @dev Requirements:
   * - Must emit a {BorrowApproval} event indicating the updated allowance
   * - Must check `operator` and `receiver` is not zero address
   * - Must check `operator` and `receiver` have `borrowAllowance` greater than or equal
   *  to `byAmount`
   */
  function decreaseBorrowAllowance(
    address operator,
    address receiver,
    uint256 byAmount
  )
    external
    returns (bool);

  /**
   * @notice Returns the current used nonces for permits of `owner`
   * Based on {IERC20Permit-nonces}
   * @param owner address whom to query the nonce for
   */
  function nonces(address owner) external view returns (uint256);

  /**
   * @notice Sets `amount` as the `withdrawAllowance` for `receiver` executable by
   * caller over `owner's` tokens, given the `owner's` signed approval.
   * Based on {IERC20Permit-permit} for assets
   * @param owner address of the owner providing the allowance
   * @param receiver address of the receiver of the allowance
   * @param amount amount of allowance to provide
   * @param deadline by which the `owner` must sign the permit
   * @param actionArgsHash keccak256 of the abi.encoded(args, actions) to be performed
   * in {BaseRouter._internalBundle}
   * @param v signature param
   * @param r signature param
   * @param s signature param
   *
   * @dev Requirements:
   * - Must check `deadline` is a timestamp in the future
   * - Must check `receiver` is not zero address
   * - Must check that `v`, `r`, `s` is a valid `secp256k1` signature from `owner`
   *   over EIP-712 formatted function arguments.
   * - Must check the signature used `owner` current nonce (replay protection)
   * - Must emit an {AssetsApproval} event indicating the updated allowance
   */
  function permitWithdraw(
    address owner,
    address receiver,
    uint256 amount,
    uint256 deadline,
    bytes32 actionArgsHash,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external;

  /**
   * @notice Sets `amount` as the `borrowAllowance` for `receiver` executable by
   * caller over `owner's` tokens, given the `owner's` signed approval.
   * Based on {IERC20Permit-permit} for debtAssets
   * @param owner address of the owner providing the allowance
   * @param receiver address of the receiver of the allowance
   * @param amount amount of allowance to provide
   * @param deadline by which the `owner` must sign the permit
   * @param actionArgsHash keccak256 of the abi.encoded(args, actions) to be performed
   * in {BaseRouter._internalBundle}
   * @param v signature param
   * @param r signature param
   * @param s signature param
   * @dev Requirements:
   * - Must check `deadline` is a timestamp in the future
   * - Must check `receiver` is not zero address
   * - Must check that `v`, `r`, `s` is a valid `secp256k1` signature from `owner`
   *  over EIP-712 formatted function arguments.
   * - Must check the signature used `owner` current nonce (replay protection)
   * - Must emit {BorrowApproval} event indicating the updated allowance
   * - Must be implemented in {BorrowingVault}
   */
  function permitBorrow(
    address owner,
    address receiver,
    uint256 amount,
    uint256 deadline,
    bytes32 actionArgsHash,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external;
}
