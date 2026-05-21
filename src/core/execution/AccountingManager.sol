//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlInter} from "../storage/security/AccessControlInter.sol";
import {ISendraAddressProvider} from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import {ISendraStorage} from "../../interfaces/iSendraCore/ISendraStorage.sol";

// This contract is protocol contract and is allowed to write on the Sendra storage. 
/* 
deployment instructions:
1. this contract must be Sendra Protocol Contract in Sendra Roles
2. Must be set as the AccountingManager in the AddressProvider
*/
contract AccountingManager {

    address public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    modifier onlyEnclave() {
        require(AccessControlInter(addressProvider.getAddress("AccessControlInter")).getIsSendraEnclave(msg.sender), "Not a Sendra Enclave");
        _;
    }


    // Each enclave is treated as a user by Sendra Storage.
    function initializePositionForEnclave(bytes[] memory _newPositionData) public onlyEnclave {

        uint256 positionId = sendraStorage.getUser(msg.sender).totalPositions + 1;

        ISendraStorage(addressProvider.getAddress("SendraStorage")).addPositionToUser(msg.sender, SendraLib.Position({
            positionType: 2, // Uniswap LP
            id: positionId,
            pnl: 0,
            isActive: true,
            positionData: _newPositionData
        }));

    }

    // This function registers a specific type of positions for enclaves for Operators and Lenders. Type 3.

    function initializePositionForUser(address _user, bytes[] memory _newPositionData) public onlyEnclave {

        uint256 positionId = sendraStorage.getUser(_user).totalPositions + 1;

        ISendraStorage(addressProvider.getAddress("SendraStorage")).addPositionToUser(_user, SendraLib.Position({
            positionType: 3, // ENCLAVE Uniswap LP Position
            id: positionId,
            pnl: 0,
            isActive: true,
            positionData: _newPositionData
        }));
    
    }

    function managePositionForEnclave(uint256 positionId, uint256 positionField, bytes memory value) public onlyEnclave {
        ISendraStorage(addressProvider.getAddress("SendraStorage")).updateUserPositionData(msg.sender, positionId, positionField, value);
    }

    function manageFullPositionForEnclave(uint256 positionId, SendraLib.Position memory position) public onlyEnclave {
        ISendraStorage(addressProvider.getAddress("SendraStorage")).updateUserFullPosition(msg.sender, positionId, position);
    }

    function managePositionForUser(address _user, uint256 positionId, uint256 positionField, bytes memory value) public onlyEnclave {
        ISendraStorage(addressProvider.getAddress("SendraStorage")).updateUserPositionData(_user, positionId, positionField, value);
    }

    function updateFullPositionForUser(address _user, uint256 positionId, SendraLib.Position memory position) public onlyEnclave {
        ISendraStorage(addressProvider.getAddress("SendraStorage")).updateUserFullPosition(_user, positionId, position);
    }

    function decreaseGlobalPositionActivePositions(address _account) public onlyEnclave {
        ISendraStorage(addressProvider.getAddress("SendraStorage")).decreaseGlobalPositionActivePositions(_account);
    }
    
}