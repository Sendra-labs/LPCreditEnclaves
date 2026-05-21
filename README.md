# Liquidity Credit Enclaves (LPCE)

> *Fund operators, not wallets. Keep capital inside rules.*

Credit Enclaves implement a controlled capital delegation model for DeFi liquidity operations. Each enclave defines a bounded execution context where an operator can manage allocated capital through approved protocol actions, while capital ownership, permissions, position tracking, and accounting remain enforced on-chain.

**A Credit Enclave is a programmable capital delegation contract.** It lets a capital provider allocate funds to a liquidity operator under predefined execution rules, without transferring unrestricted custody. This is neither classic overcollateralized lending nor a passive vault.

---

## What is a Credit Enclave?

A Credit Enclave is an isolated unit of capital, rules, and execution. Each enclave represents an agreement between:

| Participant | Role |
|---|---|
| **Capital Provider / Lender** | Supplies or defines the capital assigned to the enclave |
| **Operator** | Executes authorized actions inside the enclave |
| **Sendra environment** | Enforces rules, records positions, and maintains traceability |

The operator does not receive funds freely. Capital stays inside the enclave and can only move through functions allowed by the contracts.

> **The enclave is not a wallet handed to an operator. It is a controlled execution container.**

Think of an enclave as a smart-contract managed account for DeFi liquidity operations: a capital provider, an authorized operator, execution permissions, storage, and accounting hooks.

### Why “Credit”?

The term **credit** refers to **delegated capital capacity**, not an unrestricted loan. The operator receives the ability to use capital under rules, not direct ownership or free withdrawal rights.

### Why “Enclave”?

The term **enclave** refers to an **isolated execution context**. Each enclave has its own participants, permissions, capital configuration, and position history.

---

## Problem this solves

In DeFi, capital delegation usually requires trust, multisig coordination, overcollateralization, or passive vault structures. Credit Enclaves introduce a different model: capital can be delegated for **active liquidity operations** while remaining constrained by smart contract rules.

- The lender wants skilled operators to deploy their capital.
- The operator may generate yield but may lack sufficient own capital.
- The system delegates capital **without granting free custody**.
- Actions are limited to operations supported by the protocol.

---

## Current capabilities

Only what exists in this repository today:

- Create a Credit Enclave with defined parameters via `LiquidityCreditEnclaveFactory`.
- Deploy a rule-bound executor (SRPE / RPFP) with `LiquidityLogic` as implementation.
- Register the enclave in `EnclavesStorage` and mark the executor in `AccessControlInter`.
- Deposit USDC credit into the enclave (`depositCredit`).
- Provide Uniswap V3 liquidity from the enclave (`provideLiquidity` → `LiquidityOrchestratorEvo`).
- Close LP positions (`closePosition`).
- Withdraw remaining credit and settle profit split between lender and operator (`withdrawCredit`).
- Pause and unpause enclave execution (lender-only via SRPE rules).
- Record positions in Sendra storage through `AccountingManager` (enclave LP and lender/operator accounting positions).
- Query enclave metadata and flags via `EnclavesStorage`.

Not included in this beta: dynamic drawdown, marketplace, multi-lender pools, prop-firm models, or automated strategy products.

---

## Enclave lifecycle

Enclave state is stored and managed through `EnclavesStorage`. The intended lifecycle:

| State | Meaning |
|---|---|
| **Created** | Enclave registered; executor deployed; credit not yet deposited |
| **Active** | Credit deposited; execution allowed when not paused |
| **Paused** | Lender paused execution; liquidity actions blocked |
| **Closed** | Credit withdrawn and positions settled; enclave operation finished |

Today the storage layer exposes `isPaused` and `isDeposited` flags on `LPCE.Enclave`; an explicit status enum is being consolidated on top of these transitions.

---

## Enclave parameters

An enclave is created with `LPCE.CreateEnclaveParams`:

| Field | Description |
|---|---|
| `creditInUsd` | Target / allocated credit in USDC terms |
| `maxUsdcPerTx` / `minUsdcPerTx` | Bounds per liquidity operation |
| `deadline` | Unix timestamp after which operations are not allowed |
| `operatorFee` | Operator share of profit (percentage) |
| `allowedTokens` | Tokens permitted in enclave rules |
| `allowedOperator` | Authorized operator address |
| `lender` | Capital provider address |
| `description` | Human-readable metadata |

Stored enclave record (`LPCE.Enclave`): `operator`, `lender`, `sendraExecutor`, `creditInUsd`, `operatorFee`, `description`, `isPaused`, `isDeposited`.

**These parameters define the operational boundary of the enclave.**

---

## Roles

### Capital Provider / Lender

Supplies credit (`depositCredit`), can pause/unpause execution, and participates in settlement on `withdrawCredit`.

### Operator

Address authorized to call `provideLiquidity` and `closePosition` (and `withdrawCredit` together with the lender). Cannot move capital outside allowed functions.

### Enclave (executor)

On-chain logical entity: the SRPE-deployed `LiquidityLogic` instance (`sendraExecutor`) that holds capital and executes under SRPE rules.

### Protocol / Sendra environment

`AddressProvider`, `SendraStorage`, `SendraRoles`, SRPE (`RPFPDeployer`), and orchestration contracts that validate permissions, run operations, and record accounting.

---

## Architecture

