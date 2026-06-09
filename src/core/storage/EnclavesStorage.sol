// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LPCE } from "../../libs/LPCE.lib.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISendraRoles } from "../../interfaces/iSendraCore/ISendraRoles.sol";

contract EnclavesStorage {

    address public immutable addressProvider;
    uint256 public constant MAX_ENCLAVES_PER_USER = 15;
    uint256 public constant MAX_ENCLAVES_PER_BATCH = 50;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    modifier onlyProtocol() {
        if(!ISendraRoles(ISendraAddressProvider(addressProvider).getAddress("Roles")).isProtocolContract(msg.sender)) revert NotProtocolContract();
        _;
    }

    mapping(address => uint256) public enclaveIdByAddress;
    mapping(uint256 => LPCE.Enclave) public enclaveById;
    mapping(address => mapping(uint256 => uint256[])) public enclaves; // address user => type (0 = as Lender, 1 = as Operator) => enclaveId
    mapping(uint256 => uint256[]) public lenderOffers; // batch id => enclaveId[]

    uint256 public nextEnclaveId;
    uint256 public batchId;

    function createEnclave(LPCE.Enclave memory enclave) public onlyProtocol returns (uint256) {
        uint256 enclaveId = nextEnclaveId;
        if(enclave.lender != address(0)) {
            addEnclaveToUser(enclave.lender, 0, enclaveId);
            if(enclave.operator == address(0)){
                uint256 _batchId = addOffer(enclaveId);
                enclave.batchId = _batchId;
            }
        }
        if(enclave.operator != address(0)) addEnclaveToUser(enclave.operator, 1, enclaveId);
        if(enclave.sendraExecutor != address(0)) enclaveIdByAddress[enclave.sendraExecutor] = enclaveId;
        enclaveById[enclaveId] = enclave;
        nextEnclaveId++;
        return enclaveId;
    }

    function acceptOffer(uint256 _batchId, uint256 _enclaveId, address _operator, address _sendraExecutor) public onlyProtocol {
        if(enclaveById[_enclaveId].operator != address(0)) revert OfferAlreadyAccepted();
        enclaveById[_enclaveId].operator = _operator;
        enclaveById[_enclaveId].sendraExecutor = _sendraExecutor;
        enclaveIdByAddress[_sendraExecutor] = _enclaveId;
        removeOffer(_batchId, _enclaveId);
        addEnclaveToUser(enclaveById[_enclaveId].operator, 1, _enclaveId);
    }

    function addOffer(uint256 _enclaveId) internal returns (uint256) {
        if(lenderOffers[batchId].length >= MAX_ENCLAVES_PER_BATCH) {
            batchId++;
        }
        lenderOffers[batchId].push(_enclaveId);
        return batchId;
    }

    function removeOffer(uint256 _batchId, uint256 _enclaveId) internal {
        uint256[] memory offersArray = lenderOffers[_batchId];
        bool found = false;
        for(uint256 i = 0; i < offersArray.length; i++) {
            if(offersArray[i] == _enclaveId) {
                lenderOffers[_batchId][i] = offersArray[offersArray.length - 1];
                lenderOffers[_batchId].pop();
                found = true;
                break;
            }
        }
        if(!found) revert OfferNotFound();
    }

    function cancelOffer(uint256 _batchId, uint256 _enclaveId, address owner) public onlyProtocol {
        if(enclaveById[_enclaveId].operator != address(0)) revert OfferAlreadyAccepted();
        if(enclaveById[_enclaveId].lender != owner) revert NotOwner();
        _removeEnclaveFromUser(enclaveById[_enclaveId].lender, 0, _enclaveId);
        removeOffer(_batchId, _enclaveId);
    }

    function addEnclaveToUser(address _user, uint256 _type, uint256 _enclaveId) public onlyProtocol {
        if(enclaves[_user][_type].length >= MAX_ENCLAVES_PER_USER) revert UserAlreadyHasMaxEnclaves();
        enclaves[_user][_type].push(_enclaveId);
    }

    function removeEnclaveFromUser(address _user, uint256 _type, uint256 _enclaveId) public onlyProtocol {
        _removeEnclaveFromUser(_user, _type, _enclaveId);
    }

    function revokeEnclaveListingForExecutor(address executor) public onlyProtocol {
        uint256 enclaveId = enclaveIdByAddress[executor];
        if(enclaveById[enclaveId].isDeposited) revert CannotRevokeDepositedEnclave();

        address lender = enclaveById[enclaveId].lender;
        address operator = enclaveById[enclaveId].operator;

        if(lender != address(0)) _removeEnclaveFromUser(lender, 0, enclaveId);
        if(operator != address(0)) _removeEnclaveFromUser(operator, 1, enclaveId);
    }

    function _removeEnclaveFromUser(address _user, uint256 _type, uint256 _enclaveId) internal {
        uint256[] memory enclavesArray = enclaves[_user][_type];
        for(uint256 i = 0; i < enclavesArray.length; i++) {
            if(enclavesArray[i] == _enclaveId) {
                enclaves[_user][_type][i] = enclavesArray[enclavesArray.length - 1];
                enclaves[_user][_type].pop();
                break;
            }
        }
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

    function getLenderOffers(uint256 _batchId) public view returns (uint256[] memory) {
        return lenderOffers[_batchId];
    }

    function getUserEnclaves(address _user, uint256 _type) public view returns (uint256[] memory) {
        return enclaves[_user][_type];
    }

    function getEnclaves(uint256 _fromIndex, uint256 _toIndex) public view returns (LPCE.Enclave[] memory) {
        LPCE.Enclave[] memory enclavesArray = new LPCE.Enclave[](_toIndex - _fromIndex);
        for(uint256 i = _fromIndex; i < _toIndex; i++) {
            enclavesArray[i] = enclaveById[i];
        }
        return enclavesArray;
    }

    function getEnclavesByIds(uint256[] memory _enclaveIds) public view returns (LPCE.Enclave[] memory) {
        LPCE.Enclave[] memory enclavesArray = new LPCE.Enclave[](_enclaveIds.length);
        for(uint256 i = 0; i < _enclaveIds.length; i++) {
            enclavesArray[i] = enclaveById[_enclaveIds[i]];
        }
        return enclavesArray;
    }

    function getEnclavesCount() public view returns (uint256) {
        return nextEnclaveId;
    }

    function getCurrentBatch() public view returns (uint256) {
        return batchId;
    }

    error NotProtocolContract();
    error CannotRevokeDepositedEnclave();
    error UserAlreadyHasMaxEnclaves();
    error OfferAlreadyAccepted();
    error NotOwner();
    error OfferNotFound();
}