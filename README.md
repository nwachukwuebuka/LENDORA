# LENDORA (deFi Protocol) — Preliminary Whitepaper

## 1. Overview

This project is a decentralized finance (DeFi) protocol designed to provide lending, borrowing, and token swapping.

The project will be developed incrementally, with a strong focus on security, transparent rules, and understanding how each component works before moving to the next.

## 2. Project Goals

- Allow users to lend supported crypto assets and earn interest.
- Allow users to borrow assets against collateral.
- Allow liquidity providers to supply tokens to swap pools and earn trading fees.
- Build and test the protocol using Solidity and Foundry.
- Prioritize security and testing throughout development.

Cross-chain bridging and a native protocol token are planned as possible future services. They are not part of the initial implementation.

## 3. Lending and Borrowing

### Separate asset pools

Each supported asset will have its own lending pool. For example, a USDC pool accepts USDC, while a WETH pool accepts WETH.

### Collateral and borrowing

- Maximum initial borrowing LTV: 70%.
- Liquidation threshold: 80%.
- Liquidation bonus: 5%.
- Liquidation close factor: 50% of the borrower's outstanding debt per liquidation transaction.

Borrowing is limited by both available pool liquidity and the borrower's collateral value.

### Minimum lending amount

The intended minimum deposit is $1,000 worth of the supported asset. A price oracle will be needed to calculate the USD value.

The precise enforcement rules for individual deposits versus aggregate deposits remain to be finalized.

## 4. Interest Rate Model

Borrowing interest depends on pool utilization, using the following proposed rate bands:

| Pool utilization | Borrowing APR |
|---|---:|
| 0%–below 30% | 2% |
| 30%–below 75% | 5% |
| 75%–100% | 10% |

The rate changes at the 30% and 75% thresholds. This is a step-based rate model.

Interest income will be allocated as follows:

- 90% to lenders.
- 10% to the protocol reserve.

The reserve is intended to support protocol sustainability and may help absorb losses, but it is not a guarantee against all losses.

## 5. Lender Withdrawal Rules

### Flexible lending

Flexible lenders will have a cumulative immediate withdrawal allowance of 20% of their deposit. Withdrawals remain subject to available liquidity.

Withdrawals beyond the allowance may be submitted as withdrawal orders eligible for processing after 12 hours. This is not a guarantee of payment within 12 hours; an order may remain pending if liquidity is unavailable.

### Locked lending

- One lock cycle: 84 days.
- Project time convention: 28 days per month.
- Total lock duration: 2,016 hours.
- Early exit is permitted subject to a penalty.
- Higher fee-sharing benefits end when the lender exits early.

The maximum early-exit penalty rate is provisionally set at 5%, subject to further review.

### Early-exit penalty formula

Penalty = InitialLend × PenaltyRate × (HoursLeft / TotalHours)

The penalty decreases as the remaining lock time decreases and becomes zero at maturity.

The proposed penalty distribution is:

- 40% to eligible locked lenders who complete the full lock period, shared equally.
- 60% to the lending pool.

The method for tracking eligible lenders and distributing penalties will be finalized during implementation.

## 6. Token Swapping

The protocol will implement its own constant-product automated market maker (AMM), inspired by Uniswap V2.

The core relationship is:

x × y = k

Here, x and y represent the token reserves in a pool. A swap changes the reserve ratio, which determines the amount of tokens received.

A proposed swap fee is 0.3% per trade. This fee has not yet been finalized.

Liquidity providers will deposit both assets in a pool and receive a share of the pool's liquidity. They may earn swap fees and are exposed to impermanent loss.

## 7. Planned Development Stages

1. Set up the Foundry project and define interfaces.
2. Implement and test lending and borrowing.
3. Implement collateral checks, liquidations, and lender withdrawals.
4. Implement the constant-product swap pools.
5. Add security tests and review the protocol's accounting.
6. Consider bridging and a native token as separate future services.

## 8. Development Principles

- Build incrementally.
- Test each component before adding the next.
- Use mock tokens and a mock price oracle for initial local testing.
- Document decisions and unresolved questions in this README.
- Treat all parameters as subject to change until implementation and testing confirm the design.

## 9. Current Status

**Stage:** Initial design and project setup.

The protocol is not deployed and has not been audited. All proposed features require implementation, testing, and security review before any real funds are used.
