// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISendraAddressProvider {
    /**
     * @notice Gets the address of a contract by name.
     * @param contractName Protocol/contract name (e.g., "GMX", "Uniswap", "Aave").
     * @return Address of the target contract.
     */
    function getAddress(string calldata contractName) external view returns (address);

    error AddressNotFound(string contractName);
}

