// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityOrchestratorEvo } from "../src/core/execution/LiquidityOrchestratorEvo.sol";

/**
 * Nuevo orquestador. El cierre de LP reescala el minimo de salida al trozo
 * real (fees y principal por separado). Los enclaves ya desplegados leen
 * "LiquidityOrchestratorEvo" del provider en cada close, asi que la posicion
 * abierta se cierra despues de este script. No hay que retirar liquidez antes.
 *
 * Desde LPCreditEnclaves/ en WSL:
 *   forge script script/UpgradeLiquidityOrchestratorEvo.s.sol --target-contract UpgradeLiquidityOrchestratorEvo --rpc-url arbitrum --broadcast
 */
contract UpgradeLiquidityOrchestratorEvo is Script {
    address constant ADDRESS_PROVIDER = 0xaF7A2feFBA6Acc09e62011d0359dC06e0e1245f5;

    function run() public {
        uint256 pk = vm.envUint("ADMIN1_PRIVATE_KEY");
        IProvider provider = IProvider(ADDRESS_PROVIDER);

        vm.startBroadcast(pk);
        LiquidityOrchestratorEvo orchestrator = new LiquidityOrchestratorEvo(ADDRESS_PROVIDER);
        provider.setAddress("LiquidityOrchestratorEvo", address(orchestrator));
        vm.stopBroadcast();

        console.log("LiquidityOrchestratorEvo:", address(orchestrator));
    }
}

interface IProvider {
    function getAddress(string calldata name) external view returns (address);
    function setAddress(string calldata name, address addr) external;
}
