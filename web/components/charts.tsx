"use client";
import { useEffect, useRef } from "react";

type Draw = (ctx: CanvasRenderingContext2D, w: number, h: number, C: (n: string) => string) => void;

export function Chart({ height, draw }: { height: number; draw: Draw }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const C = (n: string) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
    const render = () => {
      const parent = cv.parentElement;
      const dpr = window.devicePixelRatio || 1;
      const w = (parent?.clientWidth || cv.clientWidth || 600);
      cv.width = w * dpr;
      cv.height = height * dpr;
      const ctx = cv.getContext("2d");
      if (!ctx) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, height);
      draw(ctx, w, height, C);
    };
    render();
    const ro = new ResizeObserver(render);
    if (cv.parentElement) ro.observe(cv.parentElement);
    const mo = new MutationObserver(render);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    mq.addEventListener("change", render);
    return () => {
      ro.disconnect();
      mo.disconnect();
      mq.removeEventListener("change", render);
    };
  }, [height, draw]);
  return (
    <div className="chart-wrap">
      <canvas ref={ref} height={height} />
    </div>
  );
}

const SANS = "system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif";
function minmax(a: number[]): [number, number] {
  const f = a.filter((x) => isFinite(x));
  return [Math.min(...f), Math.max(...f)];
}

interface LineOpts {
  color: string;
  fill?: string;
  shadeLast?: number;
  bands?: number[];
  srBand?: [number, number];
  range?: [number, number];
  yticks?: number;
  yfmt?: (v: number) => string;
  lw?: number;
}
function lineChart(ctx: CanvasRenderingContext2D, w: number, h: number, C: (n: string) => string, data: number[], opt: LineOpts) {
  const padL = 46, padR = 8, padT = 8, padB = 18;
  const x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
  const [mnR, mxR] = opt.range || minmax(data);
  const mn = mnR, mx = mxR, span = mx - mn || 1;
  const ticks = opt.yticks || 4;
  ctx.font = "11px " + SANS;
  ctx.textAlign = "right";
  ctx.textBaseline = "middle";
  for (let t = 0; t <= ticks; t++) {
    const yv = mn + (span * t) / ticks;
    const yy = y1 - ((yv - mn) / span) * (y1 - y0);
    ctx.strokeStyle = C("--grid");
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x0, yy);
    ctx.lineTo(x1, yy);
    ctx.stroke();
    ctx.fillStyle = C("--faint");
    ctx.fillText(opt.yfmt ? opt.yfmt(yv) : String(Math.round(yv)), x0 - 6, yy);
  }
  if (opt.bands)
    opt.bands.forEach((b) => {
      const yy = y1 - ((b - mn) / span) * (y1 - y0);
      ctx.strokeStyle = C("--hair");
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(x0, yy);
      ctx.lineTo(x1, yy);
      ctx.stroke();
      ctx.setLineDash([]);
    });
  const n = data.length;
  const px = (i: number) => x0 + (i / (n - 1)) * (x1 - x0);
  const py = (v: number) => y1 - ((v - mn) / span) * (y1 - y0);
  if (opt.shadeLast) {
    const xs = px(n - opt.shadeLast);
    ctx.fillStyle = C("--shade");
    ctx.fillRect(xs, y0, x1 - xs, y1 - y0);
  }
  if (opt.srBand) {
    const [s, r] = opt.srBand;
    const ys = py(s), yr = py(r);
    ctx.fillStyle = C("--shade");
    ctx.fillRect(x0, yr, x1 - x0, ys - yr);
    ctx.setLineDash([5, 4]);
    ctx.strokeStyle = C("--bear");
    ctx.beginPath();
    ctx.moveTo(x0, yr);
    ctx.lineTo(x1, yr);
    ctx.stroke();
    ctx.strokeStyle = C("--bull");
    ctx.beginPath();
    ctx.moveTo(x0, ys);
    ctx.lineTo(x1, ys);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (opt.fill) {
    const grd = ctx.createLinearGradient(0, y0, 0, y1);
    grd.addColorStop(0, opt.fill);
    grd.addColorStop(1, "transparent");
    ctx.beginPath();
    ctx.moveTo(px(0), py(data[0]));
    for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(data[i]));
    ctx.lineTo(px(n - 1), y1);
    ctx.lineTo(px(0), y1);
    ctx.closePath();
    ctx.fillStyle = grd;
    ctx.fill();
  }
  ctx.beginPath();
  ctx.moveTo(px(0), py(data[0]));
  for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(data[i]));
  ctx.strokeStyle = opt.color;
  ctx.lineWidth = opt.lw || 2;
  ctx.lineJoin = "round";
  ctx.stroke();
  ctx.fillStyle = opt.color;
  ctx.beginPath();
  ctx.arc(px(n - 1), py(data[n - 1]), 3, 0, 7);
  ctx.fill();
}

