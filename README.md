# XAUStrategy

Tools for **intraday scalping**, built around a top-down bias → setup → trigger workflow.
Originally gold-only; the dashboard and the Pine strategy now work on **any pair you
select** — XAUUSD, EURUSD, USDJPY, BTCUSD, NAS100, WTI, an equity ticker, …

## Contents

- **`web/`** — a Next.js desk-report dashboard for Vercel. Five sections: macro regime,
  an intraday scalping cockpit (10m→5m→1m), desk call, peer-group / intermarket
  rotation, and setups / levels / event risk. Pick the pair in the header (or pass
  `?pair=EURUSD`) and every number, chart and the embedded TradingView chart follow.
  Uses free data sources (Yahoo Finance, FRED, CFTC) with graceful fallback.
  See [`web/README.md`](web/README.md).
- **`TopDown_Scalping_Strategy.pine`** — a TradingView Pine v5 **strategy** (backtestable +
  alerts) implementing the same top-down logic: 10m/15m bias filter, EMA9×EMA21
  trigger, VWAP + RSI, ATR stops/targets, session & news filters. Symbol-agnostic —
  it trades whatever chart you apply it to.
- **`Triple_EMA_Cross_Alerts.pine`** — a lightweight EMA-cross alert indicator (the seed
  of the scalping trigger).

## The two layers

| Layer | Where | Purpose |
|-------|-------|---------|
| **Decision / briefing** | `web/` on Vercel | Read it to set your daily bias, key levels, and event risk — for the pair you select. |
| **Execution** | TradingView Pine | Live 1m chart, MTF triggers, alerts, and backtest on the same pair. |

Read the report → form a bias → execute the scalps on TradingView.

Not investment advice.
