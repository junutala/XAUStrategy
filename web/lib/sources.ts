// Free market-data sources. Every function is defensive: on any failure it
// throws, and the caller (buildReport) falls back to synthetic values so the
// page always renders.

export interface Bars {
  dates: string[]; // ISO yyyy-mm-dd
  open: number[];
  high: number[];
  low: number[];
  close: number[];
}

const UA =
  "Mozilla/5.0 (compatible; XAUDesk/0.1; +https://vercel.com)";

// ---- Yahoo Finance chart API (no key) --------------------------------------
// e.g. symbol "GC=F" (gold futures), "DX-Y.NYB" (DXY), "SI=F" (silver),
// "GDX", "^GVZ" (gold VIX), "BTC-USD", "^GSPC", "CL=F", "PL=F", "PA=F", "HG=F"
export async function yahooBars(
  symbol: string,
  range = "6mo",
  interval = "1d",
  revalidate = 60,
): Promise<Bars> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}` +
    `?range=${range}&interval=${interval}&includePrePost=false`;
  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/json" },
    next: { revalidate },
  });
  if (!res.ok) throw new Error(`yahoo ${symbol} ${res.status}`);
  const j: any = await res.json();
  const r = j?.chart?.result?.[0];
  if (!r) throw new Error(`yahoo ${symbol} empty`);
  const ts: number[] = r.timestamp || [];
  const q = r.indicators?.quote?.[0] || {};
  const dates: string[] = [];
  const open: number[] = [];
  const high: number[] = [];
  const low: number[] = [];
  const close: number[] = [];
  for (let i = 0; i < ts.length; i++) {
    const c = q.close?.[i];
    if (c == null) continue;
    dates.push(new Date(ts[i] * 1000).toISOString().slice(0, 10));
    open.push(q.open?.[i] ?? c);
    high.push(q.high?.[i] ?? c);
    low.push(q.low?.[i] ?? c);
    close.push(c);
  }
  if (close.length < 5) throw new Error(`yahoo ${symbol} too few points`);
  return { dates, open, high, low, close };
}

// ---- FRED CSV (no key) — used for US 10y real yield DFII10 ------------------
export async function fredSeries(
  id: string,
  revalidate = 3600,
): Promise<{ dates: string[]; values: number[] }> {
  const url = `https://fred.stlouisfed.org/graph/fredgraph.csv?id=${id}`;
  const res = await fetch(url, {
    headers: { "User-Agent": UA },
    next: { revalidate },
  });
  if (!res.ok) throw new Error(`fred ${id} ${res.status}`);
  const text = await res.text();
  const lines = text.trim().split("\n").slice(1);
  const dates: string[] = [];
  const values: number[] = [];
  for (const line of lines) {
    const [d, v] = line.split(",");
    const n = parseFloat(v);
    if (!isNaN(n)) {
      dates.push(d);
      values.push(n);
    }
  }
  if (!values.length) throw new Error(`fred ${id} empty`);
  return { dates, values };
}

// ---- CFTC COT (Socrata, no key) — speculative net positioning ---------------
// Two datasets cover everything we chart:
//   6dca-aqww  Disaggregated futures-only (commodities: metals, energy)
//   gpe5-46if  Traders in Financial Futures (FX, indices, crypto)
// Column names differ between them (and have changed over time), so we pull the
// whole row and probe a list of known long/short field pairs.
const COT_DATASETS: Record<string, string> = {
  disaggregated: "6dca-aqww",
  financial: "gpe5-46if",
};

const COT_FIELD_PAIRS: [string, string][] = [
  ["m_money_positions_long_all", "m_money_positions_short_all"], // disaggregated managed money
  ["lev_money_positions_long", "lev_money_positions_short"], // TFF leveraged funds
  ["lev_money_positions_long_all", "lev_money_positions_short_all"],
  ["noncomm_positions_long_all", "noncomm_positions_short_all"], // legacy non-commercial
];

function pickNet(row: Record<string, unknown>): number | null {
  for (const [lk, sk] of COT_FIELD_PAIRS) {
    const l = parseFloat(String(row[lk]));
    const sh = parseFloat(String(row[sk]));
    if (!isNaN(l) && !isNaN(sh)) return l - sh;
  }
  return null;
}