export function PriceChart({ data }: { data: number[] }) {
  const [mn, mx] = minmax(data);
  return (
    <Chart
      height={220}
      draw={(ctx, w, h, C) =>
        lineChart(ctx, w, h, C, data, {
          color: C("--gold"),
          fill: C("--gold-soft"),
          shadeLast: 5,
          range: [mn - 8, mx + 8],
          yfmt: (v) => Math.round(v).toLocaleString(),
        })
      }
    />
  );
}

export function GvzChart({ data }: { data: number[] }) {
  return (
    <Chart
      height={200}
      draw={(ctx, w, h, C) =>
        lineChart(ctx, w, h, C, data, { color: C("--neutral"), bands: [12, 18, 24], range: [10, 26] })
      }
    />
  );
}

export function DeskChart({ data, sr }: { data: number[]; sr: [number, number] }) {
  const [mn, mx] = minmax(data);
  return (
    <Chart
      height={210}
      draw={(ctx, w, h, C) =>
        lineChart(ctx, w, h, C, data, {
          color: C("--bull"),
          fill: C("--bull-soft"),
          srBand: sr,
          range: [Math.min(mn, sr[0]) - 14, Math.max(mx, sr[1]) + 14],
          yfmt: (v) => Math.round(v).toLocaleString(),
        })
      }
    />
  );
}

export function CotChart({ data }: { data: number[] }) {
  return (
    <Chart
      height={200}
      draw={(ctx, w, h, C) => {
        const padL = 40, padR = 8, padT = 8, padB = 20, x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
        const mx = Math.max(...data.map(Math.abs)) * 1.1 || 1;
        const zero = y0 + (y1 - y0) / 2;
        ctx.strokeStyle = C("--grid");
        ctx.beginPath();
        ctx.moveTo(x0, zero);
        ctx.lineTo(x1, zero);
        ctx.stroke();
        ctx.fillStyle = C("--faint");
        ctx.font = "11px " + SANS;
        ctx.textAlign = "right";
        ctx.textBaseline = "middle";
        ctx.fillText("0", x0 - 6, zero);
        ctx.fillText("+" + Math.round(mx) + "k", x0 - 6, y0 + 6);
        ctx.fillText("−" + Math.round(mx) + "k", x0 - 6, y1 - 6);
        const bw = ((x1 - x0) / data.length) * 0.62;
        data.forEach((v, i) => {
          const cx = x0 + ((i + 0.5) / data.length) * (x1 - x0);
          const yv = zero - (v / mx) * ((y1 - y0) / 2);
          ctx.fillStyle = v >= 0 ? C("--bull") : C("--bear");
          ctx.fillRect(cx - bw / 2, Math.min(zero, yv), bw, Math.abs(zero - yv));
        });
      }}
    />
  );
}

export function RealYieldChart({ gold, realInv }: { gold: number[]; realInv: number[] }) {
  return (
    <Chart
      height={210}
      draw={(ctx, w, h, C) => {
        const padL = 44, padR = 10, padT = 8, padB = 18, x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
        const N = Math.min(gold.length, realInv.length);
        const g = gold.slice(gold.length - N);
        const r = realInv.slice(realInv.length - N);
        const gm = minmax(g), rm = minmax(r);
        const px = (i: number) => x0 + (i / (N - 1)) * (x1 - x0);
        for (let t = 0; t <= 4; t++) {
          const yy = y1 - (t / 4) * (y1 - y0);
          ctx.strokeStyle = C("--grid");
          ctx.beginPath();
          ctx.moveTo(x0, yy);
          ctx.lineTo(x1, yy);
          ctx.stroke();
        }
        const draw = (arr: number[], mm: [number, number], col: string, lw: number) => {
          const mn = mm[0], sp = mm[1] - mm[0] || 1;
          ctx.beginPath();
          for (let i = 0; i < arr.length; i++) {
            const yy = y1 - ((arr[i] - mn) / sp) * (y1 - y0);
            i ? ctx.lineTo(px(i), yy) : ctx.moveTo(px(i), yy);
          }
          ctx.strokeStyle = col;
          ctx.lineWidth = lw;
          ctx.lineJoin = "round";
          ctx.stroke();
        };
        draw(r, rm, C("--blue"), 1.8);
        draw(g, gm, C("--gold"), 2.2);
        ctx.textAlign = "left";
        ctx.textBaseline = "top";
        ctx.font = "10px " + SANS;
        ctx.fillStyle = C("--gold");
        ctx.fillText("■ Gold", x0 + 4, y0 + 4);
        ctx.fillStyle = C("--blue");
        ctx.fillText("■ Real yield (inverted)", x0 + 52, y0 + 4);
      }}
    />
  );
}

