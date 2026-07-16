// Pure technical-indicator math. No external deps.

export function sma(v: number[], p: number): number[] {
  const out: number[] = [];
  let sum = 0;
  for (let i = 0; i < v.length; i++) {
    sum += v[i];
    if (i >= p) sum -= v[i - p];
    out.push(i >= p - 1 ? sum / p : NaN);
  }
  return out;
}

export function ema(v: number[], p: number): number[] {
  const k = 2 / (p + 1);
  const out: number[] = [];
  let e = v[0];
  for (let i = 0; i < v.length; i++) {
    e = i === 0 ? v[0] : v[i] * k + e * (1 - k);
    out.push(e);
  }
  return out;
}

export function rsi(v: number[], p = 14): number[] {
  const out: number[] = new Array(v.length).fill(NaN);
  if (v.length < p + 1) return out;
  let gain = 0,
    loss = 0;
  for (let i = 1; i <= p; i++) {
    const d = v[i] - v[i - 1];
    if (d >= 0) gain += d;
    else loss -= d;
  }
  gain /= p;
  loss /= p;
  out[p] = loss === 0 ? 100 : 100 - 100 / (1 + gain / loss);
  for (let i = p + 1; i < v.length; i++) {
    const d = v[i] - v[i - 1];
    const g = d >= 0 ? d : 0;
    const l = d < 0 ? -d : 0;
    gain = (gain * (p - 1) + g) / p;
    loss = (loss * (p - 1) + l) / p;
    out[i] = loss === 0 ? 100 : 100 - 100 / (1 + gain / loss);
  }
  return out;
}

export interface OHLC {
  open: number[];
  high: number[];
  low: number[];
  close: number[];
}

export function trueRanges(o: OHLC): number[] {
  const tr: number[] = [];
  for (let i = 0; i < o.close.length; i++) {
    if (i === 0) {
      tr.push(o.high[i] - o.low[i]);
      continue;
    }
    tr.push(
      Math.max(
        o.high[i] - o.low[i],
        Math.abs(o.high[i] - o.close[i - 1]),
        Math.abs(o.low[i] - o.close[i - 1]),
      ),
    );
  }
  return tr;
}

export function atr(o: OHLC, p = 14): number[] {
  const tr = trueRanges(o);
  // Wilder smoothing
  const out: number[] = new Array(tr.length).fill(NaN);
  if (tr.length < p) return out;
  let a = 0;
  for (let i = 0; i < p; i++) a += tr[i];
  a /= p;
  out[p - 1] = a;
  for (let i = p; i < tr.length; i++) {
    a = (a * (p - 1) + tr[i]) / p;
    out[i] = a;
  }
  return out;
}

// Wilder ADX
export function adx(o: OHLC, p = 14): number[] {
  const n = o.close.length;
  const out: number[] = new Array(n).fill(NaN);
  if (n < 2 * p) return out;
  const plusDM: number[] = [0];
  const minusDM: number[] = [0];
  const tr = trueRanges(o);
  for (let i = 1; i < n; i++) {
    const up = o.high[i] - o.high[i - 1];
    const dn = o.low[i - 1] - o.low[i];
    plusDM.push(up > dn && up > 0 ? up : 0);
    minusDM.push(dn > up && dn > 0 ? dn : 0);
  }
  const smooth = (arr: number[]): number[] => {
    const s: number[] = new Array(n).fill(NaN);
    let acc = 0;
    for (let i = 1; i <= p; i++) acc += arr[i];
    s[p] = acc;
    for (let i = p + 1; i < n; i++) {
      acc = acc - acc / p + arr[i];
      s[i] = acc;
    }
    return s;
  };
  const sTR = smooth(tr);
  const sP = smooth(plusDM);
  const sM = smooth(minusDM);
  const dx: number[] = new Array(n).fill(NaN);
  for (let i = p; i < n; i++) {
    if (!sTR[i] || sTR[i] === 0) continue;
    const pdi = (100 * sP[i]) / sTR[i];
    const mdi = (100 * sM[i]) / sTR[i];
    const sum = pdi + mdi;
    dx[i] = sum === 0 ? 0 : (100 * Math.abs(pdi - mdi)) / sum;
  }
  // ADX = Wilder avg of DX
  let start = 2 * p;
  if (start >= n) return out;
  let acc = 0,
    cnt = 0;
  for (let i = p + 1; i <= start; i++) {
    if (!isNaN(dx[i])) {
      acc += dx[i];
      cnt++;
    }
  }
  if (cnt === 0) return out;
  let a = acc / cnt;
  out[start] = a;
  for (let i = start + 1; i < n; i++) {
    if (isNaN(dx[i])) continue;
    a = (a * (p - 1) + dx[i]) / p;
    out[i] = a;
  }
  return out;
}

