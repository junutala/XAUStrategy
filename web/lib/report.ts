import {
  ema,
  rsi,
  atr,
  adx,
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
  cftcNet,
  eventCalendar,
  Bars,
  CalItem,
} from "./sources";
import {
  Instrument,
  SessionBand,
  resolveInstrument,
  peersFor,
  correlatesFor,
  DEFAULT_INSTRUMENT_ID,
} from "./instruments";

// ---------------------------------------------------------------------------
// Types — all instrument-agnostic. Nothing here says "gold".
// ---------------------------------------------------------------------------
export interface Series {
  labels: string[];
  values: number[];
}
export interface KPI {
  price: number;
  priceChgPct: number;
  vol: number | null; // instrument's vol index (GVZ / VIX / OVX / EVZ …)
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
/** The slice of the instrument definition the UI needs. */
export interface InstrumentView {
  id: string;
  pair: string;
  label: string;
  klass: string;
  tv: string;
  yahoo: string;
  decimals: number;
  quoteCcy: string;
  volLabel: string | null;
  volBands: [number, number, number] | null;
  volRange: [number, number] | null;
  cotLabel: string | null;
  peerLabel: string;
  sessions: SessionBand[];
  custom: boolean;
}
export interface Report {
  instrument: InstrumentView;
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
  vol: Series | null;
  cot: number[] | null;
  driverOverlay: { price: number[]; realInv: number[] } | null;
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
// Small helpers
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
/** Round to the instrument's own price precision. */
function px(inst: Instrument, n: number): number {
  return round(n, inst.decimals);
}
function view(inst: Instrument): InstrumentView {
  return {
    id: inst.id,
    pair: inst.pair,
    label: inst.label,
    klass: inst.klass,
    tv: inst.tv,
    yahoo: inst.yahoo,
    decimals: inst.decimals,
    quoteCcy: inst.quoteCcy,
    volLabel: inst.vol?.label ?? null,
    volBands: inst.vol?.bands ?? null,
    volRange: inst.vol?.range ?? null,
    cotLabel: inst.cot?.label ?? null,
    peerLabel: inst.peerLabel,
    sessions: inst.sessions,
    custom: !!inst.custom,
  };
}
function fmtRange(today: Date): string {
  const from = new Date(today.getTime() - 6 * 864e5);
  const opt: Intl.DateTimeFormatOptions = { day: "2-digit", month: "short" };
  return `${from.toLocaleDateString("en-GB", opt)} – ${today.toLocaleDateString("en-GB", { ...opt, year: "numeric" })}`;
}

// ---------------------------------------------------------------------------
// Deterministic synthetic fallback, scaled to the instrument's price level so
// the page always renders something plausible for whatever pair was picked.
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

export function sampleReport(inst: Instrument, today = new Date()): Report {
  const rng = mulberry32(20260716);
  const A = inst.sampleAnchor; // price anchor
  const N = 40;
  // Drift chosen so the walk lands on the anchor rather than jumping to it.
  const price = walk(rng, N, A * 0.975, A * 0.006, (A * 0.025) / N);
  price[N - 1] = A;
  const bands = inst.vol?.bands ?? [12, 18, 24];
  const volMid = bands[1] * 0.87;
  const volSeries: number[] = [];
  let v = bands[1];
  for (let i = 0; i < N; i++) {
    v += (volMid - v) * 0.08 + (rng() - 0.5) * bands[0] * 0.1;
    volSeries.push(Math.max(bands[0] * 0.7, v));
  }
  const realInv: number[] = [];
  let r = 0;
  for (let i = 0; i < N; i++) {
    r += (i / N) * 0.04 + (rng() - 0.5) * 0.6;
    realInv.push(r);
  }
  const M = 90;
  const intraday = walk(rng, M, A * 0.9985, A * 0.0008, (A * 0.0015) / M);
  intraday[M - 1] = A;
  const vwap: number[] = [];
  let s = 0;
  for (let i = 0; i < M; i++) {
    s += intraday[i];
    vwap.push(s / (i + 1));
  }
  const labels = Array.from({ length: N }, (_, i) => String(i));
  const a = A * 0.006; // ~ATR
  const P = (x: number) => px(inst, x);

  return {
    instrument: view(inst),
    meta: {
      dateRange: fmtRange(today),
      generated: today.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }),
      live: false,
      sources: ["synthetic sample"],
      notes: ["Showing synthetic placeholder data — live sources unavailable."],
    },
    kpi: {
      price: P(A),
      priceChgPct: 0.42,
      vol: inst.vol ? round(volMid, 1) : null,
      dxy: 97.8,
      dxyChgPct: -0.3,
      realYield: 1.78,
      realYieldChgBp: -4,
    },
    regime: {
      badge: "Sample · no live feed",
      text: `Synthetic placeholder for ${inst.pair} — live sources unavailable, so nothing below is a real read.`,
      tone: "neutral",
    },
    price: { labels, values: price },
    vol: inst.vol ? { labels, values: volSeries } : null,
    cot: inst.cot ? [7, 11, -6, 9, 4, -9, 14, -21, 8, 6, -13, 7, 10, -5] : null,
    driverOverlay: { price, realInv },
    scalp: {
      intraday,
      vwap,
      ema9: ema(intraday, 9),
      ema21: ema(intraday, 21),
      playbook: "Trend-Pullback",
      playbookText:
        "Trade with-trend entries off pullbacks to VWAP / EMA — skip counter-trend fades until momentum stalls.",
      biasTF: "10m",
      setupTF: "5m",
      triggerTF: "1m",
      biasState: "Long ↑",
      setupState: "Pullback forming",
      triggerState: "Long trigger ✓",
      biasTone: "Long",
      triggerTone: "Long",
      live: {
        entry: P(A),
        stop: P(A - a),
        t1: P(A + a * 1.3),
        t2: P(A + a * 2.5),
        spread: round(A * 0.00006, Math.max(2, inst.decimals)),
      },
    },
    signals: [
      { tf: "H4", verdict: "Long", momentum: "Firm", adx: 27, rsi: 61, expMove: P(a), support: P(A - a * 3), resist: P(A + a * 3) },
      { tf: "Daily", verdict: "Long", momentum: "Firm", adx: 26, rsi: 58, expMove: P(a * 2), support: P(A - a * 6), resist: P(A + a * 6) },
      { tf: "Weekly", verdict: "Neutral", momentum: "Weak", adx: 18, rsi: 54, expMove: P(a * 4), support: P(A - a * 12), resist: P(A + a * 12) },
    ],
    stance: [
      { tf: "H4", text: "Long — momentum + trend aligned; trail stop under the last swing." },
      { tf: "Daily", text: "Long — press on ADX ≥ 25 (met); risk defined below the pivot." },
      { tf: "Weekly", text: "Stand aside / small — ADX < 25, no edge; wait for a range break." },
    ],
    rrg: [],
    corr: [],
    seasonality: [1.8, 0.4, -0.2, 0.9, -0.3, -0.6, 0.7, 1.2, 1.5, 0.3, 0.8, 1.4],
    seasonalityMonth: today.getUTCMonth(),
    setups: [
      { name: "Pullback-buy", bias: "Long", entry: P(A - a), stop: P(A - a * 2), t1: P(A + a * 0.3), t2: P(A + a * 1.5), rr: 1.3 },
      { name: "Breakout", bias: "Long", entry: P(A + a * 3), stop: P(A + a * 2), t1: P(A + a * 4.3), t2: P(A + a * 5.5), rr: 1.3 },
      { name: "Fade into R", bias: "Short", entry: P(A + a * 3), stop: P(A + a * 4), t1: P(A + a * 1.7), t2: P(A + a * 0.5), rr: 1.3 },
    ],
    levels: [
      { name: "Swing high (20d)", type: "Resistance", price: P(A + a * 3) },
      { name: "Pivot R1", type: "Resistance", price: P(A + a * 1.5) },
      { name: "Round number", type: "Magnet", price: round(A / inst.roundStep) * inst.roundStep },
      { name: "Daily pivot", type: "Pivot", price: P(A) },
      { name: "Pivot S1", type: "Support", price: P(A - a * 1.5) },
      { name: "Swing low (20d)", type: "Support", price: P(A - a * 3) },
    ],
    reversal: [{ signal: "Reversal watch", what: "sample data — no live signal", rsi: 55, score: 40 }],
    events: eventCalendar(today, 10, { usdBeta: inst.usdBeta, yieldBeta: inst.yieldBeta }),
    track: [],
    predictions: [],
  };
}

