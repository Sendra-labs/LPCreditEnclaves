// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ISendraAddressProvider} from "../src/interfaces/iSendraCore/ISendraAddressProvider.sol";
import {RPFPStorage} from "srpe/src/core/storage/RPFPStorage.sol";
import {UniversalRuler} from "srpe/src/core/UniversalRuler.sol";
import {UniversalExecutorFactory} from "srpe/src/core/UniversalExecutorFactory.sol";
import {RPFPDeployer} from "srpe/src/core/RPFPDeployer.sol";
import {EnclavePulse} from "../src/core/execution/EnclavePulse.sol";
import {EnclaveAccountOpener} from "../src/core/execution/EnclaveAccountOpener.sol";
import {EnclaveDesk} from "../src/core/execution/EnclaveDesk.sol";
import {LiquidityLogic} from "../src/core/execution/LiquidityLogic.sol";
import {LiquidityCreditEnclaveFactory} from "../src/core/factory/LiquidityCreditEnclaveFactory.sol";
import {IAddressProviderAdmin, IRolesAdmin, SendraDeployLib} from "./interfaces/SendraDeploy.sol";

/**
 * @title DeployEnclavePlus
 * @notice Redeploys SRPE and the enclave pieces that spot and Aave need.
 *
 *         SRPE is replaced as a set: RPFPStorage, UniversalRuler,
 *         UniversalExecutorFactory and RPFPDeployer. A new storage starts empty,
 *         so enclaves created against the previous RPFPStorage stop executing.
 *         New executors come from the new factory. Their rules live in the new storage.
 *
 *         New enclaves pick up the new LiquidityLogic (implementation is read at
 *         create time).
 *
 *         Pulse for spot and Aave is redirected only after SwapAccountant and
 *         AaveAccountant are redeployed. Those books live in the accountant, so
 *         close open markets positions first, then run:
 *           SendraMarkets/script/UpdateSwapAccountant.s.sol
 *           SendraLending/script/UpgradeAaveAccountant.s.sol
 *
 * .env (WSL: set -a && source .env && set +a):
 *   ADMIN_PK
 *   ADDRESS_PROVIDER
 *
 *   forge script script/DeployEnclavePlus.s.sol:DeployEnclavePlus --rpc-url arbitrum --broadcast -vvvv
 */
contract DeployEnclavePlus is Script {
    string internal constant KEY_DEPLOYER = "RPFPDeployer";
    string internal constant KEY_PULSE = "EnclavePulse";
    string internal constant KEY_OPENER = "EnclaveAccountOpener";
    string internal constant KEY_DESK = "EnclaveDesk";
    string internal constant KEY_LOGIC = "LiquidityLogic";
    string internal constant KEY_FACTORY = "LiquidityCreditEnclaveFactory";

    function run() external {
        uint256 adminPk = vm.envUint("ADMIN_PK");
        address provider = vm.envAddress("ADDRESS_PROVIDER");
        address deployer = vm.addr(adminPk);

        ISendraAddressProvider ap = ISendraAddressProvider(provider);
        IRolesAdmin roles = SendraDeployLib.roles(ap);

        console2.log("=== Enclave Plus ===");
        console2.log("Deployer:", deployer);
        console2.log("AddressProvider:", provider);
        console2.log("Deployer is Roles admin:", roles.checkAdmin(deployer));

        _require(ap, "Roles");
        _require(ap, "EnclavesStorage");
        _require(ap, "AccessControlInter");
        _require(ap, "AccountDeployer");
        _require(ap, "AccountAccessControl");
        _require(ap, "USDC");
        _require(ap, "SwapRouter");

        vm.startBroadcast(adminPk);

        RPFPStorage rpfpStorage = new RPFPStorage(provider);
        UniversalRuler ruler = new UniversalRuler(provider);
        UniversalExecutorFactory executorFactory = new UniversalExecutorFactory();
        RPFPDeployer rpfp = new RPFPDeployer(provider);
        EnclavePulse pulse = new EnclavePulse(provider);
        EnclaveAccountOpener opener = new EnclaveAccountOpener(provider);
        EnclaveDesk desk = new EnclaveDesk(provider);
        LiquidityLogic logic = new LiquidityLogic(provider);
        LiquidityCreditEnclaveFactory factory = new LiquidityCreditEnclaveFactory(provider);

        IAddressProviderAdmin admin = IAddressProviderAdmin(provider);
        admin.setAddress("RPFPStorage", address(rpfpStorage));
        admin.setAddress("UniversalRuler", address(ruler));
        admin.setAddress("UniversalExecutorFactory", address(executorFactory));
        admin.setAddress(KEY_DEPLOYER, address(rpfp));
        admin.setAddress(KEY_PULSE, address(pulse));
        admin.setAddress(KEY_OPENER, address(opener));
        admin.setAddress(KEY_DESK, address(desk));
        admin.setAddress(KEY_LOGIC, address(logic));
        admin.setAddress(KEY_FACTORY, address(factory));

        _allow(roles, address(rpfp), KEY_DEPLOYER);
        _allow(roles, address(opener), KEY_OPENER);
        _allow(roles, address(factory), KEY_FACTORY);

        vm.stopBroadcast();

        console2.log("RPFPStorage:", address(rpfpStorage));
        console2.log("UniversalRuler:", address(ruler));
        console2.log("UniversalExecutorFactory:", address(executorFactory));
        console2.log("RPFPDeployer:", address(rpfp));
        console2.log("EnclavePulse:", address(pulse));
        console2.log("EnclaveAccountOpener:", address(opener));
        console2.log("EnclaveDesk:", address(desk));
        console2.log("LiquidityLogic:", address(logic));
        console2.log("LiquidityCreditEnclaveFactory:", address(factory));
        console2.log("Selectors cap:", rpfp.MAX_FUNCTION_SELECTORS());
        console2.log("Next: redeploy SwapAccountant and AaveAccountant so pulse lands on the operator.");
    }

    function _require(ISendraAddressProvider ap, string memory key) internal view {
        address addr = ap.getAddress(key);
        require(addr != address(0), key);
        console2.log(key, addr);
    }

    function _allow(IRolesAdmin roles, address contractAddr, string memory name) internal {
        if (roles.isProtocolContract(contractAddr)) {
            console2.log("Already protocol:", name, contractAddr);
            return;
        }
        roles.allowContract(contractAddr, name);
        console2.log("allowContract:", name, contractAddr);
    }
}
