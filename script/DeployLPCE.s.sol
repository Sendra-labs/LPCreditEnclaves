// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ISendraAddressProvider} from "../src/interfaces/iSendraCore/ISendraAddressProvider.sol";
import {EnclavesStorage} from "../src/core/storage/EnclavesStorage.sol";
import {AccessControlInter} from "../src/core/storage/security/AccessControlInter.sol";
import {AccountingManager} from "../src/core/execution/AccountingManager.sol";
import {LiquidityLogic} from "../src/core/execution/LiquidityLogic.sol";
import {LiquidityOrchestratorEvo} from "../src/core/execution/LiquidityOrchestratorEvo.sol";
import {LiquidityCreditEnclaveFactory} from "../src/core/factory/LiquidityCreditEnclaveFactory.sol";
import {CapitalUnderManagement} from "../src/core/storage/CapitalUnderManagement.sol";
import { AdminQuorum, IQuorumProvider, IQuorumRoles } from "./AdminQuorum.sol";

/**
 * @title DeployLPCE
 * @notice Deploys the LP Credit Enclaves stack and registers it with three hot admins.
 *
 * Prerequisites already on the AddressProvider:
 *   Roles, SendraStorage, RPFPDeployer, UniversalExecutorFactory, RPFPStorage,
 *   USDC, LiquidityManager, SwapRouter, UniswapNFTPositionManager
 *
 * Run DeploySRPE.s.sol first. WSL, same shell:
 *   forge script script/DeployLPCE.s.sol --rpc-url arbitrum
 *   forge script script/DeployLPCE.s.sol --rpc-url arbitrum --broadcast
 *
 * Optional (skip that deploy and register the given address):
 *   ENCLAVES_STORAGE, ACCESS_CONTROL_INTER, ACCOUNTING_MANAGER,
 *   CAPITAL_UNDER_MANAGEMENT, LIQUIDITY_LOGIC, LIQUIDITY_ORCHESTRATOR_EVO,
 *   LIQUIDITY_CREDIT_ENCLAVE_FACTORY
 */
