// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { ISendraAddressProvider } from "../src/interfaces/iSendraCore/ISendraAddressProvider.sol";
import { EnclavePulse } from "../src/core/execution/EnclavePulse.sol";
import { EnclaveAccountOpener } from "../src/core/execution/EnclaveAccountOpener.sol";
import { EnclaveDesk } from "../src/core/execution/EnclaveDesk.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/**
 * @title DeployEnclavePlus
 * @notice Registers the enclave pieces that are not in DeployLPCE:
 *         EnclavePulse, EnclaveAccountOpener and EnclaveDesk.
 *
 *         Run after DeploySRPE and DeployLPCE. SRPE and LiquidityLogic stay
 *         as those scripts left them. SwapAccountant already reads EnclavePulse
 *         from the provider at call time, so it does not need a redeploy.
 *
 *         WSL:
 *           forge script script/DeployEnclavePlus.s.sol --rpc-url arbitrum
 *           forge script script/DeployEnclavePlus.s.sol --rpc-url arbitrum --broadcast
 */
contract DeployEnclavePlus is AdminQuorum {
    function run() external {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        ISendraAddressProvider ap = ISendraAddressProvider(address(provider));

        console2.log("=== Enclave Plus ===");
        console2.log("Deployer:", vm.addr(_keys()[0]));
        console2.log("AddressProvider:", address(provider));

        _require(ap, "Roles");
        _require(ap, "EnclavesStorage");
        _require(ap, "AccessControlInter");
        _require(ap, "RPFPDeployer");
        _require(ap, "AccountDeployer");
        _require(ap, "AccountAccessControl");
        _require(ap, "USDC");
        _require(ap, "SwapRouter");

        vm.startBroadcast(_keys()[0]);
        EnclavePulse pulse = new EnclavePulse(address(provider));
        EnclaveAccountOpener opener = new EnclaveAccountOpener(address(provider));
        EnclaveDesk desk = new EnclaveDesk(address(provider));
        vm.stopBroadcast();

        _register(provider, roles, "EnclavePulse", address(pulse), false);
        _register(provider, roles, "EnclaveAccountOpener", address(opener), true);
        _register(provider, roles, "EnclaveDesk", address(desk), false);

        console2.log("EnclavePulse", address(pulse));
        console2.log("EnclaveAccountOpener", address(opener));
        console2.log("EnclaveDesk", address(desk));
    }

    function _require(ISendraAddressProvider ap, string memory key) internal view {
        address addr = ap.getAddress(key);
        require(addr != address(0), key);
        console2.log(key, addr);
    }

    error WrongChain();
}
