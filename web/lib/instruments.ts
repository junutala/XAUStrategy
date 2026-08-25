// Instrument catalog + resolver.
//
// Everything the dashboard used to hard-code about gold (Yahoo symbol, vol
// index, COT contract, peer complex, correlation basket, session clock, tick
// size) now lives here, one entry per tradable pair. `resolveInstrument()`
// maps whatever the user picked — a catalog id, a TradingView symbol such as
// "OANDA:EURUSD", or a bare ticker — onto one of these definitions, falling
// back to a heuristically-built definition for anything not in the catalog.

export type AssetClass = "metal" | "fx" | "crypto" | "index" | "energy" | "equity";

export interface Peer {
  name: string;
  sym: string; // Yahoo symbol
}

export interface VolIndex {
  sym: string; // Yahoo symbol, e.g. ^GVZ
  label: string; // e.g. "GVZ · gold vol"
  bands: [number, number, number];
  range: [number, number];
}

export interface CotSpec {
  code: string; // CFTC contract market code
  dataset: "disaggregated" | "financial";
  label: string; // e.g. "CFTC managed-money net"
  invert?: boolean; // e.g. JPY contract is JPY/USD — flip to read as USDJPY
}

export interface SessionBand {
  label: string;
  flex: number;
  tone: "quiet" | "active" | "prime" | "fading";
}

export interface Instrument {
  id: string; // canonical, uppercase, e.g. "XAUUSD"
  pair: string; // display pair, e.g. "XAUUSD"
  label: string; // e.g. "Gold"
  klass: AssetClass;
  tv: string; // TradingView symbol for the embed
  yahoo: string; // Yahoo symbol for all computed numbers
  quoteCcy: string;
  decimals: number; // price decimals
  roundStep: number; // "round number" magnet spacing
  usdBeta: -1 | 0 | 1; // sign of the pair's response to a stronger dollar
  yieldBeta: -1 | 0 | 1; // sign of its response to rising US real yields
  vol: VolIndex | null;
  cot: CotSpec | null;
  peers: Peer[]; // relative-strength complex (RRG)
  peerLabel: string; // heading for that complex
  correlates: Peer[]; // correlation basket
  sessions: SessionBand[];
  sampleAnchor: number; // nominal price used by the synthetic fallback
  custom?: boolean; // built by the resolver, not from the catalog
}

// ---- shared building blocks -----------------------------------------------

const FX_SESSIONS: SessionBand[] = [
  { label: "Asia 05:30–12:30 · thin", flex: 2, tone: "quiet" },
  { label: "London 12:30–15:30 · active", flex: 1.4, tone: "active" },
  { label: "London–NY 17:30–21:30 · PRIME", flex: 2, tone: "prime" },
  { label: "Late NY 21:30–02:30 · fading", flex: 1.4, tone: "fading" },
];

const CRYPTO_SESSIONS: SessionBand[] = [
  { label: "Asia 05:30–12:30 · steady", flex: 1.7, tone: "active" },
  { label: "London 12:30–17:30 · active", flex: 1.7, tone: "active" },
  { label: "US 17:30–02:30 · PRIME", flex: 2.4, tone: "prime" },
  { label: "Late/weekend · thin, gappy", flex: 1.2, tone: "quiet" },
];

const US_INDEX_SESSIONS: SessionBand[] = [
  { label: "Asia 05:30–12:30 · thin", flex: 1.6, tone: "quiet" },
  { label: "Europe 12:30–19:00 · active", flex: 1.8, tone: "active" },
  { label: "US cash 19:00–22:30 · PRIME", flex: 2.4, tone: "prime" },
  { label: "Late US 22:30–01:30 · fading", flex: 1.4, tone: "fading" },
];

