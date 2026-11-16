// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { LiquidityLogic } from "../src/core/execution/LiquidityLogic.sol";
import { AdminQuorum, IQuorumProvider } from "./AdminQuorum.sol";

/**
 * @title DeployLiquidityLogic
 * @notice Replaces LiquidityLogic after DeployLPCE. Do not run this on a fresh deploy.
 *         New enclaves read the implementation from the provider at create time.
 *         Existing enclave proxies keep their original implementation.
 *
 *         WSL:
 *           forge script script/DeployLiquidityLogic.s.sol --rpc-url arbitrum --broadcast
 *
 *         Optional: LIQUIDITY_LOGIC=0x... registers that address instead of deploying.
 */
contract DeployLiquidityLogic is AdminQuorum {
    string internal constant KEY_LIQUIDITY_LOGIC = "LiquidityLogic";

    function run() external {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        address previousLogic = provider.getAddress(KEY_LIQUIDITY_LOGIC);

        console2.log("=== Deploy LiquidityLogic ===");
        console2.log("Deployer:", vm.addr(_keys()[0]));
        console2.log("AddressProvider:", address(provider));
        console2.log("Previous LiquidityLogic:", previousLogic);

        vm.startBroadcast(_keys()[0]);
        address newLogic = _deployOrLoad(address(provider));
        vm.stopBroadcast();

        _propose(provider, KEY_LIQUIDITY_LOGIC, newLogic);

        console2.log("New LiquidityLogic:", newLogic);
    }

    function _deployOrLoad(address addressProviderAddr) internal returns (address) {
        address existing = vm.envOr("LIQUIDITY_LOGIC", address(0));
        if (existing != address(0)) {
            console2.log("Using LIQUIDITY_LOGIC from env:", existing);
            return existing;
        }
        LiquidityLogic deployed = new LiquidityLogic(addressProviderAddr);
        console2.log("Deployed LiquidityLogic:", address(deployed));
        return address(deployed);
    }

    error WrongChain();
}
