// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ReentrancyGuard
 * @notice This contracts implements a slight modification of the OpenZeppelin ReentrancyGuard contract
 * @dev Changes include:
 * - Definition of error `ReentrancyGuard: reentrant call` as a constant
 * - Constants `_NOT_ENTERED` and `_ENTERED` to track the state of the contract
 * - Usage of revert error statement in `_nonReentrantBefore`.*
 */

abstract contract ReentrancyGuard {
  ///////////////////// CUSTOM ERRORS /////////////////////
  error ReentrancyGuard_reentrantCall();

  // Booelans are more expensive than uint256 or any type that takes up a full
  // word because each write operation emits an extra SLOAD to first read the
  // slot's contents, replace the bits taken up by the boolean, and then write
  // back. This is the compiler's defense against contract upgrades and
  // pointer aliasing, and it cannot be disabled

  // The values being non-zero values make deployment a bit more expensive
  // but in exchange the refund on every call to nonReentrant will be lower
  // in amount. Since refunds are capped to half of the gas sent, it is best
  // to keep them as low as possible, to increase the likelihood of the refund
  uint256 internal constant _NOT_ENTERED = 1;
  uint256 internal constant _ENTERED = 2;

  uint256 private _status;

  constructor() {
    _status = _NOT_ENTERED;
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and make it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _nonReentrantBefore();
    _;
    _nonReentrantAfter();
  }

  function _nonReentrantBefore() private {
    // on the first call to nonReentrant, _status will be _NOT_ENTERED
    if (_status == _ENTERED) {
      revert ReentrancyGuard_reentrantCall();
    }

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;
  }

  function _nonReentrantAfter() private {
    // By setting _status to _NOT_ENTERED, any call to nonReentrant will revert
    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }

  /**
   * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a `nonReentrant` function in progress
   */
  function _reentrancyGuardEntered() internal view returns (bool) {
    return _status == _ENTERED;
  }
}
