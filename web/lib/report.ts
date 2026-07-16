import {
  ema,
  rsi,
  atr,
  adx,
  sma,
  pctChange,
  lastFinite,
  correlationOfReturns,
  rsRatioMomentum,
  quadrant,
  OHLC,
} from "./indicators";
import {
  yahooBars,
  fredSeries,
  cftcGoldNet,
  eventCalendar,
  Bars,
  CalItem,
} from "./sources";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export interface Series {
  labels: string[];
  values: number[];
}
export interface KPI {
  xau: number;
  xauChgPct: number;
  gvz: number;
  dxy: number;
  dxyChgPct: number;
  realYield: number;
  realYieldChgBp: number;
}
export type Bias = "Long" | "Short" | "Neutral";
export interface SignalRow {
  tf: string;
  verdict: Bias;
  momentum: string;
  adx: number;
  rsi: number;
  expMove: number;
  support: number;
  resist: number;
}
export interface RRGPoint {
  rank: number;
  name: string;
  x: number;
  y: number;
  quadrant: "Leading" | "Improving" | "Weakening" | "Lagging";
}
export interface CorrRow {
  k: string;
  v: number;
}
export interface Level {
  name: string;
  type: string;
  price: number;
}
export interface Setup {
  name: string;
  bias: Bias;
  entry: number;
  stop: number;
  t1: number;
  t2: number;
  rr: number;
}
export interface TrackRow {
  bias: Bias;
  trades: number;
  avg: number;
  hit: number;
  stopped: number;
}
export interface PredRow {
  date: string;
  call: string;
  bias: Bias;
  r1: number | null;
  r5: number | null;
  status: string;
}
export interface Report {
  meta: {
    dateRange: string;
    generated: string;
    live: boolean;
    sources: string[];
    notes: string[];
  };
  kpi: KPI;
  regime: { badge: string; text: string; tone: "long" | "short" | "neutral" };
  price: Series;
  gvz: Series;
  cot: number[];
  realYieldVsGold: { gold: number[]; realInv: number[] };
  scalp: {
    intraday: number[];
    vwap: number[];
    ema9: number[];
    ema21: number[];
    playbook: string;
    playbookText: string;
    biasTF: string;
    setupTF: string;
    triggerTF: string;
    biasState: string;
    setupState: string;
    triggerState: string;
    biasTone: Bias;
    triggerTone: Bias;
    live: { entry: number; stop: number; t1: number; t2: number; spread: number };
  };
  signals: SignalRow[];
  stance: { tf: string; text: string }[];
  rrg: RRGPoint[];
  corr: CorrRow[];
  seasonality: number[];
  seasonalityMonth: number;
  setups: Setup[];
  levels: Level[];
  reversal: { signal: string; what: string; rsi: number; score: number }[];
  events: CalItem[];
  track: TrackRow[];
  predictions: PredRow[];
}

// ---------------------------------------------------------------------------
// Deterministic synthetic fallback (so the page always renders)
// ---------------------------------------------------------------------------
function mulberry32(a: number) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function walk(rng: () => number, n: number, start: number, vol: number, drift: number) {
  const a: number[] = [];
  let v = start;
  for (let i = 0; i < n; i++) {
    v += drift + (rng() - 0.5) * vol;
    a.push(v);
  }
  return a;
}
function fmtRange(today: Date): string {
  const from = new Date(today.getTime() - 6 * 864e5);
  const opt: Intl.DateTimeFormatOptions = { day: "2-digit", month: "short" };
  return `${from.toLocaleDateString("en-GB", opt)} – ${today.toLocaleDateString("en-GB", { ...opt, year: "numeric" })}`;
}

