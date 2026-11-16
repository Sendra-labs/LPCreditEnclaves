// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { RPFPDeployer } from "srpe/src/core/RPFPDeployer.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/**
 * @notice Replaces RPFPDeployer only. Storage, ruler and the executor factory stay.
 *         The previous deployer rejects an enclave with more than 12 actions
 *         (InvalidFunctionSelectors). The factory now registers 20.
 *         The new deployer must be allowlisted: it is the writer of RPFPStorage.
 *
 *         WSL, from LPCreditEnclaves/:
 *           forge script script/RedeployRPFPDeployer.s.sol --rpc-url arbitrum --broadcast
 */
contract RedeployRPFPDeployer is AdminQuorum {
    function run() public {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        address previous = provider.getAddress("RPFPDeployer");

        vm.startBroadcast(_keys()[0]);
        RPFPDeployer deployer = new RPFPDeployer(address(provider));
        vm.stopBroadcast();

        _register(provider, roles, "RPFPDeployer", address(deployer), true);
        console2.log("RPFPDeployer", address(deployer));
        console2.log("previous", previous);
    }

    error WrongChain();
}
