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

// ---- CFTC COT (Socrata, no key) — managed-money net for COMEX gold ---------
// Dataset 6dca-aqww = Disaggregated Futures-Only. Gold contract code 088691.
export async function cftcGoldNet(
  revalidate = 21600,
): Promise<{ dates: string[]; net: number[]; weeklyChange: number[] }> {
  const url =
    "https://publicreporting.cftc.gov/resource/6dca-aqww.json" +
    "?$where=cftc_contract_market_code='088691'" +
    "&$order=report_date_as_yyyy_mm_dd DESC&$limit=20" +
    "&$select=report_date_as_yyyy_mm_dd,m_money_positions_long_all,m_money_positions_short_all";
  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/json" },
    next: { revalidate },
  });
  if (!res.ok) throw new Error(`cftc ${res.status}`);
  const rows: any[] = await res.json();
  if (!rows?.length) throw new Error("cftc empty");
  // rows are newest-first; reverse to chronological
  rows.reverse();
  const dates: string[] = [];
  const net: number[] = [];
  for (const r of rows) {
    const long = parseFloat(r.m_money_positions_long_all);
    const short = parseFloat(r.m_money_positions_short_all);
    if (isNaN(long) || isNaN(short)) continue;
    dates.push(String(r.report_date_as_yyyy_mm_dd).slice(0, 10));
    net.push(long - short);
  }
  const weeklyChange: number[] = [];
  for (let i = 1; i < net.length; i++)
    weeklyChange.push((net[i] - net[i - 1]) / 1000); // thousands of contracts
  return { dates, net, weeklyChange };
}

// ---- Curated US high-impact event calendar ---------------------------------
// No reliable free calendar API; we generate the recurring US macro events that
// move gold from known rules (NFP = first Friday) plus a scheduled FOMC list.
// Labelled "scheduled" in the UI — swap for a calendar API later for precision.
export interface CalItem {
  date: string;
  event: string;
  impact: "High" | "Med" | "Low";
  watch: string;
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

export function eventCalendar(today = new Date(), horizonDays = 10): CalItem[] {
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
      watch: "hot jobs = gold headwind",
    });
    // CPI ~ mid-month (approx, verify)
    items.push({
      date: iso(new Date(Date.UTC(yy, mo, 12))),
      event: "US CPI (approx)",
      impact: "High",
      watch: "softer = bullish gold",
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
      watch: "rate path + dots move gold",
    });

  const start = iso(today);
  const end = iso(new Date(today.getTime() + horizonDays * 864e5));
  return items
    .filter((e) => e.date >= start && e.date <= end)
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(0, 6);
}