export function pctChange(v: number[], back = 1): number {
  if (v.length <= back) return 0;
  const a = v[v.length - 1 - back];
  const b = v[v.length - 1];
  return a === 0 ? 0 : ((b - a) / a) * 100;
}

export function last<T>(v: T[]): T {
  return v[v.length - 1];
}

export function lastFinite(v: number[]): number {
  for (let i = v.length - 1; i >= 0; i--) if (isFinite(v[i])) return v[i];
  return NaN;
}

// Pearson correlation of daily returns of two aligned close series
export function correlationOfReturns(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  if (n < 3) return 0;
  const ra: number[] = [];
  const rb: number[] = [];
  for (let i = a.length - n + 1; i < a.length; i++) {
    const j = i - (a.length - b.length);
    if (a[i - 1] && b[j - 1]) {
      ra.push((a[i] - a[i - 1]) / a[i - 1]);
      rb.push((b[j] - b[j - 1]) / b[j - 1]);
    }
  }
  return pearson(ra, rb);
}

export function pearson(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  if (n < 2) return 0;
  let ma = 0,
    mb = 0;
  for (let i = 0; i < n; i++) {
    ma += a[i];
    mb += b[i];
  }
  ma /= n;
  mb /= n;
  let num = 0,
    da = 0,
    db = 0;
  for (let i = 0; i < n; i++) {
    const xa = a[i] - ma;
    const xb = b[i] - mb;
    num += xa * xb;
    da += xa * xa;
    db += xb * xb;
  }
  const den = Math.sqrt(da * db);
  return den === 0 ? 0 : num / den;
}

// Relative-strength ratio & momentum for an RRG (asset vs benchmark),
// normalised around 100 / 0 in the style of a JdK RS-Ratio graph.
export function rsRatioMomentum(
  asset: number[],
  bench: number[],
  win = 20,
): { ratio: number; momentum: number } {
  const n = Math.min(asset.length, bench.length);
  if (n < win + 2) return { ratio: 100, momentum: 0 };
  const rs: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = asset[asset.length - n + i];
    const b = bench[bench.length - n + i];
    rs.push(b === 0 ? 0 : (a / b) * 100);
  }
  const rsSma = sma(rs, win);
  const norm: number[] = [];
  for (let i = 0; i < rs.length; i++) {
    if (isNaN(rsSma[i]) || rsSma[i] === 0) continue;
    norm.push(100 * (rs[i] / rsSma[i]));
  }
  const ratio = norm.length ? norm[norm.length - 1] : 100;
  const mom =
    norm.length > 5
      ? ratio - norm[norm.length - 6]
      : 0;
  return { ratio, momentum: mom * 2 };
}

export function quadrant(
  ratio: number,
  momentum: number,
): "Leading" | "Improving" | "Weakening" | "Lagging" {
  if (ratio >= 100 && momentum >= 0) return "Leading";
  if (ratio < 100 && momentum >= 0) return "Improving";
  if (ratio >= 100 && momentum < 0) return "Weakening";
  return "Lagging";
}
