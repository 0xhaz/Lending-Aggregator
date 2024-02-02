// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title CoreRoles
 * @notice System definition of roles used across all contracts
 */

contract CoreRoles {
  bytes32 public constant HOUSE_KEEPER_ROLE = keccak256("HOUSE_KEEPER_ROLE");
  bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
  bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
  bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
}