// ---------------------------------------------------------------------------
// Live-path helpers
// ---------------------------------------------------------------------------
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

// Peer feeds don't share a session calendar (crypto trades 7 days, futures 5,
// FX has its own holidays), so intermarket maths is done on dates the two
// series actually share rather than on raw tail indices.
function alignOnDates(a: Bars, b: Bars): { a: number[]; b: number[] } {
  const m = new Map<string, number>();
  for (let i = 0; i < b.dates.length; i++) m.set(b.dates[i], b.close[i]);
  const x: number[] = [];
  const y: number[] = [];
  for (let i = 0; i < a.dates.length; i++) {
    const v = m.get(a.dates[i]);
    if (v != null) {
      x.push(a.close[i]);
      y.push(v);
    }
  }
  return x.length >= 25 ? { a: x, b: y } : { a: a.close, b: b.close };
}

function momentumLabel(a: number): string {
  if (isNaN(a)) return "—";
  if (a >= 25) return "Strong";
  if (a >= 20) return "Firm";
  return "Weak";
}

function computeSignal(inst: Instrument, tf: string, b: Bars): SignalRow {
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
    expMove: px(inst, lastFinite(a)),
    support: px(inst, Math.min(...look)),
    resist: px(inst, Math.max(...look)),
  };
}

