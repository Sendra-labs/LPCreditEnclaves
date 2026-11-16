// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LPCE } from "./LPCE.lib.sol";
import { SendraLib } from "./Sendra.lib.sol";
import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";

/// @title EnclaveRuleBook
/// @notice Turns an enclave policy into the SRPE v2 rules frozen at deploy.
/// @dev Selector order is fixed. The factory fills `selectors` in this order:
///      0 provideLiquidity, 1 withdrawCredit, 2 closePosition, 3 depositCredit,
///      4 pauseExecution, 5 unpauseExecution, 6 initializeOperatorPosition,
///      7 revokeEnclave, 8 provideLiquidityNoAccountingTest, 9 buySpot, 10 sellSpot,
///      11 openSupply, 12 openLoop, 13 openShort, 14 openLeveraged, 15 closeStrategy,
///      16 releaseShort, 17 closeLeveraged, 18 partialClose, 19 sellHeld, 20 openBasket.
///
///      Static words the ruler can see:
///      - provide: usdc 0, token0 1, token1 2, fee 3
///      - buySpot: usdc 0, tokenOut 1, allowlist from `allowedTokens`
///      - openSupply: asset 0, usdc 1, allowlist from `policy.allowedSupplyTokens`
///      - openLoop: asset 0, usdc 1, loops 2, borrowBps 3, allowlist from `allowedLoopTokens`
///      - openShort: asset 0, usdc 1, loops 2, borrowBps 3, allowlist from `allowedShortTokens`
///      - openLeveraged: asset 0 (collateral), usdc 1, borrowBps 2, allowlist from `allowedLeverageTokens`
///      - openBasket: collateral 0, usdc 1, allowlist from `allowedBasketTokens`.
///        The bought legs sit in a dynamic array, so they carry no allowlist.
///
///      A bit in `policy.blockedActions` leaves that open with no rules. The factory omits it,
///      and the ruler reverts the call. Closes, sells and withdrawals stay callable by either
///      party, with no deadline, no cooldown and no asset filter, so capital can always leave.
///      Drawdown, exposure, streak and open positions are ceilings on the operator's
///      Sendra pulse. They sit on every open that stays enabled. The factory also checks
///      them when the operator is named or accepts. A zero cap adds no rule.
library EnclaveRuleBook {
    uint256 internal constant ACTIONS = 21;

    function rulesFor(
        bytes4[] memory selectors,
        uint256 creditInUsd,
        uint256 minUsdcPerTx,
        uint256 maxUsdcPerTx,
        uint256 deadline,
        address allowedOperator,
        address allowedLender,
        address factory,
        address[] memory allowedTokens,
        LPCE.EnclavePolicy memory policy
    ) internal pure returns (SRPELib.Rules[] memory functionSelectorRules) {
        if (selectors.length != ACTIONS) revert SelectorCount(selectors.length);

        address[] memory either = new address[](2);
        either[0] = allowedLender;
        either[1] = allowedOperator;

        bool blockLp = (policy.blockedActions & LPCE.BLOCK_LP) != 0;
        functionSelectorRules = new SRPELib.Rules[](ACTIONS);
        functionSelectorRules[0] = blockLp
            ? _blocked()
            : _lpOpen(selectors[0], minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy);
        functionSelectorRules[1] = _either(either);
        functionSelectorRules[2] = _either(either);
        functionSelectorRules[3] = _deposit(selectors[3], allowedLender, creditInUsd);
        functionSelectorRules[4] = _only(selectors[4], allowedLender);
        functionSelectorRules[5] = _only(selectors[5], allowedLender);
        functionSelectorRules[6] = _only(selectors[6], factory);
        functionSelectorRules[7] = _either(either);
        functionSelectorRules[8] = blockLp
            ? _blocked()
            : _lpOpen(selectors[8], minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy);
        functionSelectorRules[9] = (policy.blockedActions & LPCE.BLOCK_SPOT) != 0
            ? _blocked()
            : _spotBuy(selectors[9], minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, allowedTokens, policy);
        functionSelectorRules[10] = _either(either);
        functionSelectorRules[11] = _marketOpen(
            selectors[11], 1, minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy,
            policy.allowedSupplyTokens, false, 0, (policy.blockedActions & LPCE.BLOCK_SUPPLY) != 0
        );
        functionSelectorRules[12] = _marketOpen(
            selectors[12], 1, minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy,
            policy.allowedLoopTokens, true, 3, (policy.blockedActions & LPCE.BLOCK_LOOP) != 0
        );
        functionSelectorRules[13] = _marketOpen(
            selectors[13], 1, minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy,
            policy.allowedShortTokens, true, 3, (policy.blockedActions & LPCE.BLOCK_SHORT) != 0
        );
        functionSelectorRules[14] = _marketOpen(
            selectors[14], 1, minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy,
            policy.allowedLeverageTokens, false, 2, (policy.blockedActions & LPCE.BLOCK_LEVERAGE) != 0
        );
        functionSelectorRules[15] = _either(either);
        functionSelectorRules[16] = _either(either);
        functionSelectorRules[17] = _either(either);
        functionSelectorRules[18] = _either(either);
        functionSelectorRules[19] = _either(either);
        functionSelectorRules[20] = _marketOpen(
            selectors[20], 1, minUsdcPerTx, maxUsdcPerTx, deadline, allowedOperator, policy,
            policy.allowedBasketTokens, false, 0, (policy.blockedActions & LPCE.BLOCK_BASKET) != 0
        );
    }

    function _lpOpen(
        bytes4 selector,
        uint256 minUsdc,
        uint256 maxUsdc,
        uint256 deadline,
        address operator,
        LPCE.EnclavePolicy memory policy
    ) private pure returns (SRPELib.Rules memory) {
        SRPELib.Rule[] memory buf = new SRPELib.Rule[](SRPELib.MAX_RULES);
        uint256 n;
        buf[n++] = _range(0, minUsdc, maxUsdc);
        buf[n++] = _before(deadline);
        buf[n++] = _sender(selector, operator);
        n = _cooldown(buf, n, policy.cooldownSeconds);
        if (policy.allowedPairs.length != 0) buf[n++] = _pairs(policy.allowedPairs);
        if (policy.maxLpFee != 0) buf[n++] = _atMost(3, policy.maxLpFee);
        n = _book(buf, n, policy);
        return _trim(buf, n);
    }

    function _spotBuy(
        bytes4 selector,
        uint256 minUsdc,
        uint256 maxUsdc,
        uint256 deadline,
        address operator,
        address[] memory allowedTokens,
        LPCE.EnclavePolicy memory policy
    ) private pure returns (SRPELib.Rules memory) {
        SRPELib.Rule[] memory buf = new SRPELib.Rule[](SRPELib.MAX_RULES);
        uint256 n;
        buf[n++] = _range(0, minUsdc, maxUsdc);
        buf[n++] = _before(deadline);
        buf[n++] = _sender(selector, operator);
        n = _cooldown(buf, n, policy.cooldownSeconds);
        if (allowedTokens.length != 0) buf[n++] = _allow(1, allowedTokens);
        n = _book(buf, n, policy);
        return _trim(buf, n);
    }

    /// @dev Drops opens that were left with no rules. The ruler rejects a selector that was never stored.
    function withoutBlocked(bytes4[] memory selectors, SRPELib.Rules[] memory rules)
        internal
        pure
        returns (bytes4[] memory keptSelectors, SRPELib.Rules[] memory keptRules)
    {
        uint256 keep;
        for (uint256 i; i < rules.length; ++i) {
            if (rules[i].rules.length != 0) ++keep;
        }
        keptSelectors = new bytes4[](keep);
        keptRules = new SRPELib.Rules[](keep);
        uint256 w;
        for (uint256 i; i < rules.length; ++i) {
            if (rules[i].rules.length == 0) continue;
            keptSelectors[w] = selectors[i];
            keptRules[w] = rules[i];
            unchecked {
                ++w;
            }
        }
    }

    function _marketOpen(
        bytes4 selector,
        uint256 amountIndex,
        uint256 minUsdc,
        uint256 maxUsdc,
        uint256 deadline,
        address operator,
        LPCE.EnclavePolicy memory policy,
        address[] memory assets,
        bool limitLoops,
        uint256 borrowIndex,
        bool blocked
    ) private pure returns (SRPELib.Rules memory) {
        if (blocked) return _blocked();
        SRPELib.Rule[] memory buf = new SRPELib.Rule[](SRPELib.MAX_RULES);
        uint256 n;
        buf[n++] = _range(amountIndex, minUsdc, maxUsdc);
        buf[n++] = _before(deadline);
        buf[n++] = _sender(selector, operator);
        n = _cooldown(buf, n, policy.cooldownSeconds);
        if (assets.length != 0) buf[n++] = _allow(0, assets);
        if (limitLoops && policy.maxLoops != 0) buf[n++] = _atMost(2, policy.maxLoops);
        if (borrowIndex != 0 && policy.maxBorrowBps != 0) buf[n++] = _atMost(borrowIndex, policy.maxBorrowBps);
        n = _book(buf, n, policy);
        return _trim(buf, n);
    }

    function _blocked() private pure returns (SRPELib.Rules memory packed) {
        packed = SRPELib.Rules({ruleCount: 0, rules: new SRPELib.Rule[](0)});
    }

    /// @dev Ceilings on the caller's pulse. The open caller is the operator. A fresh pulse is zeros.
    function _book(SRPELib.Rule[] memory buf, uint256 n, LPCE.EnclavePolicy memory policy) private pure returns (uint256) {
        if (policy.maxExposure != 0) buf[n++] = _ceiling(SRPELib.RULE_CURRENT_EXPOSURE, policy.maxExposure);
        if (policy.maxDrawdown != 0) buf[n++] = _ceiling(SRPELib.RULE_MAX_DRAWDOWN, policy.maxDrawdown);
        if (policy.maxConsecutiveLosses != 0) buf[n++] = _ceiling(SRPELib.RULE_CONSECUTIVE_LOSSES, policy.maxConsecutiveLosses);
        if (policy.maxOpenPositions != 0) {
            buf[n++] = _derived(SRPELib.DERIVED_OPEN_POSITIONS, int256(uint256(policy.maxOpenPositions)));
        }
        return n;
    }

    /// @dev True when the operator's existing pulse is inside the caps. A zero cap is off.
    ///      An empty pulse is zeros, so a new operator passes every cap that is set.
    function operatorFits(SendraLib.GlobalAccumulators memory book, LPCE.EnclavePolicy memory policy)
        internal
        pure
        returns (bool)
    {
        if (policy.maxDrawdown != 0 && book.maxDrawdown > policy.maxDrawdown) return false;
        if (policy.maxExposure != 0 && book.currentExposure > policy.maxExposure) return false;
        if (policy.maxConsecutiveLosses != 0 && book.consecutiveLosses > policy.maxConsecutiveLosses) return false;
        if (policy.maxOpenPositions != 0) {
            uint256 openPositions = book.totalPositionsOpened > book.totalPositionsClosed
                ? book.totalPositionsOpened - book.totalPositionsClosed
                : 0;
            if (openPositions > policy.maxOpenPositions) return false;
        }
        return true;
    }

    function _cooldown(SRPELib.Rule[] memory buf, uint256 n, uint256 seconds_) private pure returns (uint256) {
        if (seconds_ == 0) return n;
        buf[n] = SRPELib.Rule({
            ruleType: SRPELib.RULE_COOLDOWN,
            ruleData: abi.encode(seconds_),
            extraData: ""
        });
        return n + 1;
    }

    function _pairs(LPCE.TokenPair[] memory pairs) private pure returns (SRPELib.Rule memory rule) {
        address[] memory a = new address[](pairs.length);
        address[] memory b = new address[](pairs.length);
        for (uint256 i; i < pairs.length; ++i) {
            a[i] = pairs[i].tokenA;
            b[i] = pairs[i].tokenB;
        }
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_PARAM_PAIR,
            ruleData: abi.encode(uint256(1), uint256(2), true, a, b),
            extraData: ""
        });
    }

    function _either(address[] memory who) private pure returns (SRPELib.Rules memory packed) {
        SRPELib.Rule[] memory rules = new SRPELib.Rule[](1);
        rules[0] = SRPELib.Rule({
            ruleType: SRPELib.RULE_SENDER_ALLOWLIST,
            ruleData: abi.encode(who),
            extraData: ""
        });
        packed = SRPELib.Rules({ruleCount: 1, rules: rules});
    }

    function _only(bytes4 selector, address who) private pure returns (SRPELib.Rules memory packed) {
        SRPELib.Rule[] memory rules = new SRPELib.Rule[](1);
        rules[0] = _sender(selector, who);
        packed = SRPELib.Rules({ruleCount: 1, rules: rules});
    }

    function _deposit(bytes4 selector, address lender, uint256 creditInUsd) private pure returns (SRPELib.Rules memory packed) {
        SRPELib.Rule[] memory rules = new SRPELib.Rule[](1);
        rules[0] = SRPELib.Rule({
            ruleType: SRPELib.RULE_SENDER_SELECTOR_WORD,
            ruleData: abi.encode(selector, lender, uint256(0), bytes32(creditInUsd)),
            extraData: ""
        });
        packed = SRPELib.Rules({ruleCount: 1, rules: rules});
    }

    function _sender(bytes4 selector, address who) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_SENDER_SELECTOR,
            ruleData: abi.encode(selector, who),
            extraData: ""
        });
    }

    function _range(uint256 index, uint256 min, uint256 max) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_PARAM_UINT_RANGE,
            ruleData: abi.encode(index, min, max),
            extraData: ""
        });
    }

    function _atMost(uint256 index, uint256 max) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_PARAM_UINT_BOUND,
            ruleData: abi.encode(index, max, SRPELib.OP_LE),
            extraData: ""
        });
    }

    function _allow(uint256 index, address[] memory list) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_PARAM_ALLOWLIST,
            ruleData: abi.encode(index, list),
            extraData: ""
        });
    }

    function _ceiling(uint16 ruleType, uint256 threshold) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: ruleType,
            ruleData: abi.encode(threshold, SRPELib.OP_LE),
            extraData: ""
        });
    }

    function _derived(uint8 metricId, int256 threshold) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_DERIVED,
            ruleData: abi.encode(metricId, threshold, SRPELib.OP_LE),
            extraData: ""
        });
    }

    function _before(uint256 deadline) private pure returns (SRPELib.Rule memory rule) {
        rule = SRPELib.Rule({
            ruleType: SRPELib.RULE_TIMESTAMP,
            ruleData: abi.encode(deadline, SRPELib.OP_LT),
            extraData: ""
        });
    }

    function _trim(SRPELib.Rule[] memory buf, uint256 n) private pure returns (SRPELib.Rules memory packed) {
        if (n == 0 || n > SRPELib.MAX_RULES) revert TooManyRules(n);
        SRPELib.Rule[] memory rules = new SRPELib.Rule[](n);
        for (uint256 i; i < n; ++i) rules[i] = buf[i];
        packed = SRPELib.Rules({ruleCount: n, rules: rules});
    }

    error SelectorCount(uint256 count);
    error TooManyRules(uint256 count);
}
