// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { AdminQuorum, IQuorumProvider } from "./AdminQuorum.sol";

/**
 * @notice Closes the EnclaveDesk quorum left open by DeployEnclavePlus.
 *         Admin 1 already proposed. This sends the votes of admins 2 and 3
 *         for the desk already deployed. It does not deploy anything.
 *
 *         WSL:
 *           forge script script/FinishEnclaveDesk.s.sol --rpc-url arbitrum --broadcast
 */
contract FinishEnclaveDesk is AdminQuorum {
    address internal constant DESK = 0xAbAD2A808D54e7BC8698D446896BD2aC68a36c9A;

    function run() external {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();

        if (_isCurrent(provider, "EnclaveDesk", DESK)) {
            console2.log("EnclaveDesk already", DESK);
            return;
        }

        uint256[3] memory keys = _keys();
        for (uint256 i = 1; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress("EnclaveDesk", DESK);
            vm.stopBroadcast();
        }

        console2.log("EnclaveDesk", DESK);
    }

    error WrongChain();
}
