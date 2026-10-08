// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISwapRouter } from "../../interfaces/iSendraCore/sendraUniExec/ISwapRouter.sol";
import { UniswapLib } from "../../libs/uni.lib.sol";
import { AccessControlInter } from "../storage/security/AccessControlInter.sol";
import { EnclaveAccountOpener } from "./EnclaveAccountOpener.sol";

interface IEnclaveAccount {
    function owner() external view returns (address);
    function execute(UniswapLib.SwapInput calldata input, bool isBuy) external returns (uint256 positionId, uint256 amountOut);
    function openSupply(address asset, uint256 usdcAmount, UniswapLib.SwapInput calldata swap) external;
    function openLoop(address asset, uint256 usdcAmount, uint8 loops, uint16 borrowBps, UniswapLib.SwapInput calldata swap) external;
    function openShort(
        address asset,
        uint256 usdcAmount,
        uint8 loops,
        uint16 borrowBps,
        bool releaseToOwner,
        UniswapLib.SwapInput calldata sellAsset
    ) external;
    function openLeveraged(
        address asset,
        uint256 usdcAmount,
        uint16 borrowBps,
        UniswapLib.SwapInput calldata buyAsset,
        bool collateralIsAsset,
        bytes calldata lpData
    ) external;
    function close(uint256 positionId, uint256 fundAmount, UniswapLib.SwapInput calldata swap) external;
    function release(uint256 positionId) external;
    function closeLeveraged(
        uint256 positionId,
        uint256 fundAmount,
        uint256 uniId,
        uint256 lpPositionId,
        bytes calldata exitData
    ) external;
}