```
Capital Provider (Lender)
        |
        v
LiquidityCreditEnclaveFactory  --->  RPFPDeployer (SRPE rules)
        |
        v
EnclavesStorage  <----  AccessControlInter
        |
        v
LiquidityLogic (enclave executor)
        |
        +----> LiquidityOrchestratorEvo  --->  Uniswap V3 LP
        |
        v
AccountingManager  --->  SendraStorage
```

### Contracts

| Contract | Responsibility |
|---|---|
| `LiquidityCreditEnclaveFactory` | Creates enclaves: SRPE rules, executor deployment, storage registration, access control |
| `EnclavesStorage` | Enclave metadata, pause/deposit flags, lookups by id or executor address |
| `LiquidityLogic` | Enclave implementation: deposit/withdraw credit, provide/close liquidity, pause controls |
| `LiquidityOrchestratorEvo` | Coordinates swaps and Uniswap V3 liquidity (provide, withdraw, collect fees) |
| `AccountingManager` | Writes enclave and user positions into `SendraStorage` (only callable by registered enclaves) |
| `AccessControlInter` | `isSendraEnclave` registry for executor authentication |

### Libraries

| Library | Responsibility |
|---|---|
| `LPCE.lib.sol` | Enclave and creation parameter structs |
| `Sendra.lib.sol` | Position and user structs aligned with Sendra storage |
| `uni.lib.sol` | Uniswap V3 swap and liquidity instruction structs |

### External dependencies

- **[SRPE](https://github.com/Sendra-labs/SRPE)** — Rule-bound executor deployment (`RPFPDeployer`) and per-function constraints.
- **Sendra core** — `AddressProvider`, `SendraStorage`, `SendraRoles`, `LiquidityManager`, and related interfaces under `src/interfaces/iSendraCore/`.

---

## Basic flow

1. The **Capital Provider** calls `createEnclave` on `LiquidityCreditEnclaveFactory` with `CreateEnclaveParams`.
2. The factory builds **SRPE rules** (amount bounds, deadline, operator, allowed senders) and deploys a **`LiquidityLogic`** executor via `RPFPDeployer`.
3. The enclave is **registered** in `EnclavesStorage` and flagged in `AccessControlInter`.
4. The lender **deposits credit** (`depositCredit`) — enclave moves toward **Active**.
5. The **operator** executes `provideLiquidity`; `LiquidityOrchestratorEvo` opens the Uniswap V3 position; `AccountingManager` records it.
6. The operator (or lender) may **close positions** (`closePosition`) before withdrawal.
7. Lender and/or operator call **`withdrawCredit`** to settle USDC and profit split; accounting positions are updated — enclave **Closed**.

---

## Allowed operations (LiquidityLogic)

Bound at creation time through SRPE rules in the factory:

| Function | Who can call (via rules) | Purpose |
|---|---|---|
| `provideLiquidity` | Operator | Deploy USDC into Uniswap V3 LP within min/max and before deadline |
| `closePosition` | Lender or operator | Withdraw LP and update accounting |
| `depositCredit` | Lender | Fund the enclave with USDC |
| `withdrawCredit` | Lender or operator | Return capital and split profit |
| `pauseExecution` / `unpauseExecution` | Lender | Halt or resume execution |

---

## Design principles

- **Capital isolation** — Each enclave has its own executor address and storage record.
- **Controlled execution** — Only SRPE-permitted selectors; no free transfers to the operator.
- **No unrestricted custody** — Capital remains in the enclave contract.
- **Traceable positions** — LP and credit flows are recorded in `SendraStorage` via `AccountingManager`.
- **Accounting-first** — Relevant operations produce structured position data.
- **Modular layout** — Factory, storage, access control, execution logic, orchestration, and accounting are separate contracts.
- **Beta minimalism** — A single verifiable path: create → deposit → operate → close → withdraw.

---

## What this is not

- Not an overcollateralized lending protocol (e.g. Aave-style).
- Not a passive yield vault.
- Not a system where the operator receives funds with unrestricted withdrawal rights.
- Not an off-chain asset manager.
- Does not promise returns.
- Does not ship a single automated strategy; it enables **rule-bound execution** inside an enclave.

---

## Repository layout

```
src/
├── core/
│   ├── factory/LiquidityCreditEnclaveFactory.sol
│   ├── execution/
│   │   ├── LiquidityLogic.sol
│   │   ├── LiquidityOrchestratorEvo.sol
│   │   └── AccountingManager.sol
│   └── storage/
│       ├── EnclavesStorage.sol
│       └── security/AccessControlInter.sol
├── interfaces/iSendraCore/
└── libs/
    ├── LPCE.lib.sol
    ├── Sendra.lib.sol
    └── uni.lib.sol
```

---

## Status

This repository contains the **beta implementation** of Liquidity Credit Enclaves. Contracts are under active development and intended for **controlled testing environments** before any unrestricted production deployment.

The system is designed for controlled beta usage with known operators and limited capital exposure. It has not been audited.

---

## Development

Requires [Foundry](https://book.getfoundry.sh/). Initialize submodules (includes `forge-std` and `SRPE`):

```bash
git submodule update --init --recursive
```

```bash
forge build
forge test
forge fmt
```

Solidity `0.8.28`. Remappings in `foundry.toml`: `srpe/=lib/SRPE/`, `forge-std/=lib/forge-std/src/`.

---

## Positioning

Credit Enclaves are a product-level implementation of **rule-bound capital delegation** for liquidity operations: capital providers supply capital, operators execute within constraints, and the protocol records every position as structured on-chain data.
