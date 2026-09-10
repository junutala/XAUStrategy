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
- **`ARUN_Indicator_Pro.pine`** — the ARUN Pro v7 confidence-engine indicator: EMA
  cross + slow-EMA side entries, MTF and ATR-normalised angle filters, and a dashboard
  covering the price range over the Slow EMA's own window (high / low / mid, where price
  sits inside it, and the room left to each wall in ATR) plus a confidence score over the
  last N setups.
  Reads the chart's own symbol, and all thresholds are measured in ATR so it works on
  any pair you select.
- **`ARUN_EMA_CROSS_EA.mq5`** — a MetaTrader 5 Expert Advisor implementing the
  `ARUN_EMA_CROSS_V1` indicator's two-stage cross as a tradable, backtestable strategy:
  Fast/Mid and Fast/Slow crosses inside a bar window, then a confirmation candle that
  opens and closes beyond the Slow EMA, with an optional RSI-divergence filter, an
  average-candle take profit and configurable stops.
- **`ARUN_ANGLE_DRIFT_EA.mq5`** — the measurement build: the same two-stage cross, gated
  by ATR-normalised angle drift on the Fast EMA, with no fixed take profit or stop
  distance. Exits on momentum decay (an adverse angle move larger than the trade's own
  average angle gain), on peak-profit giveback, or on a wide catastrophic stop. Prints a
  drift run-length histogram and a signal funnel so the thresholds get set from data.
- **`ARUN_MTF_TPSL_EA.mq5`** — a separate line of enquiry, sharing no code with the drift
  build. The Fast EMA must cross the Mid or the Slow EMA on a higher timeframe, the same
  cross must then happen on the chart timeframe while the higher-timeframe one is still
  fresh, and the last candle must be completely clear of the Slow EMA. The trade is then
  left alone: a fixed take profit and stop, both specified in account currency and
  converted to a price distance from the tick value and the lot size actually traded, so
  the +$2 / -$2 at 0.03 lots holds if the size changes. Because nothing manages the trade
  after entry, the CSV it writes measures the entry and only the entry.
- **`ARUN_SIGNAL_PROBE_EA.mq5`** — the same entry signal as the MTF build, but it places
  no orders at all. At every signal it records where price went over eight horizons at
  once, with the best and worst excursion inside each, measured from the mid price. A
  fixed bracket can only answer whether the entry beats the spread over the one distance
  you chose; set that distance too short and the answer is always no, because the spread
  toll per trade is flat in the bracket width while any edge grows with its square. This
  build removes the bracket so the horizon and the take profit can be read off the data
  instead of guessed.
- **`Triple_EMA_Cross_Alerts.pine`** — a lightweight EMA-cross alert indicator (the seed
  of the scalping trigger).

## The two layers

| Layer | Where | Purpose |
|-------|-------|---------|
| **Decision / briefing** | `web/` on Vercel | Read it to set your daily bias, key levels, and event risk — for the pair you select. |
| **Execution** | TradingView Pine | Live 1m chart, MTF triggers, alerts, and backtest on the same pair. |

Read the report → form a bias → execute the scalps on TradingView.

Not investment advice.