interface RRGP { rank: number; name: string; x: number; y: number; quadrant: string }
export function RRGChart({ points }: { points: RRGP[] }) {
  const qcol = (q: string, C: (n: string) => string) =>
    q === "Leading" ? C("--bull") : q === "Improving" ? C("--blue") : q === "Weakening" ? C("--neutral") : C("--bear");
  return (
    <Chart
      height={300}
      draw={(ctx, w, h, C) => {
        const x0 = 34, x1 = w - 12, y0 = 12, y1 = h - 24;
        const xs = points.map((p) => p.x), ys = points.map((p) => p.y);
        const xmin = Math.min(94, ...xs) - 1, xmax = Math.max(107, ...xs) + 1;
        const ymin = Math.min(-8, ...ys) - 1, ymax = Math.max(9, ...ys) + 1;
        const px = (v: number) => x0 + ((v - xmin) / (xmax - xmin)) * (x1 - x0);
        const py = (v: number) => y1 - ((v - ymin) / (ymax - ymin)) * (y1 - y0);
        const cx = px(100), cy = py(0);
        const tint = (a: number, b: number, c: number, d: number, col: string) => {
          ctx.fillStyle = col;
          ctx.globalAlpha = 0.1;
          ctx.fillRect(a, b, c - a, d - b);
          ctx.globalAlpha = 1;
        };
        tint(cx, y0, x1, cy, C("--bull"));
        tint(x0, y0, cx, cy, C("--blue"));
        tint(x0, cy, cx, y1, C("--bear"));
        tint(cx, cy, x1, y1, C("--neutral"));
        ctx.strokeStyle = C("--hair");
        ctx.beginPath();
        ctx.moveTo(cx, y0);
        ctx.lineTo(cx, y1);
        ctx.moveTo(x0, cy);
        ctx.lineTo(x1, cy);
        ctx.stroke();
        ctx.font = "10px " + SANS;
        ctx.fillStyle = C("--muted");
        ctx.textAlign = "left";
        ctx.textBaseline = "top";
        ctx.fillText("Improving", x0 + 4, y0 + 3);
        ctx.textAlign = "right";
        ctx.fillText("Leading", x1 - 4, y0 + 3);
        ctx.textAlign = "left";
        ctx.textBaseline = "bottom";
        ctx.fillText("Lagging", x0 + 4, y1 - 3);
        ctx.textAlign = "right";
        ctx.fillText("Weakening", x1 - 4, y1 - 3);
        ctx.textAlign = "center";
        ctx.fillStyle = C("--faint");
        ctx.fillText("RS-Ratio  (>100 = outperforming gold)", (x0 + x1) / 2, h - 2);
        ctx.beginPath();
        ctx.arc(cx, cy, 3, 0, 7);
        ctx.fill();
        points.forEach((d) => {
          const X = px(d.x), Y = py(d.y);
          ctx.fillStyle = qcol(d.quadrant, C);
          ctx.beginPath();
          ctx.arc(X, Y, 9, 0, 7);
          ctx.fill();
          ctx.fillStyle = "#fff";
          ctx.font = "bold 10px " + SANS;
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText(String(d.rank), X, Y + 0.5);
        });
      }}
    />
  );
}

export function CorrChart({ rows }: { rows: { k: string; v: number }[] }) {
  return (
    <Chart
      height={300}
      draw={(ctx, w, h, C) => {
        const padL = 110, padR = 36, padT = 6, padB = 6, x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
        const mid = (x0 + x1) / 2, half = (x1 - x0) / 2;
        const rowH = (y1 - y0) / rows.length;
        ctx.strokeStyle = C("--hair");
        ctx.beginPath();
        ctx.moveTo(mid, y0);
        ctx.lineTo(mid, y1);
        ctx.stroke();
        ctx.font = "10px " + SANS;
        ctx.fillStyle = C("--faint");
        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        ctx.fillText("0", mid, y1 - 2);
        ctx.fillText("+1", x1, y1 - 2);
        ctx.fillText("−1", x0, y1 - 2);
        rows.forEach((d, i) => {
          const cy = y0 + rowH * (i + 0.5);
          const bw = d.v * half;
          ctx.fillStyle = d.v >= 0 ? C("--bull") : C("--bear");
          ctx.fillRect(mid, cy - rowH * 0.3, bw, rowH * 0.6);
          ctx.fillStyle = C("--text");
          ctx.font = "11px " + SANS;
          ctx.textAlign = "right";
          ctx.textBaseline = "middle";
          ctx.fillText(d.k, x0 - 8, cy);
          ctx.textAlign = d.v >= 0 ? "left" : "right";
          ctx.fillStyle = C("--muted");
          ctx.fillText((d.v > 0 ? "+" : "") + d.v.toFixed(2), mid + bw + (d.v >= 0 ? 4 : -4), cy);
        });
      }}
    />
  );
}

