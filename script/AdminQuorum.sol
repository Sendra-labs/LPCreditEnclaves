// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

interface IQuorumProvider {
    function getAddress(string calldata name) external view returns (address);
    function proposeAddress(string calldata name, address addr) external;
}

interface IQuorumRoles {
    function allowContract(address account, string calldata name) external;
    function isProtocolContract(address account) external view returns (bool);
    function checkAdmin(address account) external view returns (bool);
}

/// @notice Three hot-admin signatures for AddressProvider and Roles.
abstract contract AdminQuorum is Script {
    function _keys() internal view returns (uint256[3] memory keys) {
        keys[0] = vm.envUint("HOT_ADMIN1_PRIVATE_KEY");
        keys[1] = vm.envUint("HOT_ADMIN2_PRIVATE_KEY");
        keys[2] = vm.envUint("HOT_ADMIN3_PRIVATE_KEY");
    }

    function _provider() internal view returns (IQuorumProvider) {
        return IQuorumProvider(vm.envAddress("ADDRESS_PROVIDER"));
    }

    function _propose(IQuorumProvider provider, string memory name, address addr) internal {
        uint256[3] memory keys = _keys();
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress(name, addr);
            vm.stopBroadcast();
        }
    }

    function _register(
        IQuorumProvider provider,
        IQuorumRoles roles,
        string memory name,
        address addr,
        bool allow
    ) internal {
        if (!_isCurrent(provider, name, addr)) _propose(provider, name, addr);
        if (!allow || roles.isProtocolContract(addr)) return;
        uint256[3] memory keys = _keys();
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            roles.allowContract(addr, name);
            vm.stopBroadcast();
        }
    }

    function _isCurrent(IQuorumProvider provider, string memory name, address addr) internal view returns (bool) {
        (bool ok, bytes memory data) =
            address(provider).staticcall(abi.encodeWithSignature("getAddress(string)", name));
        return ok && data.length >= 32 && abi.decode(data, (address)) == addr;
    }
}