const METAL_PEERS: Peer[] = [
  { name: "Gold", sym: "GC=F" },
  { name: "Silver", sym: "SI=F" },
  { name: "Platinum", sym: "PL=F" },
  { name: "Palladium", sym: "PA=F" },
  { name: "Copper", sym: "HG=F" },
  { name: "Gold miners GDX", sym: "GDX" },
  { name: "Junior miners GDXJ", sym: "GDXJ" },
  { name: "Silver miners SIL", sym: "SIL" },
];

const FX_PEERS: Peer[] = [
  { name: "EUR", sym: "EURUSD=X" },
  { name: "GBP", sym: "GBPUSD=X" },
  { name: "JPY", sym: "JPYUSD=X" },
  { name: "AUD", sym: "AUDUSD=X" },
  { name: "NZD", sym: "NZDUSD=X" },
  { name: "CAD", sym: "CADUSD=X" },
  { name: "CHF", sym: "CHFUSD=X" },
];

const CRYPTO_PEERS: Peer[] = [
  { name: "Bitcoin", sym: "BTC-USD" },
  { name: "Ethereum", sym: "ETH-USD" },
  { name: "Solana", sym: "SOL-USD" },
  { name: "XRP", sym: "XRP-USD" },
  { name: "Coinbase COIN", sym: "COIN" },
  { name: "Gold", sym: "GC=F" },
];

const INDEX_PEERS: Peer[] = [
  { name: "S&P 500", sym: "^GSPC" },
  { name: "Nasdaq 100", sym: "^NDX" },
  { name: "Dow 30", sym: "^DJI" },
  { name: "Russell 2000", sym: "^RUT" },
  { name: "Tech XLK", sym: "XLK" },
  { name: "Financials XLF", sym: "XLF" },
  { name: "Energy XLE", sym: "XLE" },
];

const ENERGY_PEERS: Peer[] = [
  { name: "WTI crude", sym: "CL=F" },
  { name: "Brent crude", sym: "BZ=F" },
  { name: "Nat gas", sym: "NG=F" },
  { name: "Gasoline RB", sym: "RB=F" },
  { name: "Energy XLE", sym: "XLE" },
  { name: "Oil services OIH", sym: "OIH" },
];

const CORR_CORE: Peer[] = [
  { name: "DXY", sym: "DX-Y.NYB" },
  { name: "US10Y nom.", sym: "^TNX" },
  { name: "Gold", sym: "GC=F" },
  { name: "S&P 500", sym: "^GSPC" },
  { name: "Bitcoin", sym: "BTC-USD" },
  { name: "WTI oil", sym: "CL=F" },
];

const GVZ: VolIndex = { sym: "^GVZ", label: "GVZ · gold vol", bands: [12, 18, 24], range: [8, 30] };
const VIX: VolIndex = { sym: "^VIX", label: "VIX · equity vol", bands: [14, 20, 28], range: [8, 40] };
const VXN: VolIndex = { sym: "^VXN", label: "VXN · Nasdaq vol", bands: [16, 22, 30], range: [10, 45] };
const OVX: VolIndex = { sym: "^OVX", label: "OVX · oil vol", bands: [25, 35, 50], range: [15, 70] };
const EVZ: VolIndex = { sym: "^EVZ", label: "EVZ · euro FX vol", bands: [6, 8, 11], range: [3, 16] };

function base(p: Partial<Instrument> & Pick<Instrument, "id" | "label" | "klass" | "tv" | "yahoo">): Instrument {
  const klass = p.klass;
  const defaults: Omit<Instrument, "id" | "label" | "klass" | "tv" | "yahoo"> = {
    pair: p.id,
    quoteCcy: "USD",
    decimals: klass === "fx" ? 4 : 2,
    roundStep: 1,
    usdBeta: -1,
    yieldBeta: -1,
    vol: null,
    cot: null,
    peers:
      klass === "metal" ? METAL_PEERS
      : klass === "fx" ? FX_PEERS
      : klass === "crypto" ? CRYPTO_PEERS
      : klass === "index" ? INDEX_PEERS
      : klass === "energy" ? ENERGY_PEERS
      : INDEX_PEERS,
    peerLabel:
      klass === "metal" ? "Metals complex"
      : klass === "fx" ? "G10 currencies vs USD"
      : klass === "crypto" ? "Crypto complex"
      : klass === "index" ? "Equity indices & sectors"
      : klass === "energy" ? "Energy complex"
      : "Peer group",
    correlates: CORR_CORE,
    sessions: klass === "crypto" ? CRYPTO_SESSIONS : klass === "index" || klass === "equity" ? US_INDEX_SESSIONS : FX_SESSIONS,
    sampleAnchor: 100,
  };
  return { ...defaults, ...p } as Instrument;
}