export async function cftcNet(
  code: string,
  dataset: "disaggregated" | "financial" = "disaggregated",
  invert = false,
  revalidate = 21600,
): Promise<{ dates: string[]; net: number[]; weeklyChange: number[] }> {
  const res_id = COT_DATASETS[dataset] || COT_DATASETS.disaggregated;
  const url =
    `https://publicreporting.cftc.gov/resource/${res_id}.json` +
    `?$where=cftc_contract_market_code='${code}'` +
    "&$order=report_date_as_yyyy_mm_dd DESC&$limit=20";
  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/json" },
    next: { revalidate },
  });
  if (!res.ok) throw new Error(`cftc ${code} ${res.status}`);
  const rows: Record<string, unknown>[] = await res.json();
  if (!rows?.length) throw new Error(`cftc ${code} empty`);
  rows.reverse(); // newest-first -> chronological
  const dates: string[] = [];
  const net: number[] = [];
  for (const r of rows) {
    const n = pickNet(r);
    if (n == null) continue;
    dates.push(String(r.report_date_as_yyyy_mm_dd).slice(0, 10));
    net.push(invert ? -n : n);
  }
  if (net.length < 2) throw new Error(`cftc ${code} no usable columns`);
  const weeklyChange: number[] = [];
  for (let i = 1; i < net.length; i++)
    weeklyChange.push((net[i] - net[i - 1]) / 1000); // thousands of contracts
  return { dates, net, weeklyChange };
}

// ---- Curated US high-impact event calendar ---------------------------------
// No reliable free calendar API; we generate the recurring US macro events that
// move every dollar-denominated market from known rules (NFP = first Friday)
// plus a scheduled FOMC list. The "watch" column is written from the selected
// instrument's dollar / real-yield sensitivity, so the same calendar reads
// correctly for gold, EURUSD, USDJPY or Nasdaq.
export interface CalItem {
  date: string;
  event: string;
  impact: "High" | "Med" | "Low";
  watch: string;
}

export interface EventTone {
  usdBeta: -1 | 0 | 1; // pair's response to a stronger dollar
  yieldBeta: -1 | 0 | 1; // pair's response to higher real yields
}

const FOMC_2026 = [
  "2026-01-28",
  "2026-03-18",
  "2026-04-29",
  "2026-06-17",
  "2026-07-29",
  "2026-09-16",
  "2026-10-28",
  "2026-12-16",
];

function firstFriday(year: number, month0: number): Date {
  const d = new Date(Date.UTC(year, month0, 1));
  const day = d.getUTCDay(); // 0 Sun..6 Sat
  const offset = (5 - day + 7) % 7; // to Friday
  return new Date(Date.UTC(year, month0, 1 + offset));
}

function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// "Hot" US data => stronger dollar and higher yields. Translate that into what
// it means for this particular pair.
function hotWatch(t: EventTone, what: string): string {
  const score = t.usdBeta + t.yieldBeta; // +2 helped .. -2 hurt by hot data
  if (score > 0) return `hot ${what} = tailwind`;
  if (score < 0) return `hot ${what} = headwind`;
  return `hot ${what} = two-way, trade the level`;
}
function softWatch(t: EventTone, what: string): string {
  const score = t.usdBeta + t.yieldBeta;
  if (score > 0) return `soft ${what} = headwind`;
  if (score < 0) return `soft ${what} = tailwind`;
  return `soft ${what} = two-way, trade the level`;
}

export function eventCalendar(
  today = new Date(),
  horizonDays = 10,
  tone: EventTone = { usdBeta: -1, yieldBeta: -1 },
): CalItem[] {
  const items: CalItem[] = [];
  const y = today.getUTCFullYear();
  const m = today.getUTCMonth();
  // NFP for this and next month
  for (const mm of [m, m + 1]) {
    const yy = y + Math.floor(mm / 12);
    const mo = ((mm % 12) + 12) % 12;
    items.push({
      date: iso(firstFriday(yy, mo)),
      event: "US Nonfarm Payrolls",
      impact: "High",
      watch: hotWatch(tone, "jobs"),
    });
    // CPI ~ mid-month (approx, verify)
    items.push({
      date: iso(new Date(Date.UTC(yy, mo, 12))),
      event: "US CPI (approx)",
      impact: "High",
      watch: softWatch(tone, "CPI"),
    });
    // PCE ~ end of month (approx)
    items.push({
      date: iso(new Date(Date.UTC(yy, mo, 27))),
      event: "US Core PCE (approx)",
      impact: "Med",
      watch: "Fed's preferred gauge",
    });
  }
  for (const f of FOMC_2026)
    items.push({
      date: f,
      event: "FOMC decision",
      impact: "High",
      watch: "rate path + dots move the dollar",
    });

  const start = iso(today);
  const end = iso(new Date(today.getTime() + horizonDays * 864e5));
  return items
    .filter((e) => e.date >= start && e.date <= end)
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(0, 6);
}