/// @notice Spot and Aave for an enclave. The executor delegatecalls this contract,
///         so address(this) is the enclave and the USDC never leaves that context
///         except through the Sendra account the enclave owns.
/// @dev Selectors must match LiquidityLogic. The ruler checks those selectors
///      before the executor delegatecalls LiquidityLogic, which delegatecalls here.
contract EnclaveDesk {
    using SafeERC20 for IERC20;

    ISendraAddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
    }

    function buySpot(uint256 usdcAmount, UniswapLib.SwapInput calldata input) external {
        _guard();
        _requireCredit(usdcAmount);
        if (input.amountIn0 != usdcAmount || input.tokenIn != _usdc()) revert AmountMismatch();
        address account = EnclaveAccountOpener(addressProvider.getAddress("EnclaveAccountOpener")).spotAccount();
        _fund(account, usdcAmount);
        IEnclaveAccount(account).execute(input, true);
    }

    function sellSpot(UniswapLib.SwapInput calldata input) external {
        _guard();
        if (input.tokenOut != _usdc()) revert AmountMismatch();
        address account = EnclaveAccountOpener(addressProvider.getAddress("EnclaveAccountOpener")).spotOf(address(this));
        if (account == address(0)) revert NoSpotAccount();
        _owned(account);
        IEnclaveAccount(account).execute(input, false);
    }

    function openSupply(address asset, uint256 usdcAmount, UniswapLib.SwapInput calldata swap) external {
        _guard();
        address account = _freshAave(usdcAmount);
        IEnclaveAccount(account).openSupply(asset, usdcAmount, swap);
    }

    function openLoop(
        address asset,
        uint256 usdcAmount,
        uint8 loops,
        uint16 borrowBps,
        UniswapLib.SwapInput calldata swap
    ) external {
        _guard();
        address account = _freshAave(usdcAmount);
        IEnclaveAccount(account).openLoop(asset, usdcAmount, loops, borrowBps, swap);
    }

    function openShort(
        address asset,
        uint256 usdcAmount,
        uint8 loops,
        uint16 borrowBps,
        bool releaseToOwner,
        UniswapLib.SwapInput calldata sellAsset
    ) external {
        _guard();
        address account = _freshAave(usdcAmount);
        IEnclaveAccount(account).openShort(asset, usdcAmount, loops, borrowBps, releaseToOwner, sellAsset);
    }

    function openLeveraged(
        address asset,
        uint256 usdcAmount,
        uint16 borrowBps,
        UniswapLib.SwapInput calldata buyAsset,
        bool collateralIsAsset,
        bytes calldata lpData
    ) external {
        _guard();
        address account = _freshAave(usdcAmount);
        IEnclaveAccount(account).openLeveraged(asset, usdcAmount, borrowBps, buyAsset, collateralIsAsset, lpData);
    }

    function closeStrategy(
        address account,
        uint256 positionId,
        uint256 fundAmount,
        UniswapLib.SwapInput calldata swap
    ) external {
        _guard();
        _owned(account);
        if (fundAmount > 0) {
            _requireCredit(fundAmount);
            _fund(account, fundAmount);
        }
        IEnclaveAccount(account).close(positionId, fundAmount, swap);
        // Supply of a non-USDC asset lands on the executor. Sell it so the
        // lender can see the credit as USDC on withdraw.
        if (swap.tokenOut == _usdc() && swap.tokenIn != _usdc()) {
            _swapHeld(swap);
        }
    }

    function releaseShort(address account, uint256 positionId) external {
        _guard();
        _owned(account);
        IEnclaveAccount(account).release(positionId);
    }

    function closeLeveraged(
        address account,
        uint256 positionId,
        uint256 fundAmount,
        uint256 uniId,
        uint256 lpPositionId,
        bytes calldata exitData
    ) external {
        _guard();
        _owned(account);
        if (fundAmount > 0) {
            _requireCredit(fundAmount);
            _fund(account, fundAmount);
        }
        IEnclaveAccount(account).closeLeveraged(positionId, fundAmount, uniId, lpPositionId, exitData);
    }

    function _freshAave(uint256 usdcAmount) internal returns (address account) {
        _requireCredit(usdcAmount);
        account = EnclaveAccountOpener(addressProvider.getAddress("EnclaveAccountOpener")).openAaveAccount();
        _fund(account, usdcAmount);
    }

    function _fund(address account, uint256 amount) internal {
        IERC20(_usdc()).forceApprove(account, amount);
    }

    function _owned(address account) internal view {
        if (account == address(0) || IEnclaveAccount(account).owner() != address(this)) revert NotEnclaveAccount();
    }

    function _guard() internal view {
        if (!AccessControlInter(addressProvider.getAddress("AccessControlInter")).getIsSendraEnclave(address(this))) {
            revert NotEnclave();
        }
    }

    function _requireCredit(uint256 amount) internal view {
        uint256 balance = IERC20(_usdc()).balanceOf(address(this));
        if (balance < amount) revert InsufficientCredit(balance, amount);
    }

    function _usdc() internal view returns (address) {
        return addressProvider.getAddress("USDC");
    }

    /// @dev Sells whatever of swap.tokenIn is sitting on the executor.
    ///      Hop amounts are scaled to that balance so the router route matches.
    function _swapHeld(UniswapLib.SwapInput calldata input) internal {
        uint256 bal = IERC20(input.tokenIn).balanceOf(address(this));
        if (bal == 0 || input.swapInstructions.length == 0) return;
        UniswapLib.SwapInput memory swap = input;
        uint256 quoted = swap.amountIn0 == 0 ? bal : swap.amountIn0;
        swap.amountIn0 = bal;
        swap.to = address(this);
        uint256 rooted;
        uint256 first = type(uint256).max;
        for (uint256 i = 0; i < swap.swapInstructions.length; i++) {
            uint256 hopIn = swap.swapInstructions[i].amountIn;
            if (hopIn == 0) continue;
            if (first == type(uint256).max) first = i;
            swap.swapInstructions[i].amountIn = hopIn * bal / quoted;
            swap.swapInstructions[i].amountOut = swap.swapInstructions[i].amountOut * bal / quoted;
            rooted += swap.swapInstructions[i].amountIn;
        }
        if (first == type(uint256).max) return;
        if (rooted < bal) swap.swapInstructions[first].amountIn += bal - rooted;
        address router = addressProvider.getAddress("SwapRouter");
        IERC20(swap.tokenIn).safeTransfer(router, bal);
        ISwapRouter(router).executeSwap(swap);
    }

    error NotEnclave();
    error NotEnclaveAccount();
    error NoSpotAccount();
    error AmountMismatch();
    error InsufficientCredit(uint256 balance, uint256 needed);
}