export function sampleReport(today = new Date()): Report {
  const rng = mulberry32(20260716);
  const N = 40;
  const gold = walk(rng, N, 3262, 15, 2.3);
  gold[N - 1] = 3351;
  const gvz: number[] = [];
  let v = 18;
  for (let i = 0; i < N; i++) {
    v += (15.6 - v) * 0.08 + (rng() - 0.5) * 1.3;
    gvz.push(Math.max(10, v));
  }
  gvz[N - 1] = 15.6;
  const realInv: number[] = [];
  let r = 0;
  for (let i = 0; i < N; i++) {
    r += (i / N) * 0.04 + (rng() - 0.5) * 0.6;
    realInv.push(r);
  }
  const M = 90;
  const intraday = walk(rng, M, 3345, 0.9, 0.055);
  intraday[M - 1] = 3349.5;
  const vwap: number[] = [];
  let s = 0;
  for (let i = 0; i < M; i++) {
    s += intraday[i];
    vwap.push(s / (i + 1));
  }
  const labels = Array.from({ length: N }, (_, i) => String(i));

  return {
    meta: {
      dateRange: fmtRange(today),
      generated: today.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }),
      live: false,
      sources: ["synthetic sample"],
      notes: ["Showing synthetic placeholder data — live sources unavailable."],
    },
    kpi: { xau: 3351, xauChgPct: 0.42, gvz: 15.6, dxy: 97.8, dxyChgPct: -0.3, realYield: 1.78, realYieldChgBp: -4 },
    regime: {
      badge: "Tailwind · Long-friendly",
      text: "Dollar soft, real yields easing, vol contained. Backdrop favours directional longs with defined risk; fade rallies only into resistance.",
      tone: "long",
    },
    price: { labels, values: gold },
    gvz: { labels, values: gvz },
    cot: [7, 11, -6, 9, 4, -9, 14, -21, 8, 6, -13, 7, 10, -5],
    realYieldVsGold: { gold, realInv },
    scalp: {
      intraday,
      vwap,
      ema9: ema(intraday, 9),
      ema21: ema(intraday, 21),
      playbook: "Trend-Pullback",
      playbookText:
        "NY session, trending up, ATR expanding. Trade with-trend longs off pullbacks to VWAP / EMA — skip counter-trend fades until momentum stalls.",
      biasTF: "10m",
      setupTF: "5m",
      triggerTF: "1m",
      biasState: "Long ↑",
      setupState: "Pullback forming",
      triggerState: "Long trigger ✓",
      biasTone: "Long",
      triggerTone: "Long",
      live: { entry: 3349.5, stop: 3346.5, t1: 3353.5, t2: 3357.0, spread: 0.2 },
    },
    signals: [
      { tf: "H4", verdict: "Long", momentum: "Firm", adx: 27, rsi: 61, expMove: 14, support: 3338, resist: 3372 },
      { tf: "Daily", verdict: "Long", momentum: "Firm", adx: 26, rsi: 58, expMove: 31, support: 3305, resist: 3378 },
      { tf: "Weekly", verdict: "Neutral", momentum: "Weak", adx: 18, rsi: 54, expMove: 72, support: 3244, resist: 3431 },
    ],
    stance: [
      { tf: "H4", text: "Long — momentum + trend aligned; trail stop under 3,338 swing." },
      { tf: "Daily", text: "Long — press on ADX ≥ 25 (met); risk defined below 3,305." },
      { tf: "Weekly", text: "Stand aside / small — ADX < 25, no edge; wait for break of 3,431 or 3,244." },
    ],
    rrg: [
      { rank: 1, name: "Silver (XAG)", x: 105.1, y: 4.2, quadrant: "Leading" },
      { rank: 2, name: "Silver miners SIL", x: 104.0, y: 6.1, quadrant: "Leading" },
      { rank: 3, name: "Junior miners GDXJ", x: 103.0, y: 7.4, quadrant: "Leading" },
      { rank: 4, name: "Gold miners GDX", x: 99.2, y: 5.0, quadrant: "Improving" },
      { rank: 5, name: "Platinum", x: 101.8, y: -2.8, quadrant: "Weakening" },
      { rank: 6, name: "Copper", x: 98.4, y: 2.1, quadrant: "Improving" },
      { rank: 7, name: "Palladium", x: 96.1, y: -4.9, quadrant: "Lagging" },
    ],
    corr: [
      { k: "Silver (XAG)", v: 0.86 },
      { k: "Real yield", v: -0.82 },
      { k: "DXY", v: -0.71 },
      { k: "US10Y nom.", v: -0.55 },
      { k: "Bitcoin", v: 0.41 },
      { k: "S&P 500", v: 0.24 },
      { k: "WTI oil", v: 0.16 },
    ],
    seasonality: [1.8, 0.4, -0.2, 0.9, -0.3, -0.6, 0.7, 1.2, 1.5, 0.3, 0.8, 1.4],
    seasonalityMonth: today.getUTCMonth(),
    setups: [
      { name: "XAU pullback-buy", bias: "Long", entry: 3332, stop: 3304, t1: 3378, t2: 3410, rr: 1.6 },
      { name: "XAU breakout", bias: "Long", entry: 3379, stop: 3351, t1: 3412, t2: 3448, rr: 1.2 },
      { name: "Fade into 3,431", bias: "Short", entry: 3428, stop: 3449, t1: 3388, t2: 3360, rr: 1.9 },
    ],
    levels: [
      { name: "Weekly R1", type: "Resistance", price: 3431 },
      { name: "Prior day high", type: "Resistance", price: 3372 },
      { name: "Round number", type: "Magnet", price: 3350 },
      { name: "Daily pivot", type: "Pivot", price: 3341 },
      { name: "50% Fib (swing)", type: "Support", price: 3318 },
      { name: "Weekly S1", type: "Support", price: 3244 },
    ],
    reversal: [{ signal: "Bearish RSI div", what: "H4 price ↑ / RSI ↓", rsi: 61, score: 45 }],
    events: eventCalendar(today),
    track: [
      { bias: "Long", trades: 412, avg: 0.71, hit: 44.9, stopped: 28.4 },
      { bias: "Short", trades: 261, avg: -0.22, hit: 31.0, stopped: 41.7 },
    ],
    predictions: [
      { date: "16 Jul", call: "XAU pullback-buy", bias: "Long", r1: null, r5: null, status: "Open" },
      { date: "15 Jul", call: "Break 3,340", bias: "Long", r1: 0.61, r5: null, status: "Open" },
      { date: "14 Jul", call: "Fade 3,360", bias: "Short", r1: -0.38, r5: null, status: "Stopped" },
      { date: "11 Jul", call: "XAU dip-buy", bias: "Long", r1: 0.44, r5: 1.72, status: "T1 hit" },
    ],
  };
}