// ---- catalog ---------------------------------------------------------------

export const CATALOG: Instrument[] = [
  base({
    id: "XAUUSD", label: "Gold", klass: "metal", tv: "TICKMILL:XAUUSD", yahoo: "GC=F",
    decimals: 1, roundStep: 50, sampleAnchor: 3350, vol: GVZ,
    cot: { code: "088691", dataset: "disaggregated", label: "CFTC managed-money net · gold" },
    peerLabel: "Precious-metals complex",
  }),
  base({
    id: "XAGUSD", label: "Silver", klass: "metal", tv: "TICKMILL:XAGUSD", yahoo: "SI=F",
    decimals: 3, roundStep: 1, sampleAnchor: 38,
    cot: { code: "084691", dataset: "disaggregated", label: "CFTC managed-money net · silver" },
    peerLabel: "Precious-metals complex",
  }),
  base({
    id: "XPTUSD", label: "Platinum", klass: "metal", tv: "OANDA:XPTUSD", yahoo: "PL=F",
    decimals: 1, roundStep: 25, sampleAnchor: 1050,
    cot: { code: "076651", dataset: "disaggregated", label: "CFTC managed-money net · platinum" },
    peerLabel: "Precious-metals complex",
  }),
  base({
    id: "XPDUSD", label: "Palladium", klass: "metal", tv: "OANDA:XPDUSD", yahoo: "PA=F",
    decimals: 1, roundStep: 25, sampleAnchor: 1150, peerLabel: "Precious-metals complex",
  }),
  base({
    id: "XCUUSD", label: "Copper", klass: "metal", tv: "OANDA:XCUUSD", yahoo: "HG=F",
    decimals: 3, roundStep: 0.25, sampleAnchor: 4.6, yieldBeta: 0,
    cot: { code: "085692", dataset: "disaggregated", label: "CFTC managed-money net · copper" },
    peerLabel: "Industrial & precious metals",
  }),
  base({
    id: "EURUSD", label: "Euro", klass: "fx", tv: "OANDA:EURUSD", yahoo: "EURUSD=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 1.09, vol: EVZ,
    cot: { code: "099741", dataset: "financial", label: "CFTC leveraged-funds net · EUR" },
  }),
  base({
    id: "GBPUSD", label: "Sterling", klass: "fx", tv: "OANDA:GBPUSD", yahoo: "GBPUSD=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 1.28,
    cot: { code: "096742", dataset: "financial", label: "CFTC leveraged-funds net · GBP" },
  }),
  base({
    id: "USDJPY", label: "Yen", klass: "fx", tv: "OANDA:USDJPY", yahoo: "USDJPY=X",
    decimals: 3, roundStep: 1, sampleAnchor: 152, quoteCcy: "JPY",
    usdBeta: 1, yieldBeta: 1,
    cot: { code: "097741", dataset: "financial", label: "CFTC leveraged-funds net · JPY (inverted)", invert: true },
  }),
  base({
    id: "AUDUSD", label: "Aussie", klass: "fx", tv: "OANDA:AUDUSD", yahoo: "AUDUSD=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 0.66,
    cot: { code: "232741", dataset: "financial", label: "CFTC leveraged-funds net · AUD" },
  }),
  base({
    id: "USDCAD", label: "Loonie", klass: "fx", tv: "OANDA:USDCAD", yahoo: "USDCAD=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 1.36, quoteCcy: "CAD", usdBeta: 1, yieldBeta: 1,
  }),
  base({
    id: "USDCHF", label: "Swissy", klass: "fx", tv: "OANDA:USDCHF", yahoo: "USDCHF=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 0.88, quoteCcy: "CHF", usdBeta: 1, yieldBeta: 1,
  }),
  base({
    id: "NZDUSD", label: "Kiwi", klass: "fx", tv: "OANDA:NZDUSD", yahoo: "NZDUSD=X",
    decimals: 4, roundStep: 0.01, sampleAnchor: 0.60,
  }),
  base({
    id: "BTCUSD", label: "Bitcoin", klass: "crypto", tv: "BITSTAMP:BTCUSD", yahoo: "BTC-USD",
    decimals: 0, roundStep: 1000, sampleAnchor: 92000, yieldBeta: -1,
    cot: { code: "133741", dataset: "financial", label: "CFTC leveraged-funds net · BTC" },
  }),
  base({
    id: "ETHUSD", label: "Ethereum", klass: "crypto", tv: "BITSTAMP:ETHUSD", yahoo: "ETH-USD",
    decimals: 1, roundStep: 100, sampleAnchor: 3100,
  }),
  base({
    id: "SOLUSD", label: "Solana", klass: "crypto", tv: "COINBASE:SOLUSD", yahoo: "SOL-USD",
    decimals: 2, roundStep: 10, sampleAnchor: 175,
  }),
  base({
    id: "USOIL", label: "WTI crude", klass: "energy", tv: "TVC:USOIL", yahoo: "CL=F",
    decimals: 2, roundStep: 5, sampleAnchor: 72, vol: OVX, yieldBeta: 0,
    cot: { code: "067651", dataset: "disaggregated", label: "CFTC managed-money net · WTI" },
  }),
  base({
    id: "UKOIL", label: "Brent crude", klass: "energy", tv: "TVC:UKOIL", yahoo: "BZ=F",
    decimals: 2, roundStep: 5, sampleAnchor: 76, vol: OVX, yieldBeta: 0,
  }),
  base({
    id: "NATGAS", label: "Natural gas", klass: "energy", tv: "TVC:NATURALGAS", yahoo: "NG=F",
    decimals: 3, roundStep: 0.5, sampleAnchor: 3.1, usdBeta: 0, yieldBeta: 0,
  }),
  base({
    id: "NAS100", label: "Nasdaq 100", klass: "index", tv: "OANDA:NAS100USD", yahoo: "NQ=F",
    decimals: 0, roundStep: 250, sampleAnchor: 20500, vol: VXN, usdBeta: 0, yieldBeta: -1,
  }),
  base({
    id: "SPX500", label: "S&P 500", klass: "index", tv: "OANDA:SPX500USD", yahoo: "ES=F",
    decimals: 0, roundStep: 50, sampleAnchor: 5800, vol: VIX, usdBeta: 0, yieldBeta: -1,
  }),
  base({
    id: "US30", label: "Dow 30", klass: "index", tv: "OANDA:US30USD", yahoo: "YM=F",
    decimals: 0, roundStep: 500, sampleAnchor: 43000, vol: VIX, usdBeta: 0, yieldBeta: -1,
  }),
  base({
    id: "GER40", label: "DAX 40", klass: "index", tv: "OANDA:DE30EUR", yahoo: "^GDAXI",
    decimals: 0, roundStep: 250, sampleAnchor: 19500, quoteCcy: "EUR", usdBeta: 0, yieldBeta: -1,
  }),
];