// Light backtest of the daily EMA9/EMA21 cross for the track-record table.
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
    for (let j = i + 1; j <= i + 10 && j < c.length; j++) {
      if (dir * (c[j] - t1) >= 0) {
        side.hit++;
        break;
      }
      if (dir * (st - c[j]) >= 0) {
        side.stopped++;
        break;
      }
    }
    const exit = c[Math.min(i + 10, c.length - 1)];
    side.ret += (dir * (exit - entry)) / entry;
    side.trades++;
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

// The last few EMA9/21 crosses with their realised 1D / 5D returns — a real
// (if simple) scorecard instead of hard-coded illustrative rows.
function recentCalls(b: Bars): PredRow[] {
  const c = b.close;
  const e9 = ema(c, 9);
  const e21 = ema(c, 21);
  const a = atr(toOHLC(b), 14);
  const rows: PredRow[] = [];
  for (let i = 30; i < c.length; i++) {
    const up = e9[i] > e21[i] && e9[i - 1] <= e21[i - 1];
    const dn = e9[i] < e21[i] && e9[i - 1] >= e21[i - 1];
    if (!up && !dn) continue;
    const dir = up ? 1 : -1;
    const entry = c[i];
    const risk = a[i] || entry * 0.005;
    const r1 = i + 1 < c.length ? round((dir * (c[i + 1] - entry) * 100) / entry, 2) : null;
    const r5 = i + 5 < c.length ? round((dir * (c[i + 5] - entry) * 100) / entry, 2) : null;
    let status = "Open";
    for (let j = i + 1; j <= i + 10 && j < c.length; j++) {
      if (dir * (c[j] - (entry + dir * risk * 1.3)) >= 0) {
        status = "T1 hit";
        break;
      }
      if (dir * (entry - dir * risk * 1.1 - c[j]) >= 0) {
        status = "Stopped";
        break;
      }
    }
    if (status === "Open" && i + 10 < c.length) status = "Timed out";
    const dt = new Date(b.dates[i] + "T00:00:00Z");
    rows.push({
      date: dt.toLocaleDateString("en-GB", { day: "2-digit", month: "short", timeZone: "UTC" }),
      call: `EMA9×21 ${up ? "bull" : "bear"} cross`,
      bias: up ? "Long" : "Short",
      r1,
      r5,
      status,
    });
  }
  return rows.slice(-5).reverse();
}

