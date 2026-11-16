// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console2 } from "forge-std/Script.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/**
 * @notice Points the live AddressProvider at the previous enclave stack so an
 *         already-open enclave can close, then points it back at Enclaves v3 / SRPE v2.
 *
 *         The executor, its rules and its implementation live in the old RPFPStorage.
 *         Enclave rows, the enclave flag and the capital counter live in the old
 *         storage contracts. The LP account reads LiquidityOrchestratorEvo on every
 *         close. Factory, LiquidityLogic, RPFPDeployer and UniversalExecutorFactory
 *         stay on v3: nothing already deployed reads them to close.
 *
 *         Legacy addresses are the deploy registered just before v3
 *         (SRPE run-1793195851621, LPCE run-1793195994995, desk run-1793210708707).
 *
 *         WSL, from LPCreditEnclaves/:
 *           ENCLAVE_PROVIDER_MODE=legacy forge script script/RepointEnclaveProvider.s.sol --rpc-url arbitrum --broadcast
 *           # close the position, withdraw credit, revoke the enclave
 *           ENCLAVE_PROVIDER_MODE=current forge script script/RepointEnclaveProvider.s.sol --rpc-url arbitrum --broadcast
 */
contract RepointEnclaveProvider is AdminQuorum {
    struct Slot {
        string name;
        address legacy;
        address current;
        bool allow;
    }

    function run() external {
        if (block.chainid != 42161) revert WrongChain();

        string memory mode = vm.envString("ENCLAVE_PROVIDER_MODE");
        bool legacy = keccak256(bytes(mode)) == keccak256("legacy");
        bool current = keccak256(bytes(mode)) == keccak256("current");
        if (!legacy && !current) revert UnknownMode(mode);

        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        Slot[] memory slots = _slots();

        console2.log(legacy ? "Mode: legacy" : "Mode: current");
        for (uint256 i = 0; i < slots.length; i++) {
            address target = legacy ? slots[i].legacy : slots[i].current;
            console2.log(slots[i].name, target);
            _register(provider, roles, slots[i].name, target, slots[i].allow);
        }
    }

    /// @dev Order is irrelevant. Each key is one the old executor resolves while closing.
    function _slots() internal pure returns (Slot[] memory slots) {
        slots = new Slot[](8);

        slots[0] = Slot("RPFPStorage", 0xCE57938Af57631EDE6B253358B041189dAb18b8B, 0x59944DFe70715162d4935Aa8A1a4D1e67CFE574A, false);
        slots[1] = Slot("UniversalRuler", 0x9D3e143fa08b04e6A318935E228A533766A31D3a, 0x462Df1FcC364e452b71e1c0EB1d653EB3462BE15, false);

        slots[2] = Slot("EnclavesStorage", 0x21e81f52024d36F3F1560A7Fc2fe8Cf048f9b526, 0xC72681c1f3D81880E28dCF37aF536dcB7a4Fd8Df, true);
        slots[3] = Slot("AccessControlInter", 0x9f67dccaFDe50C88a1Efc4807010C66E83b0E35C, 0x58Dd81e9837d5fB28902920F9711824Aa208d65E, true);
        slots[4] = Slot("AccountingManager", 0x876160bB747afE2180BeFd32362f67ddc955Da89, 0xd3BB11DF824e98313D772FC9007a804889f9ca36, true);
        slots[5] = Slot("CapitalUnderManagement", 0xD09636918C4d23A504cf7edC0e8ec081Bba74084, 0x937345C6D2E647D1b9AF9FcaC89F63e5a1eac7A3, true);

        slots[6] = Slot("LiquidityOrchestratorEvo", 0x19812e8D88BdE50252c28D5d09B9d77d32557719, 0x65d9b1A61729fAA46D8E461289F9F52ce24B7E58, false);
        slots[7] = Slot("EnclaveDesk", 0x380AA4DF99BDE4e3686C565252050Fc9b515462F, 0xAbAD2A808D54e7BC8698D446896BD2aC68a36c9A, false);
    }

    error WrongChain();
    error UnknownMode(string mode);
}
