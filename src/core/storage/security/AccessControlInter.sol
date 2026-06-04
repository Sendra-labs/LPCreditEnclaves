//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISendraAddressProvider} from "../../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISendraRoles } from "../../../interfaces/iSendraCore/ISendraRoles.sol";

/*
Deployment instructions:
1. This contract must be Sendra Protocol Contract in Sendra Roles
2. Must be set as the AccessControlInter in the AddressProvider
*/

contract AccessControlInter {

    ISendraAddressProvider public immutable addressProvider;
    ISendraRoles public immutable sendraRoles;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
        sendraRoles = ISendraRoles(addressProvider.getAddress("Roles"));
    }

    modifier onlyProtocol() {
        require(sendraRoles.isProtocolContract(msg.sender), "Not a protocol contract");
        _;
    }

    mapping(address => bool) public isSendraEnclave;

    function setIsSendraEnclave(address _enclave, bool _isSendraEnclave) public onlyProtocol {
        isSendraEnclave[_enclave] = _isSendraEnclave;
    }

    function getIsSendraEnclave(address _enclave) public view returns (bool) {
        return isSendraEnclave[_enclave];
    }

    function accessControl() public view returns (bool) {
        return isSendraEnclave[msg.sender];
    }

}