// ---------------------------------------------------------------------------
// buildReport(pair): sample base for the chosen instrument, overlaid with
// whatever live sources succeed. Everything below is driven by the instrument
// definition — no symbol is hard-coded.
// ---------------------------------------------------------------------------
export async function buildReport(pair?: string | null): Promise<Report> {
  const inst = resolveInstrument(pair || DEFAULT_INSTRUMENT_ID);
  const today = new Date();
  const rep = sampleReport(inst, today);
  const notes: string[] = [];
  const sources: string[] = [];
  let live = false;

  // ---- core: instrument daily bars ----
  let daily: Bars | null = null;
  try {
    daily = await yahooBars(inst.yahoo, "6mo", "1d");
    live = true;
    sources.push(`Yahoo (${inst.pair} ${inst.yahoo})`);
    const c = daily.close;
    rep.price = { labels: tail(daily.dates, 40), values: tail(c, 40) };
    rep.kpi.price = px(inst, c[c.length - 1]);
    rep.kpi.priceChgPct = round(pctChange(c, 1), 2);

    const dSig = computeSignal(inst, "Daily", daily);
    const wSig = computeSignal(inst, "Weekly", groupBars(daily, weekKey));
    rep.signals = [rep.signals[0], dSig, wSig]; // H4 filled below if intraday works
    rep.track = backtest(daily);
    rep.predictions = recentCalls(daily);

    // levels from the last daily bar (classic pivots) + 20-day swing
    const n = c.length - 1;
    const H = daily.high[n],
      L = daily.low[n],
      C = c[n];
    const P = (H + L + C) / 3;
    const swingHi = Math.max(...tail(daily.high, 20));
    const swingLo = Math.min(...tail(daily.low, 20));
    rep.levels = [
      { name: "Swing high (20d)", type: "Resistance", price: px(inst, swingHi) },
      { name: "Pivot R1", type: "Resistance", price: px(inst, 2 * P - L) },
      { name: "Round number", type: "Magnet", price: round(Math.round(C / inst.roundStep) * inst.roundStep, inst.decimals) },
      { name: "Daily pivot", type: "Pivot", price: px(inst, P) },
      { name: "Pivot S1", type: "Support", price: px(inst, 2 * P - H) },
      { name: "Swing low (20d)", type: "Support", price: px(inst, swingLo) },
    ];
    const a = lastFinite(atr(toOHLC(daily), 14)) || C * 0.006;
    rep.setups = [
      { name: "Pullback-buy", bias: "Long", entry: px(inst, P), stop: px(inst, P - a), t1: px(inst, P + a * 1.3), t2: px(inst, P + a * 2.5), rr: 1.3 },
      { name: "Breakout", bias: "Long", entry: px(inst, swingHi), stop: px(inst, swingHi - a), t1: px(inst, swingHi + a * 1.3), t2: px(inst, swingHi + a * 2.5), rr: 1.3 },
      { name: "Fade into R", bias: "Short", entry: px(inst, swingHi), stop: px(inst, swingHi + a), t1: px(inst, swingHi - a * 1.3), t2: px(inst, swingHi - a * 2.5), rr: 1.3 },
    ];
    const rsNow = lastFinite(rsi(c, 14));
    rep.reversal = [
      {
        signal: dSig.verdict === "Long" ? "Overbought watch" : "Reversal watch",
        what: `Daily RSI ${round(rsNow)} · ADX ${dSig.adx}`,
        rsi: round(rsNow),
        score: round(Math.abs(rsNow - 50) + dSig.adx),
      },
    ];
    rep.stance = [
      { tf: "H4", text: `${rep.signals[0].verdict} — intraday alignment; trail under the recent swing.` },
      { tf: "Daily", text: `${dSig.verdict} — press on ADX ≥ 25 (now ${dSig.adx}); risk below ${rep.levels[4].price}.` },
      { tf: "Weekly", text: `${wSig.verdict} — ${wSig.adx < 25 ? "no edge, wait for a break of " + rep.levels[0].price + " / " + rep.levels[5].price : "trend intact"}.` },
    ];
  } catch {
    notes.push(`${inst.pair} price feed unavailable — using sample prices.`);
  }

  // ---- seasonality (10y monthly) ----
  try {
    const mo = await yahooBars(inst.yahoo, "10y", "1mo");
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

  // ---- instrument's volatility index, if it has one ----
  if (inst.vol) {
    try {
      const v = await yahooBars(inst.vol.sym, "3mo", "1d");
      rep.vol = { labels: tail(v.dates, 40), values: tail(v.close, 40) };
      rep.kpi.vol = round(v.close[v.close.length - 1], 1);
      sources.push(`Yahoo (${inst.vol.sym})`);
    } catch {
      notes.push(`${inst.vol.label} feed unavailable — using sample.`);
    }
  } else {
    rep.vol = null;
    rep.kpi.vol = null;
  }

  // ---- DXY (dollar backdrop — relevant to every USD-quoted pair) ----
  let dxy: Bars | null = null;
  try {
    dxy = await yahooBars("DX-Y.NYB", "3mo", "1d");
    rep.kpi.dxy = round(dxy.close[dxy.close.length - 1], 1);
    rep.kpi.dxyChgPct = round(pctChange(dxy.close, 1), 2);
    sources.push("Yahoo (DXY)");
  } catch {
    notes.push("DXY feed unavailable — using sample.");
  }

  // ---- US 10y real yield (FRED DFII10) ----
  try {
    const ry = await fredSeries("DFII10");
    rep.kpi.realYield = round(ry.values[ry.values.length - 1], 2);
    rep.kpi.realYieldChgBp = round((ry.values[ry.values.length - 1] - ry.values[ry.values.length - 2]) * 100);
    if (daily) {
      rep.driverOverlay = {
        price: tail(daily.close, 40),
        realInv: tail(ry.values, 40).map((x) => -x),
      };
    }
    sources.push("FRED (real yield DFII10)");
  } catch {
    notes.push("FRED real-yield feed unavailable — using sample.");
  }

  // ---- CFTC positioning, when the instrument has a futures contract ----
  if (inst.cot) {
    try {
      const cot = await cftcNet(inst.cot.code, inst.cot.dataset, inst.cot.invert);
      if (cot.weeklyChange.length) rep.cot = tail(cot.weeklyChange, 14).map((x) => round(x));
      sources.push(`CFTC (${inst.pair} COT)`);
    } catch {
      rep.cot = null;
      notes.push("CFTC positioning unavailable for this pair.");
    }
  } else {
    rep.cot = null;
  }

  // ---- intermarket: relative strength (RRG) + correlations ----
  if (daily) {
    const pts: RRGPoint[] = [];
    for (const p of peersFor(inst)) {
      try {
        const b = await yahooBars(p.sym, "6mo", "1d");
        const al = alignOnDates(b, daily);
        const { ratio, momentum } = rsRatioMomentum(al.a, al.b, 20);
        if (!isFinite(ratio) || !isFinite(momentum)) continue;
        pts.push({ rank: 0, name: p.name, x: round(ratio, 1), y: round(momentum, 2), quadrant: quadrant(ratio, momentum) });
      } catch {
        /* skip this leg */
      }
    }
    if (pts.length >= 3) {
      pts.sort((a, b) => b.x - a.x);
      pts.forEach((p, i) => (p.rank = i + 1));
      rep.rrg = pts;
      sources.push(`Yahoo (${inst.peerLabel.toLowerCase()})`);
    } else {
      notes.push("Peer-group feeds unavailable — relative-strength panel is empty.");
    }

    const corr: CorrRow[] = [];
    for (const c of correlatesFor(inst)) {
      try {
        const b = c.sym === "DX-Y.NYB" && dxy ? dxy : await yahooBars(c.sym, "3mo", "1d");
        const al = alignOnDates(daily, b);
        const v = correlationOfReturns(al.a, al.b);
        if (isFinite(v)) corr.push({ k: c.name, v: round(v, 2) });
      } catch {
        /* skip */
      }
    }
    if (corr.length) {
      corr.sort((a, b) => Math.abs(b.v) - Math.abs(a.v));
      rep.corr = corr.slice(0, 8);
    } else {
      notes.push("Correlation feeds unavailable.");
    }
  }

  // ---- intraday cockpit (5m) ----
  try {
    const intr = await yahooBars(inst.yahoo, "5d", "5m");
    const c = tail(intr.close, 90);
    const vwap: number[] = [];
    let s = 0;
    for (let i = 0; i < c.length; i++) {
      s += c[i];
      vwap.push(s / (i + 1));
    }
    const e9 = ema(c, 9);
    const e21 = ema(c, 21);
    const lastC = c[c.length - 1];
    const biasUp = e9[e9.length - 1] > e21[e21.length - 1] && lastC > vwap[vwap.length - 1];
    const trigUp = e9[e9.length - 1] > e21[e21.length - 1];
    const cOHLC: OHLC = { open: c, high: c, low: c, close: c };
    const a5 = lastFinite(atr(cOHLC, 14)) || lastC * 0.0006;
    const dir = biasUp ? 1 : -1;
    const trending = lastFinite(adx(cOHLC, 14)) >= 20;
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
      playbook: trending ? "Trend-Pullback" : "Range-Fade",
      playbookText: trending
        ? `${inst.pair} is trending on the 5m with ATR expanding — take with-trend entries off pullbacks to VWAP / EMA21 and skip counter-trend fades.`
        : `${inst.pair} is ranging on the 5m — fade the edges back to VWAP, keep targets tight and stand aside on the break.`,
      live: {
        entry: px(inst, lastC),
        stop: px(inst, lastC - dir * a5 * 1.1),
        t1: px(inst, lastC + dir * a5 * 1.3),
        t2: px(inst, lastC + dir * a5 * 2.5),
        spread: round(lastC * 0.00006, Math.max(2, inst.decimals)),
      },
    };
    // H4 signal from 60m bars, resampled 4:1
    try {
      const h1 = await yahooBars(inst.yahoo, "1mo", "60m");
      const h4 = groupBars(h1, (_d, i) => String(Math.floor(i / 4)));
      rep.signals[0] = computeSignal(inst, "H4", h4);
    } catch {
      /* keep the existing H4 row */
    }
    sources.push("Yahoo (intraday 5m)");
  } catch {
    notes.push("Intraday feed unavailable — scalping cockpit using sample.");
  }

  // ---- regime read, expressed in the instrument's own sensitivities --------
  if (live) {
    const dxyUp = rep.kpi.dxyChgPct > 0;
    const ryUp = rep.kpi.realYieldChgBp > 0;
    // + = supportive for this pair, − = a drag
    const usdPush = (dxyUp ? 1 : -1) * inst.usdBeta;
    const yieldPush = (ryUp ? 1 : -1) * inst.yieldBeta;
    const score = usdPush + yieldPush;
    const bands = inst.vol?.bands;
    const volState = rep.kpi.vol == null || !bands ? null : rep.kpi.vol < bands[1] ? "contained" : "elevated";
    const drivers: string[] = [];
    if (inst.usdBeta !== 0) drivers.push(`Dollar ${dxyUp ? "firm" : "soft"}`);
    if (inst.yieldBeta !== 0) drivers.push(`real yields ${ryUp ? "rising" : "easing"}`);
    if (volState) drivers.push(`${inst.vol!.label.split(" ")[0]} ${volState}`);
    rep.regime = {
      badge: score > 0 ? "Tailwind · Long-friendly" : score < 0 ? "Headwind · Cautious" : "Mixed · Two-way",
      tone: score > 0 ? "long" : score < 0 ? "short" : "neutral",
      text:
        (drivers.length ? drivers.join(", ") + ". " : "") +
        (score > 0
          ? `Backdrop favours directional longs in ${inst.pair} with defined risk; fade rallies only into resistance.`
          : score < 0
            ? `Backdrop is a headwind for ${inst.pair}; prefer fades into resistance or stand aside.`
            : `Drivers are mixed for ${inst.pair} — trade levels, keep size modest.`),
    };
  }

  // ---- events, written for this pair's sensitivities ----
  rep.events = eventCalendar(today, 10, { usdBeta: inst.usdBeta, yieldBeta: inst.yieldBeta });

  if (inst.custom)
    notes.push(
      `${inst.pair} is not in the built-in catalog — mapped to Yahoo symbol "${inst.yahoo}" by convention. If the numbers look wrong, the mapping is the first thing to check.`,
    );

  rep.meta = {
    dateRange: fmtRange(today),
    generated: today.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }),
    live,
    sources: sources.length ? sources : ["synthetic sample"],
    notes: [
      ...notes,
      "Event calendar is scheduled/approx (NFP = first Friday, FOMC list) — verify before trading.",
      "Track record and recent calls are a backtest of the EMA9/21 cross on daily bars, not executed trades.",
    ],
  };
  return rep;
}