contract DeployLPCE is AdminQuorum {
    struct Deployed {
        EnclavesStorage enclavesStorage;
        AccessControlInter accessControlInter;
        AccountingManager accountingManager;
        CapitalUnderManagement capitalUnderManagement;
        LiquidityLogic liquidityLogic;
        LiquidityOrchestratorEvo liquidityOrchestratorEvo;
        LiquidityCreditEnclaveFactory factory;
    }

    string internal constant KEY_ENCLAVES_STORAGE = "EnclavesStorage";
    string internal constant KEY_ACCESS_CONTROL = "AccessControlInter";
    string internal constant KEY_ACCOUNTING_MANAGER = "AccountingManager";
    string internal constant KEY_CAPITAL_UNDER_MANAGEMENT = "CapitalUnderManagement";
    string internal constant KEY_LIQUIDITY_LOGIC = "LiquidityLogic";
    string internal constant KEY_LIQUIDITY_ORCHESTRATOR_EVO = "LiquidityOrchestratorEvo";
    string internal constant KEY_FACTORY = "LiquidityCreditEnclaveFactory";

    string[] internal prerequisiteKeys = [
        "Roles",
        "SendraStorage",
        "RPFPDeployer",
        "UniversalExecutorFactory",
        "RPFPStorage",
        "USDC",
        "LiquidityManager",
        "SwapRouter",
        "UniswapNFTPositionManager"
    ];

    function run() external {
        if (block.chainid != 42161) revert WrongChain();
        IQuorumProvider provider = _provider();
        IQuorumRoles roles = IQuorumRoles(provider.getAddress("Roles"));
        address deployer = vm.addr(_keys()[0]);

        console2.log("=== LPCE Deploy ===");
        console2.log("Deployer:", deployer);
        console2.log("AddressProvider:", address(provider));
        console2.log("Deployer is Roles admin:", roles.checkAdmin(deployer));

        _verifyPrerequisites(ISendraAddressProvider(address(provider)));

        vm.startBroadcast(_keys()[0]);
        Deployed memory d = _deployOrLoad(address(provider));
        vm.stopBroadcast();

        _register(provider, roles, KEY_ENCLAVES_STORAGE, address(d.enclavesStorage), true);
        _register(provider, roles, KEY_ACCESS_CONTROL, address(d.accessControlInter), true);
        _register(provider, roles, KEY_ACCOUNTING_MANAGER, address(d.accountingManager), true);
        _register(provider, roles, KEY_CAPITAL_UNDER_MANAGEMENT, address(d.capitalUnderManagement), true);
        _register(provider, roles, KEY_LIQUIDITY_LOGIC, address(d.liquidityLogic), false);
        _register(provider, roles, KEY_LIQUIDITY_ORCHESTRATOR_EVO, address(d.liquidityOrchestratorEvo), false);
        _register(provider, roles, KEY_FACTORY, address(d.factory), true);

        _logSummary(d);
    }

    function _deployOrLoad(address addressProviderAddr) internal returns (Deployed memory d) {
        d.enclavesStorage = _loadOrDeployEnclavesStorage(addressProviderAddr);
        d.accessControlInter = _loadOrDeployAccessControlInter(addressProviderAddr);
        d.accountingManager = _loadOrDeployAccountingManager(addressProviderAddr);
        d.capitalUnderManagement = _loadOrDeployCapitalUnderManagement(addressProviderAddr);
        d.liquidityLogic = _loadOrDeployLiquidityLogic(addressProviderAddr);
        d.liquidityOrchestratorEvo = _loadOrDeployLiquidityOrchestratorEvo(addressProviderAddr);
        d.factory = _loadOrDeployFactory(addressProviderAddr);
    }

    function _loadOrDeployEnclavesStorage(address ap) internal returns (EnclavesStorage) {
        address existing = vm.envOr("ENCLAVES_STORAGE", address(0));
        if (existing != address(0)) {
            console2.log("Using ENCLAVES_STORAGE:", existing);
            return EnclavesStorage(existing);
        }
        EnclavesStorage deployed = new EnclavesStorage(ap);
        console2.log("Deployed EnclavesStorage:", address(deployed));
        return deployed;
    }

    function _loadOrDeployAccessControlInter(address ap) internal returns (AccessControlInter) {
        address existing = vm.envOr("ACCESS_CONTROL_INTER", address(0));
        if (existing != address(0)) {
            console2.log("Using ACCESS_CONTROL_INTER:", existing);
            return AccessControlInter(existing);
        }
        AccessControlInter deployed = new AccessControlInter(ap);
        console2.log("Deployed AccessControlInter:", address(deployed));
        return deployed;
    }

    function _loadOrDeployAccountingManager(address ap) internal returns (AccountingManager) {
        address existing = vm.envOr("ACCOUNTING_MANAGER", address(0));
        if (existing != address(0)) {
            console2.log("Using ACCOUNTING_MANAGER:", existing);
            return AccountingManager(existing);
        }
        AccountingManager deployed = new AccountingManager(ap);
        console2.log("Deployed AccountingManager:", address(deployed));
        return deployed;
    }

    function _loadOrDeployCapitalUnderManagement(address ap) internal returns (CapitalUnderManagement) {
        address existing = vm.envOr("CAPITAL_UNDER_MANAGEMENT", address(0));
        if (existing != address(0)) {
            console2.log("Using CAPITAL_UNDER_MANAGEMENT:", existing);
            return CapitalUnderManagement(existing);
        }
        CapitalUnderManagement deployed = new CapitalUnderManagement(ap);
        console2.log("Deployed CapitalUnderManagement:", address(deployed));
        return deployed;
    }

    function _loadOrDeployLiquidityLogic(address ap) internal returns (LiquidityLogic) {
        address existing = vm.envOr("LIQUIDITY_LOGIC", address(0));
        if (existing != address(0)) {
            console2.log("Using LIQUIDITY_LOGIC:", existing);
            return LiquidityLogic(existing);
        }
        LiquidityLogic deployed = new LiquidityLogic(ap);
        console2.log("Deployed LiquidityLogic (implementation):", address(deployed));
        return deployed;
    }

    function _loadOrDeployLiquidityOrchestratorEvo(address ap) internal returns (LiquidityOrchestratorEvo) {
        address existing = vm.envOr("LIQUIDITY_ORCHESTRATOR_EVO", address(0));
        if (existing != address(0)) {
            console2.log("Using LIQUIDITY_ORCHESTRATOR_EVO:", existing);
            return LiquidityOrchestratorEvo(existing);
        }
        LiquidityOrchestratorEvo deployed = new LiquidityOrchestratorEvo(ap);
        console2.log("Deployed LiquidityOrchestratorEvo:", address(deployed));
        return deployed;
    }

    function _loadOrDeployFactory(address ap) internal returns (LiquidityCreditEnclaveFactory) {
        address existing = vm.envOr("LIQUIDITY_CREDIT_ENCLAVE_FACTORY", address(0));
        if (existing != address(0)) {
            console2.log("Using LIQUIDITY_CREDIT_ENCLAVE_FACTORY:", existing);
            return LiquidityCreditEnclaveFactory(existing);
        }
        LiquidityCreditEnclaveFactory deployed = new LiquidityCreditEnclaveFactory(ap);
        console2.log("Deployed LiquidityCreditEnclaveFactory:", address(deployed));
        return deployed;
    }

    function _verifyPrerequisites(ISendraAddressProvider ap) internal view {
        console2.log("--- Prerequisites ---");
        for (uint256 i = 0; i < prerequisiteKeys.length; i++) {
            string memory key = prerequisiteKeys[i];
            address addr = ap.getAddress(key);
            require(addr != address(0), string.concat("Missing prerequisite in AddressProvider: ", key));
            console2.log(key, addr);
        }
    }

    function _logSummary(Deployed memory d) internal pure {
        console2.log("=== Deployment summary ===");
        console2.log("EnclavesStorage:", address(d.enclavesStorage));
        console2.log("AccessControlInter:", address(d.accessControlInter));
        console2.log("AccountingManager:", address(d.accountingManager));
        console2.log("CapitalUnderManagement:", address(d.capitalUnderManagement));
        console2.log("LiquidityLogic:", address(d.liquidityLogic));
        console2.log("LiquidityOrchestratorEvo:", address(d.liquidityOrchestratorEvo));
        console2.log("LiquidityCreditEnclaveFactory:", address(d.factory));
    }

    error WrongChain();
}
