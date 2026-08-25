# Desk Report — multi-pair trading dashboard

A Next.js dashboard that builds a full desk report for **whatever pair you select** —
XAUUSD, XAGUSD, EURUSD, USDJPY, BTCUSD, NAS100, WTI, or any TradingView symbol you
type in. Five sections:

1. **Macro Regime** — spot / vol index / DXY / US 10y real-yield KPIs, a regime read
   written from the selected pair's own dollar and real-yield sensitivity, plus price,
   vol-band and CFTC-positioning charts (the last two appear only when that pair has a
   vol index or a futures contract).
2. **Intraday Scalping Cockpit** — top-down **10m → 5m → 1m** bias→setup→trigger stack,
   VWAP + EMA9/EMA21 chart, a session clock for that asset class, live scalp card, and
   the rules checklist. (Pairs with `../TopDown_Scalping_Strategy.pine` for execution.)
3. **Desk Call** — trend / momentum / ADX / RSI / expected-move signals per timeframe
   with support/resistance, plus a real-yield overlay.
4. **Peer group & Intermarket** — an **RRG** of the pair's peer complex (metals for
   metals, G10 for FX, sectors for indices, …) and a correlation panel.
5. **Setups, Levels & Event Risk** — pivots/levels, ATR-based setups, reversal watch,
   the US event calendar with the watch column written for that pair, 10-year
   seasonality, and a backtested EMA9/21 track record with its recent signals.

## Selecting a pair

- The **Pair** control in the header switches the whole report; the URL carries it
  (`/?pair=EURUSD`), so a pair is bookmarkable and shareable.
- The dropdown lists the built-in catalog (`lib/instruments.ts`). The text box next to
  it accepts **any TradingView symbol** — `OANDA:EURJPY`, `NASDAQ:AAPL`, `BTCUSDT`,
  aliases like `GOLD` or `US100`. Unknown symbols are mapped to a Yahoo data symbol by
  convention (FX → `EURJPY=X`, crypto → `SOL-USD`, anything else → the plain ticker)
  and flagged in the footer notes so you can sanity-check the mapping.
- **The TradingView embed follows the picker, not the other way round.** TradingView's
  free widget can't report a symbol change back to the page, so symbol switching inside
  the chart is disabled — otherwise the chart and the computed numbers would silently
  disagree. Switch pairs with the picker and both stay in sync.

Adding a pair to the catalog is one entry in `lib/instruments.ts`: Yahoo symbol,
TradingView symbol, decimals, dollar/real-yield betas, optional vol index and CFTC
contract, peer list, session clock.

The page **always renders**: every data source is fetched defensively and falls back to
deterministic synthetic values (scaled to that pair's price level) on failure, so a
blocked feed never breaks the report. A **LIVE / SAMPLE DATA** banner and per-panel
notes tell you which is showing.

## Data sources (all free, no API key)

| Data | Source | Endpoint |
|------|--------|----------|
| Prices, peers, correlation basket, vol indices (GVZ / VIX / VXN / OVX / EVZ) | Yahoo Finance chart API | `query1.finance.yahoo.com/v8/finance/chart/{symbol}` |
| US 10y real yield (TIPS, `DFII10`) | FRED CSV | `fred.stlouisfed.org/graph/fredgraph.csv?id=DFII10` |
| CFTC positioning — managed money (commodities) / leveraged funds (FX, indices, crypto) | CFTC Socrata | `publicreporting.cftc.gov/resource/{6dca-aqww,gpe5-46if}.json` |
| US event calendar | Curated (NFP = first Friday, scheduled FOMC list, approx CPI/PCE) | in code |

Each `fetch` uses Next.js `revalidate` caching (60 s for prices, hourly for FRED, 6 h for
COT), so the app is cheap to run on Vercel's free tier.

## Run locally

```bash
cd web
npm install
npm run dev      # http://localhost:3000  ·  http://localhost:3000/?pair=EURUSD
```

`GET /api/report?pair=NAS100` returns the full report as JSON (handy for debugging, and
for checking which symbol a custom input resolved to).

## Deploy to Vercel

1. Push this repo to GitHub (already connected).
2. In Vercel: **New Project → import the repo**.
3. Set **Root Directory = `web`** (the Next.js app lives in the subfolder).
4. Framework preset auto-detects **Next.js**. No env vars required.
5. Deploy. (Optional: add a **Vercel Cron** hitting `/` or `/api/report` to keep the
   cache warm before your London/NY sessions.)

## Notes & known limitations

- **Intraday coverage varies by symbol.** Yahoo serves 5m bars for futures, FX and
  crypto, but some tickers (and some hours) return nothing — the cockpit then falls back
  to sample values and says so in the footer.
- **CFTC positioning** only exists for instruments with a US futures contract; the panel
  is hidden for the rest. Column names differ between the disaggregated and financial
  datasets, so the fetcher probes several known long/short field pairs.
- **Event calendar** is scheduled/approximate — NFP is exact (first Friday), FOMC uses a
  static 2026 list, CPI/PCE are month-approximate. Swap in a calendar API for precision.
  The calendar itself is US-only: for a EUR- or JPY-driven session you still need the
  local central-bank dates.
- **Track record / recent signals** are a backtest of the EMA9/21 daily cross on the last
  6 months, not executed trades. Persisting real calls needs a store (Vercel KV/Postgres).
- **Live in-browser 1-minute tape** would need a streaming/paid feed; this build uses
  Yahoo's delayed 5-minute intraday bars for the cockpit chart, which is fine for a
  session briefing. Do live execution on TradingView with the Pine strategy.
- The data feeds could not be exercised from the build sandbox (its network policy
  allowlists only package registries); they are standard public endpoints and run
  normally on Vercel.

Not investment advice. Nothing here is a trade trigger.
