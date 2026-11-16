// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { RPFPStorage } from "srpe/src/core/storage/RPFPStorage.sol";
import { UniversalRuler } from "srpe/src/core/UniversalRuler.sol";
import { UniversalExecutorFactory } from "srpe/src/core/UniversalExecutorFactory.sol";
import { RPFPDeployer } from "srpe/src/core/RPFPDeployer.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/**
 * @notice Deploys SRPE and registers it on the current AddressProvider.
 *         Does not touch SendraStorage. RPFPDeployer needs three allowContract votes
 *         because it is the only writer of RPFPStorage.
 *
 *         WSL, same shell as the core deploy:
 *           forge script script/DeploySRPE.s.sol --rpc-url arbitrum
 *           forge script script/DeploySRPE.s.sol --rpc-url arbitrum --broadcast
 */
contract DeploySRPE is AdminQuorum {
    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        address sendraStorage = provider.getAddress("SendraStorage");

        vm.startBroadcast(_keys()[0]);
        RPFPStorage rpfpStorage = new RPFPStorage(address(provider));
        UniversalRuler ruler = new UniversalRuler(address(provider), address(rpfpStorage), sendraStorage);
        UniversalExecutorFactory factory = new UniversalExecutorFactory();
        RPFPDeployer deployer = new RPFPDeployer(address(provider));
        vm.stopBroadcast();

        _register(provider, roles, "RPFPStorage", address(rpfpStorage), false);
        _register(provider, roles, "UniversalRuler", address(ruler), false);
        _register(provider, roles, "UniversalExecutorFactory", address(factory), false);
        _register(provider, roles, "RPFPDeployer", address(deployer), true);

        console2.log("RPFPStorage", address(rpfpStorage));
        console2.log("UniversalRuler", address(ruler));
        console2.log("UniversalExecutorFactory", address(factory));
        console2.log("RPFPDeployer", address(deployer));
    }

    error WrongChain();
}
