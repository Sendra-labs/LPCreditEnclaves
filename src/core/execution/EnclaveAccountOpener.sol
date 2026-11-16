// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { AccessControlInter } from "../storage/security/AccessControlInter.sol";

/// @notice Kept so the address stays in the provider.
///         Accounts are opened by the enclave itself through AccountsManager.
///         A call from this contract would register the opener as the owner, and LP would not see it.
contract EnclaveAccountOpener {
    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function spotAccount() external view returns (address) {
        _onlyEnclave();
        revert OpenFromEnclave();
    }

    function openAaveAccount() external view returns (address) {
        _onlyEnclave();
        revert OpenFromEnclave();
    }

    function _onlyEnclave() internal view {
        if (!AccessControlInter(addressProvider.getAddress("AccessControlInter")).getIsSendraEnclave(msg.sender)) {
            revert NotEnclave();
        }
    }

    error NotEnclave();
    error OpenFromEnclave();
}
