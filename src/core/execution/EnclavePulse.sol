// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { EnclavesStorage } from "../storage/EnclavesStorage.sol";
import { LPCE } from "../../libs/LPCE.lib.sol";

/// @notice When a Sendra position owner is an enclave executor, reputation
///         (global and specific pulse) belongs to the operator. The book stays
///         on the executor. Returns address(0) for every other owner.
contract EnclavePulse {
    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function recipient(address owner) external view returns (address) {
        LPCE.Enclave memory enclave = EnclavesStorage(addressProvider.getAddress("EnclavesStorage")).getEnclaveByAddress(owner);
        if (enclave.sendraExecutor != owner) return address(0);
        return enclave.operator;
    }
}
