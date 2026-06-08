// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ISendraAddressProvider} from "../src/interfaces/iSendraCore/ISendraAddressProvider.sol";
import {LiquidityLogic} from "../src/core/execution/LiquidityLogic.sol";
import {IAddressProviderAdmin, SendraDeployLib} from "./interfaces/SendraDeploy.sol";

/**
 * @title DeployLiquidityLogic
 * @notice Deploys a new LiquidityLogic implementation and registers it in AddressProvider.
 *
 * @dev LiquidityLogic is used as the RPFP implementation when the factory creates enclave executors.
 *      Updating AddressProvider only affects **new** enclaves (createEnclave / acceptOffer).
 *      Already deployed enclave proxies keep their original implementation address.
 *
 * Prerequisites:
 *   - Sendra AddressProvider with LPCE stack already registered (factory, storage, etc.)
 *   - Protocol SendraStorage must support global pulse field 19 if using totalLosingCapitalIn
 *
 * .env:
 *   ADMIN_PK         - deployer private key (must be AddressProvider admin via Roles)
 *   ADDRESS_PROVIDER - existing Sendra AddressProvider
 *
 * Optional:
 *   LIQUIDITY_LOGIC  - if set, skips deploy and only registers this address
 *
 * Usage:
 *   set -a && source .env && set +a
 *   forge script script/DeployLiquidityLogic.s.sol:DeployLiquidityLogic --rpc-url arbitrum --broadcast -vvvv
 */
contract DeployLiquidityLogic is Script {
    string internal constant KEY_LIQUIDITY_LOGIC = "LiquidityLogic";

    function run() external {
        uint256 adminPk = vm.envUint("ADMIN_PK");
        address addressProviderAddr = vm.envAddress("ADDRESS_PROVIDER");
        address deployer = vm.addr(adminPk);

        ISendraAddressProvider ap = ISendraAddressProvider(addressProviderAddr);
        address previousLogic = ap.getAddress(KEY_LIQUIDITY_LOGIC);

        console2.log("=== Deploy LiquidityLogic ===");
        console2.log("Deployer:", deployer);
        console2.log("AddressProvider:", addressProviderAddr);
        console2.log("Deployer is Roles admin:", SendraDeployLib.roles(ap).checkAdmin(deployer));
        console2.log("Previous LiquidityLogic:", previousLogic);

        require(previousLogic != address(0), "LiquidityLogic not registered yet - run DeployLPCE first");

        vm.startBroadcast(adminPk);

        address newLogic = _deployOrLoad(addressProviderAddr);
        IAddressProviderAdmin(addressProviderAddr).setAddress(KEY_LIQUIDITY_LOGIC, newLogic);

        vm.stopBroadcast();

        console2.log("=== Done ===");
        console2.log("New LiquidityLogic:", newLogic);
        console2.log("Registered in AddressProvider as:", KEY_LIQUIDITY_LOGIC);
        console2.log("New enclaves will use the new implementation.");
    }

    function _deployOrLoad(address addressProviderAddr) internal returns (address) {
        address existing = vm.envOr("LIQUIDITY_LOGIC", address(0));
        if (existing != address(0)) {
            console2.log("Using LIQUIDITY_LOGIC from env (skip deploy):", existing);
            return existing;
        }

        LiquidityLogic deployed = new LiquidityLogic(addressProviderAddr);
        console2.log("Deployed LiquidityLogic:", address(deployed));
        return address(deployed);
    }
}
