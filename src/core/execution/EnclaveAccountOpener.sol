// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { AccessControlInter } from "../storage/security/AccessControlInter.sol";

interface IAccountDeployerMin {
    function deployMinimal(address owner) external returns (address);
}

interface IAccountAccessMin {
    function setIsProtocolAccount(address account) external;
}

/// @notice Opens Sendra accounts owned by an enclave executor.
///         Spot reuses one account. Each Aave strategy gets a fresh one.
///         Must be a Sendra protocol contract: it calls AccountDeployer and AccountAccessControl.
contract EnclaveAccountOpener {
    ISendraAddressProvider public immutable addressProvider;

    mapping(address => address) public spotOf;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function spotAccount() external returns (address account) {
        _onlyEnclave();
        account = spotOf[msg.sender];
        if (account != address(0)) return account;
        account = _deploy(msg.sender);
        spotOf[msg.sender] = account;
    }

    function openAaveAccount() external returns (address account) {
        _onlyEnclave();
        account = _deploy(msg.sender);
    }

    function _onlyEnclave() internal view {
        if (!AccessControlInter(addressProvider.getAddress("AccessControlInter")).getIsSendraEnclave(msg.sender)) {
            revert NotEnclave();
        }
    }

    function _deploy(address owner) internal returns (address account) {
        account = IAccountDeployerMin(addressProvider.getAddress("AccountDeployer")).deployMinimal(owner);
        IAccountAccessMin(addressProvider.getAddress("AccountAccessControl")).setIsProtocolAccount(account);
    }

    error NotEnclave();
}
