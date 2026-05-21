// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LPCE } from "../../library/LPCE.lib.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISendraRoles } from "../../interfaces/iSendraCore/ISendraRoles.sol";

contract EnclavesStorage {

    address public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    modifier onlyProtocol() {
        if(!ISendraRoles(ISendraAddressProvider(addressProvider).getAddress("Roles")).isProtocolContract(msg.sender)) revert NotProtocolContract();
        _;
    }

    mapping(address => uint256) public enclaveIdByAddress;
    mapping(uint256 => LPCE.Enclave) public enclaveById;

    uint256 public nextEnclaveId;

    function createEnclave(LPCE.Enclave memory enclave) public onlyProtocol returns (uint256) {
        uint256 enclaveId = nextEnclaveId;
        enclaveIdByAddress[enclave.sendraExecutor] = enclaveId;
        enclaveById[enclaveId] = enclave;
        nextEnclaveId++;
        return enclaveId;
    }

    function pauseExecution() public {
        enclaveById[enclaveIdByAddress[msg.sender]].isPaused = true;
    }

    function unpauseExecution() public {
        enclaveById[enclaveIdByAddress[msg.sender]].isPaused = false;
    }

    function setIsDeposited() public {
        enclaveById[enclaveIdByAddress[msg.sender]].isDeposited = true;
    }

    function setLenderPositionId(uint256 _lenderPositionId) public {
        enclaveById[enclaveIdByAddress[msg.sender]].lenderPositionId = _lenderPositionId;
    }

    function setOperatorPositionId(uint256 _operatorPositionId) public {
        enclaveById[enclaveIdByAddress[msg.sender]].operatorPositionId = _operatorPositionId;
    }

    // VIEW FUNCTIONS

    function isPausedView(address _sendraExecutor) public view returns (bool) {
        return enclaveById[enclaveIdByAddress[_sendraExecutor]].isPaused;
    }

    function isPausedControl() public view returns (bool) {
        return enclaveById[enclaveIdByAddress[msg.sender]].isPaused;
    }

    function isDepositedView(address _sendraExecutor) public view returns (bool) {
        return enclaveById[enclaveIdByAddress[_sendraExecutor]].isDeposited;
    }

    function isDepositedControl() public view returns (bool) {
        return enclaveById[enclaveIdByAddress[msg.sender]].isDeposited;
    }

    function getEnclaveId(address _sendraExecutor) public view returns (uint256) {
        return enclaveIdByAddress[_sendraExecutor];
    }

    function getEnclave(uint256 _enclaveId) public view returns (LPCE.Enclave memory) {
        return enclaveById[_enclaveId];
    }

    function getEnclaveByAddress(address _sendraExecutor) public view returns (LPCE.Enclave memory) {
        return enclaveById[enclaveIdByAddress[_sendraExecutor]];
    }

    error NotProtocolContract();

}