// Extra spellings people type or that TradingView uses.
const ALIASES: Record<string, string> = {
  GOLD: "XAUUSD", XAU: "XAUUSD", GC: "XAUUSD", GCUSD: "XAUUSD", XAUUSDT: "XAUUSD",
  SILVER: "XAGUSD", XAG: "XAGUSD", SI: "XAGUSD",
  PLATINUM: "XPTUSD", XPT: "XPTUSD", PALLADIUM: "XPDUSD", XPD: "XPDUSD",
  COPPER: "XCUUSD", HG: "XCUUSD", XCU: "XCUUSD",
  EUR: "EURUSD", GBP: "GBPUSD", CABLE: "GBPUSD", JPY: "USDJPY", AUD: "AUDUSD",
  CAD: "USDCAD", CHF: "USDCHF", NZD: "NZDUSD",
  BTC: "BTCUSD", BTCUSDT: "BTCUSD", XBTUSD: "BTCUSD", ETH: "ETHUSD", ETHUSDT: "ETHUSD",
  SOL: "SOLUSD", SOLUSDT: "SOLUSD",
  WTI: "USOIL", CL: "USOIL", USOUSD: "USOIL", BRENT: "UKOIL", UKOUSD: "UKOIL",
  NATURALGAS: "NATGAS", NG: "NATGAS",
  NAS100USD: "NAS100", US100: "NAS100", USTEC: "NAS100", NDX: "NAS100", NQ: "NAS100",
  SPX500USD: "SPX500", SPX: "SPX500", US500: "SPX500", ES: "SPX500", SPY: "SPX500",
  US30USD: "US30", DJI: "US30", YM: "US30",
  DE30EUR: "GER40", DAX: "GER40", DE40: "GER40", GER30: "GER40",
};

