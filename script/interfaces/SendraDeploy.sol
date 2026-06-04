// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISendraAddressProvider} from "../../src/interfaces/iSendraCore/ISendraAddressProvider.sol";

/// @dev Admin surface of Sendra `AddressProvider` (see SendraLabsContracts).
interface IAddressProviderAdmin {
    function setAddress(string calldata contractName, address _address) external;
}

/// @dev Admin surface of Sendra `Roles` (see SendraLabsContracts).
interface IRolesAdmin {
    function allowContract(address _contract, string calldata _name) external;

    function isProtocolContract(address _contract) external view returns (bool);

    function checkAdmin(address _admin) external view returns (bool);
}

/// @dev Helper to resolve Roles from AddressProvider.
library SendraDeployLib {
    function roles(ISendraAddressProvider ap) internal view returns (IRolesAdmin) {
        return IRolesAdmin(ap.getAddress("Roles"));
    }
}
