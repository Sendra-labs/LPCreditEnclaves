//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISendraRoles } from "../../interfaces/iSendraCore/ISendraRoles.sol";

/// @notice Protocol-wide counter of USDC credit actively committed in enclaves.
/// @dev Tracks deposit → withdraw lifecycle only. Capital deployed to Uniswap still counts
///      as under management until the enclave finalizes via withdrawCredit.
contract CapitalUnderManagement {

    address public immutable addressProvider;

    uint256 public totalCapitalUnderManagement;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    modifier onlyProtocol() {
        if (!ISendraRoles(ISendraAddressProvider(addressProvider).getAddress("Roles")).isProtocolContract(msg.sender)) {
            revert NotProtocolContract();
        }
        _;
    }

    function recordDeposit(uint256 amount) external onlyProtocol {
        if (amount == 0) revert ZeroAmount();

        totalCapitalUnderManagement += amount;

        emit CapitalUnderManagementUpdated(totalCapitalUnderManagement);
    }

    function recordWithdrawal(uint256 amount) external onlyProtocol {
        if (amount == 0) revert ZeroAmount();
        if (amount > totalCapitalUnderManagement) revert InsufficientCapitalUnderManagement();

        totalCapitalUnderManagement -= amount;

        emit CapitalUnderManagementUpdated(totalCapitalUnderManagement);
    }

    /// @dev One row per change. Dune: ORDER BY evt_block_time DESC LIMIT 1 → current KPI.
    event CapitalUnderManagementUpdated(uint256 newTotal);

    error NotProtocolContract();
    error ZeroAmount();
    error InsufficientCapitalUnderManagement();
}
