// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../interfaces/iSendraCore/ISendraAddressProvider.sol";

interface IAccountsManager {
    function accountByOwner(address owner) external view returns (address);
    function initializeAccount() external returns (address);
    function openAccount() external returns (address);
}

/// @notice Opens the enclave's Sendra accounts.
///         These calls are made from a delegatecall, so AccountsManager sees the enclave as msg.sender.
///         The first account is the shared spot and Uniswap LP account. Aave gets another one.
library EnclaveAccounts {
    function spot(address provider) internal returns (address account) {
        IAccountsManager mgr = _mgr(provider);
        account = mgr.accountByOwner(address(this));
        if (account == address(0)) account = mgr.initializeAccount();
    }

    function aave(address provider) internal returns (address account) {
        IAccountsManager mgr = _mgr(provider);
        if (mgr.accountByOwner(address(this)) == address(0)) mgr.initializeAccount();
        account = mgr.openAccount();
    }

    function _mgr(address provider) private view returns (IAccountsManager) {
        return IAccountsManager(ISendraAddressProvider(provider).getAddress("AccountsManager"));
    }
}