const CCY = new Set(["USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF", "SEK", "NOK", "SGD", "HKD", "MXN", "ZAR", "TRY", "CNH", "INR", "PLN", "DKK"]);
const CRYPTO_BASES = new Set(["BTC", "XBT", "ETH", "SOL", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "MATIC", "LTC", "BCH", "BNB", "TRX", "TON", "SUI", "ARB", "OP"]);

export const DEFAULT_INSTRUMENT_ID = "XAUUSD";

function byId(id: string): Instrument | undefined {
  return CATALOG.find((i) => i.id === id);
}

function cleanTicker(raw: string): { exchange: string; sym: string } {
  const s = raw.trim().toUpperCase().replace(/\s+/g, "");
  const parts = s.split(":");
  const sym = (parts.length > 1 ? parts[parts.length - 1] : s).replace(/[^A-Z0-9._=^-]/g, "");
  const exchange = parts.length > 1 ? parts[0] : "";
  return { exchange, sym };
}

// Build a definition for a pair that isn't in the catalog, guessing the Yahoo
// symbol from the ticker shape. Anything we can't classify is treated as a
// listed equity ticker, which is what TradingView symbols like NASDAQ:AAPL are.
function synthesize(input: string): Instrument {
  const { exchange, sym } = cleanTicker(input);
  const tv = input.includes(":") ? input.trim().toUpperCase() : sym;

  // FX / metal pair: 6 letters, both halves known currency (or metal) codes.
  const metalMap: Record<string, string> = { XAU: "GC=F", XAG: "SI=F", XPT: "PL=F", XPD: "PA=F", XCU: "HG=F" };
  const six = sym.replace(/USDT$/, "USD");
  if (/^[A-Z]{6}$/.test(six)) {
    const b = six.slice(0, 3);
    const q = six.slice(3);
    if (metalMap[b] && q === "USD") {
      return base({ id: six, label: b, klass: "metal", tv, yahoo: metalMap[b], decimals: 2, roundStep: 1, sampleAnchor: 100 });
    }
    if (CCY.has(b) && CCY.has(q)) {
      return base({
        id: six, label: `${b}/${q}`, pair: six, klass: "fx", tv, yahoo: `${b}${q}=X`,
        quoteCcy: q, decimals: q === "JPY" ? 3 : 4, roundStep: q === "JPY" ? 1 : 0.01,
        sampleAnchor: q === "JPY" ? 150 : 1.1,
        usdBeta: b === "USD" ? 1 : -1, yieldBeta: b === "USD" ? 1 : -1,
      });
    }
    if (CRYPTO_BASES.has(b) && (q === "USD" || q === "USDC")) {
      return base({ id: six, label: b, klass: "crypto", tv, yahoo: `${b === "XBT" ? "BTC" : b}-USD`, decimals: 2, roundStep: 10, sampleAnchor: 1000 });
    }
  }
  if (CRYPTO_BASES.has(sym)) {
    return base({ id: sym + "USD", label: sym, klass: "crypto", tv, yahoo: `${sym}-USD`, decimals: 2, roundStep: 10, sampleAnchor: 1000 });
  }
  // Fall back to an equity/ETF ticker — Yahoo uses the plain symbol.
  return base({
    id: sym, label: sym, pair: sym, klass: "equity", tv: exchange ? tv : sym, yahoo: sym,
    decimals: 2, roundStep: 5, sampleAnchor: 100, usdBeta: 0, yieldBeta: -1,
    peerLabel: "Peer group & benchmarks",
  });
}