// ---------------------------------------------------------------------------
// Helpers for the live path
// ---------------------------------------------------------------------------
function toOHLC(b: Bars): OHLC {
  return { open: b.open, high: b.high, low: b.low, close: b.close };
}
function tail<T>(a: T[], n: number): T[] {
  return a.slice(Math.max(0, a.length - n));
}
function round(n: number, d = 0): number {
  const f = Math.pow(10, d);
  return Math.round(n * f) / f;
}

function groupBars(b: Bars, keyFn: (d: string, i: number) => string): Bars {
  const out: Bars = { dates: [], open: [], high: [], low: [], close: [] };
  let curKey = "";
  for (let i = 0; i < b.close.length; i++) {
    const k = keyFn(b.dates[i], i);
    if (k !== curKey) {
      out.dates.push(b.dates[i]);
      out.open.push(b.open[i]);
      out.high.push(b.high[i]);
      out.low.push(b.low[i]);
      out.close.push(b.close[i]);
      curKey = k;
    } else {
      const j = out.close.length - 1;
      out.high[j] = Math.max(out.high[j], b.high[i]);
      out.low[j] = Math.min(out.low[j], b.low[i]);
      out.close[j] = b.close[i];
    }
  }
  return out;
}
function weekKey(d: string): string {
  const dt = new Date(d + "T00:00:00Z");
  const onejan = new Date(Date.UTC(dt.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((dt.getTime() - onejan.getTime()) / 864e5 + onejan.getUTCDay() + 1) / 7);
  return dt.getUTCFullYear() + "-" + week;
}

function momentumLabel(a: number): string {
  if (isNaN(a)) return "—";
  if (a >= 25) return "Strong";
  if (a >= 20) return "Firm";
  return "Weak";
}

function computeSignal(tf: string, b: Bars): SignalRow {
  const c = b.close;
  const e9 = ema(c, 9);
  const e21 = ema(c, 21);
  const e50 = ema(c, 50);
  const rs = rsi(c, 14);
  const a = atr(toOHLC(b), 14);
  const adxs = adx(toOHLC(b), 14);
  const lastC = c[c.length - 1];
  const f9 = lastFinite(e9);
  const f21 = lastFinite(e21);
  const f50 = lastFinite(e50);
  let verdict: Bias = "Neutral";
  if (f9 > f21 && lastC > f50) verdict = "Long";
  else if (f9 < f21 && lastC < f50) verdict = "Short";
  const look = tail(c, 20);
  return {
    tf,
    verdict,
    momentum: momentumLabel(lastFinite(adxs)),
    adx: round(lastFinite(adxs)),
    rsi: round(lastFinite(rs)),
    expMove: round(lastFinite(a)),
    support: round(Math.min(...look)),
    resist: round(Math.max(...look)),
  };
}

// Light backtest of daily EMA9/EMA21 cross for the track-record table.
function backtest(b: Bars): TrackRow[] {
  const c = b.close;
  const e9 = ema(c, 9);
  const e21 = ema(c, 21);
  const a = atr(toOHLC(b), 14);
  const long = { trades: 0, ret: 0, hit: 0, stopped: 0 };
  const short = { trades: 0, ret: 0, hit: 0, stopped: 0 };
  for (let i = 30; i < c.length - 10; i++) {
    const up = e9[i] > e21[i] && e9[i - 1] <= e21[i - 1];
    const dn = e9[i] < e21[i] && e9[i - 1] >= e21[i - 1];
    if (!up && !dn) continue;
    const entry = c[i];
    const risk = a[i] || entry * 0.005;
    const side = up ? long : short;
    const dir = up ? 1 : -1;
    const t1 = entry + dir * risk * 1.3;
    const st = entry - dir * risk * 1.1;
    let done = false;
    for (let j = i + 1; j <= i + 10 && j < c.length; j++) {
      if (dir * (c[j] - t1) >= 0) {
        side.hit++;
        done = true;
        break;
      }
      if (dir * (st - c[j]) >= 0) {
        side.stopped++;
        done = true;
        break;
      }
    }
    const exit = c[Math.min(i + 10, c.length - 1)];
    side.ret += (dir * (exit - entry)) / entry;
    side.trades++;
    void done;
  }
  const mk = (bias: Bias, s: typeof long): TrackRow => ({
    bias,
    trades: s.trades,
    avg: s.trades ? round((s.ret / s.trades) * 100, 2) : 0,
    hit: s.trades ? round((s.hit / s.trades) * 100, 1) : 0,
    stopped: s.trades ? round((s.stopped / s.trades) * 100, 1) : 0,
  });
  return [mk("Long", long), mk("Short", short)];
}

// ---------------------------------------------------------------------------
// buildReport: sample base, overlaid with whatever live sources succeed.
// ---------------------------------------------------------------------------
export async function buildReport(): Promise<Report> {
  const today = new Date();
  const rep = sampleReport(today);
  const notes: string[] = [];
  const sources: string[] = [];
  let live = false;

  // ---- core: gold daily ----
  let goldDaily: Bars | null = null;
  try {
    goldDaily = await yahooBars("GC=F", "6mo", "1d");
    live = true;
    sources.push("Yahoo (gold GC=F)");
    const c = goldDaily.close;
    const px = tail(c, 40);
    rep.price = { labels: tail(goldDaily.dates, 40), values: px };
    rep.kpi.xau = round(c[c.length - 1], 1);
    rep.kpi.xauChgPct = round(pctChange(c, 1), 2);

    const daily = computeSignal("Daily", goldDaily);
    const weekly = computeSignal("Weekly", groupBars(goldDaily, weekKey));
    rep.signals = [rep.signals[0], daily, weekly]; // keep H4 (filled below if intraday works)
    rep.track = backtest(goldDaily);

    // levels from last daily bar (classic pivots) + swing
    const n = c.length - 1;
    const H = goldDaily.high[n],
      L = goldDaily.low[n],
      C = c[n];
    const P = (H + L + C) / 3;
    const swingHi = Math.max(...tail(goldDaily.high, 20));
    const swingLo = Math.min(...tail(goldDaily.low, 20));
    rep.levels = [
      { name: "Swing high (20d)", type: "Resistance", price: round(swingHi, 1) },
      { name: "Pivot R1", type: "Resistance", price: round(2 * P - L, 1) },
      { name: "Round number", type: "Magnet", price: round(C / 50) * 50 },
      { name: "Daily pivot", type: "Pivot", price: round(P, 1) },
      { name: "Pivot S1", type: "Support", price: round(2 * P - H, 1) },
      { name: "Swing low (20d)", type: "Support", price: round(swingLo, 1) },
    ];
    const a = lastFinite(atr(toOHLC(goldDaily), 14)) || C * 0.006;
    rep.setups = [
      { name: "Pullback-buy", bias: "Long", entry: round(P, 1), stop: round(P - a, 1), t1: round(P + a * 1.3, 1), t2: round(P + a * 2.5, 1), rr: 1.3 },
      { name: "Breakout", bias: "Long", entry: round(swingHi, 1), stop: round(swingHi - a, 1), t1: round(swingHi + a * 1.3, 1), t2: round(swingHi + a * 2.5, 1), rr: 1.3 },
      { name: "Fade into R", bias: "Short", entry: round(swingHi, 1), stop: round(swingHi + a, 1), t1: round(swingHi - a * 1.3, 1), t2: round(swingHi - a * 2.5, 1), rr: 1.3 },
    ];
    const rsNow = lastFinite(rsi(c, 14));
    rep.reversal = [
      {
        signal: daily.verdict === "Long" ? "Overbought watch" : "Reversal watch",
        what: `Daily RSI ${round(rsNow)} · ADX ${daily.adx}`,
        rsi: round(rsNow),
        score: round(Math.abs(rsNow - 50) + daily.adx),
      },
    ];
    rep.stance = [
      { tf: "H4", text: `${rep.signals[0].verdict} — intraday alignment; trail under recent swing.` },
      { tf: "Daily", text: `${daily.verdict} — press on ADX ≥ 25 (now ${daily.adx}); risk below ${rep.levels[4].price}.` },
      { tf: "Weekly", text: `${weekly.verdict} — ${weekly.adx < 25 ? "no edge, wait for break of " + rep.levels[0].price + " / " + rep.levels[5].price : "trend intact"}.` },
    ];
  } catch (e) {
    notes.push("Gold price feed unavailable — using sample prices.");
  }

  // ---- gold seasonality (10y monthly) ----
  try {
    const mo = await yahooBars("GC=F", "10y", "1mo");
    const byMonth: number[][] = Array.from({ length: 12 }, () => []);
    for (let i = 1; i < mo.close.length; i++) {
      const m = new Date(mo.dates[i] + "T00:00:00Z").getUTCMonth();
      const r = (mo.close[i] - mo.close[i - 1]) / mo.close[i - 1];
      if (isFinite(r)) byMonth[m].push(r * 100);
    }
    rep.seasonality = byMonth.map((arr) => (arr.length ? round(arr.reduce((x, y) => x + y, 0) / arr.length, 2) : 0));
    sources.push("Yahoo (seasonality)");
  } catch {
    notes.push("Seasonality feed unavailable — using sample.");
  }

  // ---- GVZ (gold vol) ----
  try {
    const gvz = await yahooBars("^GVZ", "3mo", "1d");
    rep.gvz = { labels: tail(gvz.dates, 40), values: tail(gvz.close, 40) };
    rep.kpi.gvz = round(gvz.close[gvz.close.length - 1], 1);
    sources.push("Yahoo (GVZ)");
  } catch {
    notes.push("GVZ feed unavailable — using sample.");
  }

  // ---- DXY ----
  let dxy: Bars | null = null;
  try {
    dxy = await yahooBars("DX-Y.NYB", "3mo", "1d");
    rep.kpi.dxy = round(dxy.close[dxy.close.length - 1], 1);
    rep.kpi.dxyChgPct = round(pctChange(dxy.close, 1), 2);
    sources.push("Yahoo (DXY)");
  } catch {
    notes.push("DXY feed unavailable — using sample.");
  }

  // ---- real yield (FRED DFII10) ----
  try {
    const ry = await fredSeries("DFII10");
    rep.kpi.realYield = round(ry.values[ry.values.length - 1], 2);
    rep.kpi.realYieldChgBp = round((ry.values[ry.values.length - 1] - ry.values[ry.values.length - 2]) * 100);
    // inverted real yield vs gold overlay (align lengths)
    if (goldDaily) {
      const g = tail(goldDaily.close, 40);
      const inv = tail(ry.values, 40).map((x) => -x);
      rep.realYieldVsGold = { gold: g, realInv: inv };
    }
    sources.push("FRED (real yield DFII10)");
  } catch {
    notes.push("FRED real-yield feed unavailable — using sample.");
  }

  // ---- CFTC COT managed-money ----
  try {
    const cot = await cftcGoldNet();
    if (cot.weeklyChange.length) rep.cot = tail(cot.weeklyChange, 14).map((x) => round(x));
    sources.push("CFTC (COT gold)");
  } catch {
    notes.push("CFTC COT feed unavailable — using sample.");
  }

  // ---- intermarket: RRG + correlations ----
  try {
    if (goldDaily) {
      const gc = goldDaily.close;
      const complex: { key: string; name: string; sym: string }[] = [
        { key: "SI=F", name: "Silver (XAG)", sym: "SI=F" },
        { key: "SIL", name: "Silver miners SIL", sym: "SIL" },
        { key: "GDXJ", name: "Junior miners GDXJ", sym: "GDXJ" },
        { key: "GDX", name: "Gold miners GDX", sym: "GDX" },
        { key: "PL=F", name: "Platinum", sym: "PL=F" },
        { key: "HG=F", name: "Copper", sym: "HG=F" },
        { key: "PA=F", name: "Palladium", sym: "PA=F" },
      ];
      const pts: RRGPoint[] = [];
      for (const c of complex) {
        try {
          const b = await yahooBars(c.sym, "6mo", "1d");
          const { ratio, momentum } = rsRatioMomentum(b.close, gc, 20);
          pts.push({ rank: 0, name: c.name, x: round(ratio, 1), y: round(momentum, 2), quadrant: quadrant(ratio, momentum) });
        } catch {
          /* skip this leg */
        }
      }
      if (pts.length >= 3) {
        pts.sort((a, b) => b.x - a.x);
        pts.forEach((p, i) => (p.rank = i + 1));
        rep.rrg = pts;
        sources.push("Yahoo (metals complex)");
      }

      // correlations of daily returns vs gold
      const corr: CorrRow[] = [];
      const addCorr = async (label: string, sym: string) => {
        try {
          const b = await yahooBars(sym, "3mo", "1d");
          corr.push({ k: label, v: round(correlationOfReturns(gc, b.close), 2) });
        } catch {
          /* skip */
        }
      };
      await addCorr("Silver (XAG)", "SI=F");
      if (dxy) corr.push({ k: "DXY", v: round(correlationOfReturns(gc, dxy.close), 2) });
      await addCorr("US10Y nom.", "^TNX");
      await addCorr("Bitcoin", "BTC-USD");
      await addCorr("S&P 500", "^GSPC");
      await addCorr("WTI oil", "CL=F");
      if (corr.length >= 3) {
        corr.sort((a, b) => Math.abs(b.v) - Math.abs(a.v));
        rep.corr = corr;
      }
    }
  } catch {
    notes.push("Intermarket feeds partially unavailable — using sample where missing.");
  }

  // ---- intraday scalping cockpit (5m) ----
  try {
    const intr = await yahooBars("GC=F", "5d", "5m");
    const c = tail(intr.close, 90);
    const vwap: number[] = [];
    let s = 0;
    for (let i = 0; i < c.length; i++) {
      s += c[i];
      vwap.push(s / (i + 1));
    }
    const e9 = ema(c, 9);
    const e21 = ema(c, 21);
    const e50 = ema(c, 50);
    const lastC = c[c.length - 1];
    const biasUp = e9[e9.length - 1] > e21[e21.length - 1] && lastC > vwap[vwap.length - 1];
    const trigUp = e9[e9.length - 1] > e21[e21.length - 1];
    const cOHLC: OHLC = { open: c, high: c, low: c, close: c };
    const a5 = lastFinite(atr(cOHLC, 14)) || lastC * 0.0006;
    rep.scalp = {
      ...rep.scalp,
      intraday: c,
      vwap,
      ema9: e9,
      ema21: e21,
      biasState: biasUp ? "Long ↑" : "Short ↓",
      biasTone: biasUp ? "Long" : "Short",
      setupState: `RSI ${round(lastFinite(rsi(c, 14)))}`,
      triggerState: trigUp ? "Long trigger ✓" : "Short trigger ✓",
      triggerTone: trigUp ? "Long" : "Short",
      playbook: lastFinite(adx(cOHLC, 14)) >= 20 ? "Trend-Pullback" : "Range-Fade",
      live: {
        entry: round(lastC, 1),
        stop: round(lastC - (biasUp ? 1 : -1) * a5 * 1.1, 1),
        t1: round(lastC + (biasUp ? 1 : -1) * a5 * 1.3, 1),
        t2: round(lastC + (biasUp ? 1 : -1) * a5 * 2.5, 1),
        spread: 0.2,
      },
    };
    // H4 signal from 60m resampled
    try {
      const h1 = await yahooBars("GC=F", "1mo", "60m");
      const h4 = groupBars(h1, (_d, i) => String(Math.floor(i / 4)));
      rep.signals[0] = computeSignal("H4", h4);
    } catch {
      /* keep sample H4 */
    }
    sources.push("Yahoo (intraday 5m)");
  } catch {
    notes.push("Intraday feed unavailable — scalping cockpit using sample.");
  }

  // ---- regime read (derived) ----
  if (live) {
    const dxyDown = rep.kpi.dxyChgPct < 0;
    const ryDown = rep.kpi.realYieldChgBp < 0;
    const long = dxyDown && ryDown;
    const shortish = !dxyDown && !ryDown;
    rep.regime = {
      badge: long ? "Tailwind · Long-friendly" : shortish ? "Headwind · Cautious" : "Mixed · Two-way",
      tone: long ? "long" : shortish ? "short" : "neutral",
      text:
        `Dollar ${dxyDown ? "soft" : "firm"}, real yields ${ryDown ? "easing" : "rising"}, GVZ ${rep.kpi.gvz < 18 ? "contained" : "elevated"}. ` +
        (long
          ? "Backdrop favours directional longs with defined risk; fade rallies only into resistance."
          : shortish
            ? "Backdrop is a headwind for gold; prefer fades into resistance / stand aside."
            : "Drivers are mixed — trade levels, keep size modest."),
    };
  }

  // ---- events ----
  rep.events = eventCalendar(today);

  rep.meta = {
    dateRange: fmtRange(today),
    generated: today.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }),
    live,
    sources: sources.length ? sources : ["synthetic sample"],
    notes: [
      ...notes,
      "Event calendar is scheduled/approx (NFP=first Friday, FOMC list) — verify before trading.",
      "Predictions-vs-actuals is illustrative until a results store is added.",
    ],
  };
  return rep;
}
