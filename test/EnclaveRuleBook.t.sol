// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { EnclaveRuleBook } from "../src/libs/EnclaveRuleBook.sol";
import { LPCE } from "../src/libs/LPCE.lib.sol";
import { SendraLib } from "../src/libs/Sendra.lib.sol";
import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";

contract EnclaveRuleBookHarness {
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
    ) external pure returns (SRPELib.Rules[] memory) {
        return EnclaveRuleBook.rulesFor(
            selectors,
            creditInUsd,
            minUsdcPerTx,
            maxUsdcPerTx,
            deadline,
            allowedOperator,
            allowedLender,
            factory,
            allowedTokens,
            policy
        );
    }

    function operatorFits(SendraLib.GlobalAccumulators memory book, LPCE.EnclavePolicy memory policy) external pure returns (bool) {
        return EnclaveRuleBook.operatorFits(book, policy);
    }

    function withoutBlocked(bytes4[] memory selectors, SRPELib.Rules[] memory rules)
        external
        pure
        returns (bytes4[] memory, SRPELib.Rules[] memory)
    {
        return EnclaveRuleBook.withoutBlocked(selectors, rules);
    }
}

contract EnclaveRuleBookTest is Test {
    EnclaveRuleBookHarness internal harness;

    address internal operator = makeAddr("operator");
    address internal lender = makeAddr("lender");
    address internal factory = makeAddr("factory");
    address internal weth = makeAddr("weth");
    address internal usdc = makeAddr("usdc");

    function setUp() public {
        harness = new EnclaveRuleBookHarness();
    }

    function test_plainPolicyKeepsExitsOpen() public view {
        SRPELib.Rules[] memory rules = _rules(_tokens(0), _policy());
        assertEq(rules.length, 21);
        assertEq(rules[0].ruleCount, 3);
        assertEq(rules[0].rules[0].ruleType, SRPELib.RULE_PARAM_UINT_RANGE);
        (uint256 index, uint256 min, uint256 max) = abi.decode(rules[0].rules[0].ruleData, (uint256, uint256, uint256));
        assertEq(index, 0);
        assertEq(min, 100e6);
        assertEq(max, 1_000e6);
        assertFalse(_has(rules[0], SRPELib.RULE_COOLDOWN));
        assertFalse(_has(rules[0], SRPELib.RULE_PARAM_PAIR));
        assertFalse(_has(rules[0], SRPELib.RULE_MAX_DRAWDOWN));
        assertFalse(_has(rules[12], SRPELib.RULE_PARAM_UINT_BOUND));

        assertEq(rules[1].ruleCount, 1);
        assertEq(rules[1].rules[0].ruleType, SRPELib.RULE_SENDER_ALLOWLIST);
        assertFalse(_has(rules[1], SRPELib.RULE_MAX_DRAWDOWN));
        assertFalse(_has(rules[2], SRPELib.RULE_COOLDOWN));
        assertFalse(_has(rules[10], SRPELib.RULE_PARAM_ALLOWLIST));

        (uint256 supplyIndex,,) = abi.decode(rules[11].rules[0].ruleData, (uint256, uint256, uint256));
        assertEq(supplyIndex, 1);
        assertEq(rules[3].rules[0].ruleType, SRPELib.RULE_SENDER_SELECTOR_WORD);
    }

    function test_optionalRulesAttachOnlyToOpens() public view {
        address[] memory tokens = _tokens(1);
        tokens[0] = weth;
        LPCE.EnclavePolicy memory policy = _policy();
        policy.allowedPairs = new LPCE.TokenPair[](1);
        policy.allowedPairs[0] = LPCE.TokenPair({tokenA: weth, tokenB: usdc});
        policy.cooldownSeconds = 3600;
        policy.maxDrawdown = 50e6;
        policy.maxExposure = 100e6;
        policy.maxConsecutiveLosses = 3;
        policy.maxOpenPositions = 4;
        policy.maxBorrowBps = 5_000;
        policy.maxLoops = 2;
        policy.maxLpFee = 500;
        policy.allowedSupplyTokens = new address[](1);
        policy.allowedSupplyTokens[0] = usdc;
        policy.allowedLoopTokens = new address[](1);
        policy.allowedLoopTokens[0] = weth;
        policy.allowedShortTokens = new address[](1);
        policy.allowedShortTokens[0] = weth;
        policy.allowedLeverageTokens = new address[](1);
        policy.allowedLeverageTokens[0] = usdc;
        policy.allowedBasketTokens = new address[](1);
        policy.allowedBasketTokens[0] = weth;

        SRPELib.Rules[] memory rules = _rules(tokens, policy);

        assertTrue(_has(rules[0], SRPELib.RULE_COOLDOWN));
        assertTrue(_has(rules[0], SRPELib.RULE_PARAM_PAIR));
        assertTrue(_has(rules[0], SRPELib.RULE_PARAM_UINT_BOUND));
        assertTrue(_has(rules[0], SRPELib.RULE_MAX_DRAWDOWN));
        assertTrue(_has(rules[0], SRPELib.RULE_CURRENT_EXPOSURE));
        assertTrue(_has(rules[0], SRPELib.RULE_CONSECUTIVE_LOSSES));
        assertTrue(_has(rules[0], SRPELib.RULE_DERIVED));
        assertTrue(_has(rules[9], SRPELib.RULE_MAX_DRAWDOWN));
        assertTrue(_has(rules[11], SRPELib.RULE_MAX_DRAWDOWN));
        assertTrue(_has(rules[14], SRPELib.RULE_MAX_DRAWDOWN));

        address[] memory spot = _allowlist(rules[9]);
        address[] memory supply = _allowlist(rules[11]);
        address[] memory loop = _allowlist(rules[12]);
        address[] memory shorted = _allowlist(rules[13]);
        address[] memory leverage = _allowlist(rules[14]);
        address[] memory basket = _allowlist(rules[20]);
        assertEq(spot.length, 1);
        assertEq(spot[0], weth);
        assertEq(supply.length, 1);
        assertEq(supply[0], usdc);
        assertEq(loop.length, 1);
        assertEq(loop[0], weth);
        assertEq(shorted.length, 1);
        assertEq(shorted[0], weth);
        assertEq(leverage.length, 1);
        assertEq(leverage[0], usdc);
        assertEq(basket.length, 1);
        assertEq(basket[0], weth);
        assertFalse(_has(rules[20], SRPELib.RULE_PARAM_UINT_BOUND));
        assertTrue(_has(rules[9], SRPELib.RULE_COOLDOWN));
        assertFalse(_has(rules[10], SRPELib.RULE_PARAM_ALLOWLIST));
        assertFalse(_has(rules[10], SRPELib.RULE_COOLDOWN));
        assertFalse(_has(rules[10], SRPELib.RULE_MAX_DRAWDOWN));

        assertFalse(_has(rules[11], SRPELib.RULE_PARAM_UINT_BOUND));
        assertTrue(_has(rules[12], SRPELib.RULE_PARAM_UINT_BOUND));
        assertTrue(_has(rules[14], SRPELib.RULE_PARAM_UINT_BOUND));
        assertFalse(_has(rules[15], SRPELib.RULE_PARAM_ALLOWLIST));
        assertFalse(_has(rules[1], SRPELib.RULE_MAX_DRAWDOWN));

        SendraLib.GlobalAccumulators memory book;
        assertTrue(harness.operatorFits(book, policy));
        book.maxDrawdown = 50e6;
        book.currentExposure = 100e6;
        book.consecutiveLosses = 3;
        book.totalPositionsOpened = 4;
        assertTrue(harness.operatorFits(book, policy));
        book.maxDrawdown = 50e6 + 1;
        assertFalse(harness.operatorFits(book, policy));
    }

    function test_blockedOpensAreOmitted() public view {
        LPCE.EnclavePolicy memory policy = _policy();
        policy.blockedActions = LPCE.BLOCK_LP | LPCE.BLOCK_SUPPLY;
        SRPELib.Rules[] memory rules = _rules(_tokens(0), policy);
        assertEq(rules[0].rules.length, 0);
        assertEq(rules[8].rules.length, 0);
        assertEq(rules[11].rules.length, 0);
        assertGt(rules[9].rules.length, 0);
        assertGt(rules[12].rules.length, 0);
        assertGt(rules[1].rules.length, 0);

        bytes4[] memory selectors = new bytes4[](21);
        for (uint256 i; i < 21; ++i) selectors[i] = bytes4(uint32(i + 1));
        (bytes4[] memory kept, SRPELib.Rules[] memory keptRules) = harness.withoutBlocked(selectors, rules);
        assertEq(kept.length, 18);
        assertEq(keptRules.length, 18);
        assertGt(rules[20].rules.length, 0);
        assertEq(kept[0], selectors[1]);
    }

    function _rules(address[] memory tokens, LPCE.EnclavePolicy memory policy) internal view returns (SRPELib.Rules[] memory) {
        bytes4[] memory selectors = new bytes4[](21);
        for (uint256 i; i < 21; ++i) selectors[i] = bytes4(uint32(i + 1));
        return harness.rulesFor(selectors, 1_000e6, 100e6, 1_000e6, 1, operator, lender, factory, tokens, policy);
    }

    function _policy() internal pure returns (LPCE.EnclavePolicy memory policy) {}

    function _tokens(uint256 n) internal pure returns (address[] memory tokens) {
        tokens = new address[](n);
    }

    function _allowlist(SRPELib.Rules memory rules) internal pure returns (address[] memory list) {
        for (uint256 i; i < rules.rules.length; ++i) {
            if (rules.rules[i].ruleType != SRPELib.RULE_PARAM_ALLOWLIST) continue;
            (, list) = abi.decode(rules.rules[i].ruleData, (uint256, address[]));
            return list;
        }
        return new address[](0);
    }

    function _has(SRPELib.Rules memory rules, uint16 ruleType) internal pure returns (bool) {
        for (uint256 i; i < rules.rules.length; ++i) {
            if (rules.rules[i].ruleType == ruleType) return true;
        }
        return false;
    }
}
