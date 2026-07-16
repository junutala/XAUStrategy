# XAU·Desk — 5-Day Gold Report

A Next.js dashboard for **XAUUSD (spot gold)** trading — a gold-native adaptation of a
classic equity desk report, built for a scalper. Five sections:

1. **Macro Regime** — XAUUSD / GVZ / DXY / US 10y real-yield KPIs, a regime read, and
   price / GVZ-bands / CFTC-positioning charts.
2. **Intraday Scalping Cockpit** — top-down **10m → 5m → 1m** bias→setup→trigger stack,
   VWAP + EMA9/EMA21 chart, session clock, live scalp card, and the rules checklist.
   (Pairs with `../XAU_Scalping_Strategy.pine` for TradingView execution + backtest.)
3. **Desk Call** — trend / momentum / ADX / RSI / expected-move signals per timeframe
   with support/resistance, plus a real-yield-vs-gold overlay.
4. **Metals Complex & Intermarket** — a precious-metals **RRG** (silver, platinum,
   palladium, miners vs gold) and a 20-day correlation panel.
5. **Setups, Levels & Event Risk** — pivots/levels, ATR-based setups, reversal watch,
   a curated US event calendar, gold seasonality, and a backtested track record.

The page **always renders**: every data source is fetched defensively and falls back to
deterministic synthetic values on failure, so a blocked feed never breaks the report.
A **LIVE / SAMPLE DATA** banner and per-panel notes tell you which is showing.

## Data sources (all free, no API key)

| Data | Source | Endpoint |
|------|--------|----------|
| Gold, DXY, silver, miners, platinum, palladium, copper, GVZ, BTC, SPX, oil, 10Y | Yahoo Finance chart API | `query1.finance.yahoo.com/v8/finance/chart/{symbol}` |
| US 10y real yield (TIPS, `DFII10`) | FRED CSV | `fred.stlouisfed.org/graph/fredgraph.csv?id=DFII10` |
| CFTC managed-money positioning (COMEX gold `088691`) | CFTC Socrata | `publicreporting.cftc.gov/resource/6dca-aqww.json` |
| US event calendar | Curated (NFP = first Friday, scheduled FOMC list, approx CPI/PCE) | in code |

Each `fetch` uses Next.js `revalidate` caching (15 min for intraday/prices, hourly for
FRED, 6 h for COT), so the app is cheap to run on Vercel's free tier.

## Run locally

```bash
cd web
npm install
npm run dev      # http://localhost:3000
```

`GET /api/report` returns the full report as JSON (handy for debugging).

## Deploy to Vercel

1. Push this repo to GitHub (already connected).
2. In Vercel: **New Project → import the repo**.
3. Set **Root Directory = `web`** (the Next.js app lives in the subfolder).
4. Framework preset auto-detects **Next.js**. No env vars required.
5. Deploy. (Optional: add a **Vercel Cron** hitting `/` or `/api/report` to keep the
   ISR cache warm before your London/NY sessions.)

## Notes & known limitations

- **Timeframes**: the scalping cockpit is wired for 10m/5m/1m. Switch the bias layer to
  15m by changing the intraday resample in `lib/report.ts` (and `biasTF` in `sampleReport`).
- **Event calendar** is scheduled/approximate — NFP is exact (first Friday), FOMC uses a
  static 2026 list, CPI/PCE are month-approximate. Swap in a calendar API for precision.
- **Predictions-vs-actuals** is illustrative until a results store (e.g. Vercel KV/Postgres)
  is added to persist each day's rank-1 call and score it forward.
- **Live in-browser 1-minute tape** would need a streaming/paid feed; this build uses
  Yahoo's delayed 5-minute intraday bars for the cockpit chart, which is fine for a
  session briefing. Do live execution on TradingView with the Pine strategy.
- The data feeds could not be exercised from the build sandbox (its network policy
  allowlists only package registries); they are standard public endpoints and run
  normally on Vercel.

Not investment advice. Nothing here is a trade trigger.