/**
 * Resolve a user selection to an instrument definition.
 * Accepts a catalog id ("XAUUSD"), an alias ("GOLD", "US100"), a TradingView
 * symbol ("OANDA:EURUSD", "NASDAQ:AAPL") or a bare ticker ("AAPL").
 */
export function resolveInstrument(input?: string | null): Instrument {
  if (!input || !input.trim()) return byId(DEFAULT_INSTRUMENT_ID)!;
  const raw = input.trim().toUpperCase();

  const direct = byId(raw);
  if (direct) return direct;

  const tvMatch = CATALOG.find((i) => i.tv.toUpperCase() === raw);
  if (tvMatch) return tvMatch;

  const { sym } = cleanTicker(raw);
  const viaAlias = ALIASES[sym] || ALIASES[raw];
  if (viaAlias) {
    const inst = byId(viaAlias);
    // Keep the exchange the user asked for on the TradingView side.
    if (inst) return raw.includes(":") ? { ...inst, tv: raw } : inst;
  }
  const bySym = byId(sym);
  if (bySym) return raw.includes(":") ? { ...bySym, tv: raw } : bySym;

  return { ...synthesize(raw), custom: true };
}

// Symbols that track the same thing — a pair should never be ranked or
// correlated against its own proxy (NQ=F vs ^NDX, GC=F vs GLD …).
const EQUIVALENTS: string[][] = [
  ["NQ=F", "^NDX", "QQQ"],
  ["ES=F", "^GSPC", "SPY"],
  ["YM=F", "^DJI", "DIA"],
  ["GC=F", "GLD", "XAUUSD=X"],
  ["SI=F", "SLV"],
  ["CL=F", "USO"],
  ["BTC-USD", "BITO"],
  ["^GDAXI", "DAX"],
];

function sameThing(a: string, b: string): boolean {
  if (a === b) return true;
  return EQUIVALENTS.some((g) => g.includes(a) && g.includes(b));
}

/** Peers minus the instrument itself (never rank a pair against itself). */
export function peersFor(inst: Instrument): Peer[] {
  return inst.peers.filter((p) => !sameThing(p.sym, inst.yahoo));
}

/** Correlation basket minus the instrument itself. */
export function correlatesFor(inst: Instrument): Peer[] {
  const extra: Peer[] =
    inst.klass === "metal" ? [{ name: "Silver", sym: "SI=F" }]
    : inst.klass === "crypto" ? [{ name: "Nasdaq 100", sym: "^NDX" }]
    : inst.klass === "index" ? [{ name: "VIX", sym: "^VIX" }]
    : [];
  const all = [...inst.correlates, ...extra];
  const seen = new Set<string>();
  return all.filter((c) => !sameThing(c.sym, inst.yahoo) && !seen.has(c.sym) && seen.add(c.sym));
}

/** Options rendered in the pair picker. */
export function catalogOptions(): { id: string; label: string; klass: AssetClass }[] {
  return CATALOG.map((i) => ({ id: i.id, label: `${i.pair} · ${i.label}`, klass: i.klass }));
}