export function SeasonalityChart({ data, month }: { data: number[]; month: number }) {
  return (
    <Chart
      height={150}
      draw={(ctx, w, h, C) => {
        const padL = 26, padR = 6, padT = 8, padB = 18, x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
        const mx = Math.max(...data.map(Math.abs)) * 1.15 || 1;
        const zero = y0 + (y1 - y0) / 2;
        const mo = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"];
        ctx.strokeStyle = C("--grid");
        ctx.beginPath();
        ctx.moveTo(x0, zero);
        ctx.lineTo(x1, zero);
        ctx.stroke();
        const bw = ((x1 - x0) / 12) * 0.64;
        data.forEach((v, i) => {
          const cx = x0 + ((i + 0.5) / 12) * (x1 - x0);
          const yv = zero - (v / mx) * ((y1 - y0) / 2);
          const cur = i === month;
          ctx.fillStyle = cur ? C("--gold") : v >= 0 ? C("--bull") : C("--bear");
          ctx.globalAlpha = cur ? 1 : 0.85;
          ctx.fillRect(cx - bw / 2, Math.min(zero, yv), bw, Math.abs(zero - yv));
          ctx.globalAlpha = 1;
          ctx.fillStyle = C("--faint");
          ctx.font = "9px " + SANS;
          ctx.textAlign = "center";
          ctx.textBaseline = "top";
          ctx.fillText(mo[i], cx, y1 + 3);
        });
      }}
    />
  );
}

export function ScalpChart({ price, vwap, ema9, ema21 }: { price: number[]; vwap: number[]; ema9: number[]; ema21: number[] }) {
  return (
    <Chart
      height={230}
      draw={(ctx, w, h, C) => {
        const padL = 48, padR = 10, padT = 8, padB = 8, x0 = padL, x1 = w - padR, y0 = padT, y1 = h - padB;
        const M = price.length;
        const all = price.concat(vwap, ema9, ema21);
        const [mn0, mx0] = minmax(all);
        const mn = mn0 - 0.8, mx = mx0 + 0.8, sp = mx - mn || 1;
        const px = (i: number) => x0 + (i / (M - 1)) * (x1 - x0);
        const py = (v: number) => y1 - ((v - mn) / sp) * (y1 - y0);
        const xs = px(Math.floor(M * 0.62));
        ctx.fillStyle = C("--shade");
        ctx.fillRect(xs, y0, x1 - xs, y1 - y0);
        ctx.font = "11px " + SANS;
        ctx.textAlign = "right";
        ctx.textBaseline = "middle";
        for (let t = 0; t <= 4; t++) {
          const yv = mn + (sp * t) / 4, yy = py(yv);
          ctx.strokeStyle = C("--grid");
          ctx.beginPath();
          ctx.moveTo(x0, yy);
          ctx.lineTo(x1, yy);
          ctx.stroke();
          ctx.fillStyle = C("--faint");
          ctx.fillText(yv.toFixed(1), x0 - 6, yy);
        }
        const line = (arr: number[], col: string, lw: number, dash: number[] = []) => {
          ctx.setLineDash(dash);
          ctx.beginPath();
          for (let i = 0; i < arr.length; i++) {
            i ? ctx.lineTo(px(i), py(arr[i])) : ctx.moveTo(px(i), py(arr[i]));
          }
          ctx.strokeStyle = col;
          ctx.lineWidth = lw;
          ctx.lineJoin = "round";
          ctx.stroke();
          ctx.setLineDash([]);
        };
        line(vwap, C("--muted"), 1.4, [5, 4]);
        line(ema21, C("--blue"), 1.4);
        line(ema9, C("--bear"), 1.4);
        line(price, C("--gold"), 2);
        ctx.fillStyle = C("--gold");
        ctx.beginPath();
        ctx.arc(px(M - 1), py(price[M - 1]), 3, 0, 7);
        ctx.fill();
        ctx.textAlign = "left";
        ctx.textBaseline = "top";
        ctx.font = "10px " + SANS;
        ctx.fillStyle = C("--gold");
        ctx.fillText("■ price", x0 + 4, y0 + 3);
        ctx.fillStyle = C("--bear");
        ctx.fillText("■ EMA9", x0 + 46, y0 + 3);
        ctx.fillStyle = C("--blue");
        ctx.fillText("■ EMA21", x0 + 92, y0 + 3);
        ctx.fillStyle = C("--muted");
        ctx.fillText("╌ VWAP", x0 + 146, y0 + 3);
      }}
    />
  );
}
