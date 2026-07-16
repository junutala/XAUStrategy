# XAUStrategy

Tools for trading **XAUUSD (spot gold)**, built around an intraday scalping workflow.

## Contents

- **`web/`** — **XAU·Desk**, a Next.js desk-report dashboard for Vercel. Five sections:
  macro regime, an intraday scalping cockpit (10m→5m→1m), desk call, metals-complex /
  intermarket rotation, and setups / levels / event risk. Uses free data sources
  (Yahoo Finance, FRED, CFTC) with graceful fallback. See [`web/README.md`](web/README.md).
- **`XAU_Scalping_Strategy.pine`** — a TradingView Pine v5 **strategy** (backtestable +
  alerts) implementing the same top-down scalping logic: 10m/15m bias filter, EMA9×EMA21
  trigger, VWAP + RSI, ATR stops/targets, session & news filters.
- **`Triple_EMA_Cross_Alerts.pine`** — a lightweight EMA-cross alert indicator (the seed
  of the scalping trigger).

## The two layers

| Layer | Where | Purpose |
|-------|-------|---------|
| **Decision / briefing** | `web/` on Vercel | Read it to set your daily bias, key levels, and event risk. |
| **Execution** | TradingView Pine | Live 1m chart, MTF triggers, alerts, and backtest. |

Read the report → form a bias → execute the scalps on TradingView.

Not investment advice.
