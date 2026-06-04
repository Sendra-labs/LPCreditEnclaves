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
import {IAddressProviderAdmin, IRolesAdmin, SendraDeployLib} from "./interfaces/SendraDeploy.sol";

/**
 * @title DeployLPCE
 * @notice Deploys LP Credit Enclaves stack and registers it in Sendra AddressProvider + Roles.
 *
 * Prerequisites (already deployed in Sendra core):
 *   Roles, SendraStorage, RPFPDeployer, UniversalExecutorFactory, RPFPStorage,
 *   USDC, LiquidityManager, SwapRouter, UniswapNFTPositionManager
 *
 * .env:
 *   ADMIN_PK           - deployer private key (must be Sendra Roles admin)
 *   ADDRESS_PROVIDER   - existing Sendra AddressProvider
 *
 * Usage:
 *   forge script script/DeployLPCE.s.sol:DeployLPCE --rpc-url $RPC_URL --broadcast -vvvv
 *
 * Optional (skip deploy, only register existing addresses):
 *   ENCLAVES_STORAGE=0x...
 *   ACCESS_CONTROL_INTER=0x...
 *   ACCOUNTING_MANAGER=0x...
 *   LIQUIDITY_LOGIC=0x...
 *   LIQUIDITY_ORCHESTRATOR_EVO=0x...
 *   LIQUIDITY_CREDIT_ENCLAVE_FACTORY=0x...
 */
contract DeployLPCE is Script {
    struct Deployed {
        EnclavesStorage enclavesStorage;
        AccessControlInter accessControlInter;
        AccountingManager accountingManager;
        LiquidityLogic liquidityLogic;
        LiquidityOrchestratorEvo liquidityOrchestratorEvo;
        LiquidityCreditEnclaveFactory factory;
    }

    string internal constant KEY_ENCLAVES_STORAGE = "EnclavesStorage";
    string internal constant KEY_ACCESS_CONTROL = "AccessControlInter";
    string internal constant KEY_ACCOUNTING_MANAGER = "AccountingManager";
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
        uint256 adminPk = vm.envUint("ADMIN_PK");
        address addressProviderAddr = vm.envAddress("ADDRESS_PROVIDER");
        address deployer = vm.addr(adminPk);

        ISendraAddressProvider ap = ISendraAddressProvider(addressProviderAddr);
        IRolesAdmin roles = SendraDeployLib.roles(ap);

        console2.log("=== LPCE Deploy ===");
        console2.log("Deployer:", deployer);
        console2.log("AddressProvider:", addressProviderAddr);
        console2.log("Deployer is Roles admin:", roles.checkAdmin(deployer));

        _verifyPrerequisites(ap);

        vm.startBroadcast(adminPk);

        Deployed memory d = _deployOrLoad(addressProviderAddr);
        _registerInAddressProvider(IAddressProviderAdmin(addressProviderAddr), d);
        _registerProtocolContracts(roles, d);

        vm.stopBroadcast();

        _logSummary(d);
    }

    function _deployOrLoad(address addressProviderAddr) internal returns (Deployed memory d) {
        d.enclavesStorage = _loadOrDeployEnclavesStorage(addressProviderAddr);
        d.accessControlInter = _loadOrDeployAccessControlInter(addressProviderAddr);
        d.accountingManager = _loadOrDeployAccountingManager(addressProviderAddr);
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

    function _registerInAddressProvider(IAddressProviderAdmin ap, Deployed memory d) internal {
        console2.log("--- AddressProvider registration ---");

        ap.setAddress(KEY_ENCLAVES_STORAGE, address(d.enclavesStorage));
        ap.setAddress(KEY_ACCESS_CONTROL, address(d.accessControlInter));
        ap.setAddress(KEY_ACCOUNTING_MANAGER, address(d.accountingManager));
        ap.setAddress(KEY_LIQUIDITY_LOGIC, address(d.liquidityLogic));
        ap.setAddress(KEY_LIQUIDITY_ORCHESTRATOR_EVO, address(d.liquidityOrchestratorEvo));
        ap.setAddress(KEY_FACTORY, address(d.factory));
    }

    function _registerProtocolContracts(IRolesAdmin roles, Deployed memory d) internal {
        console2.log("--- Roles allowContract ---");

        _allowIfNeeded(roles, address(d.enclavesStorage), KEY_ENCLAVES_STORAGE);
        _allowIfNeeded(roles, address(d.accessControlInter), KEY_ACCESS_CONTROL);
        _allowIfNeeded(roles, address(d.accountingManager), KEY_ACCOUNTING_MANAGER);
        _allowIfNeeded(roles, address(d.factory), KEY_FACTORY);
    }

    function _allowIfNeeded(IRolesAdmin roles, address contractAddr, string memory name) internal {
        if (roles.isProtocolContract(contractAddr)) {
            console2.log("Already protocol:", name, contractAddr);
            return;
        }
        roles.allowContract(contractAddr, name);
        console2.log("allowContract:", name, contractAddr);
    }

    function _logSummary(Deployed memory d) internal view {
        console2.log("=== Deployment summary ===");
        console2.log("EnclavesStorage:", address(d.enclavesStorage));
        console2.log("AccessControlInter:", address(d.accessControlInter));
        console2.log("AccountingManager:", address(d.accountingManager));
        console2.log("LiquidityLogic:", address(d.liquidityLogic));
        console2.log("LiquidityOrchestratorEvo:", address(d.liquidityOrchestratorEvo));
        console2.log("LiquidityCreditEnclaveFactory:", address(d.factory));
    }
}
