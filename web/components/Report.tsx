"use client";
import { useState } from "react";
import type { Report, Bias } from "@/lib/report";
import {
  PriceChart,
  GvzChart,
  CotChart,
  RealYieldChart,
  DeskChart,
  RRGChart,
  CorrChart,
  SeasonalityChart,
  ScalpChart,
} from "./charts";

const n0 = (v: number) => Math.round(v).toLocaleString();
const n1 = (v: number) => v.toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const sign = (v: number, d = 2) => (v >= 0 ? "+" : "") + v.toFixed(d);
const cls = (v: number) => (v > 0 ? "up" : v < 0 ? "down" : "neu");
const pill = (b: Bias) => <span className={`pill ${b.toLowerCase()}`}>{b}</span>;

function ThemeToggle() {
  const [, force] = useState(0);
  const toggle = () => {
    const root = document.documentElement;
    const cur = root.getAttribute("data-theme");
    const dark = cur ? cur === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", dark ? "light" : "dark");
    force((x) => x + 1);
  };
  return (
    <button className="toggle" type="button" onClick={toggle}>
      ◐ Theme
    </button>
  );
}

export default function ReportView({ data }: { data: Report }) {
  const d = data;
  return (
    <div className="wrap">
      <header className="mast">
        <div>
          <h1>
            XAU<span>·</span>Desk
          </h1>
          <div className="sub">5-Day Gold Report — XAUUSD</div>
        </div>
        <div className="right">
          <ThemeToggle />
          <div className="dates">{d.meta.dateRange}</div>
          <div>generated {d.meta.generated}</div>
        </div>
      </header>

      <div className={`statusbar ${d.meta.live ? "live" : "sample"}`}>
        <span className="dot" />
        <b>{d.meta.live ? "LIVE" : "SAMPLE DATA"}</b>
        <span>
          {d.meta.live ? "Sources: " + d.meta.sources.join(" · ") : "Live sources unavailable — showing synthetic placeholder data."}
        </span>
      </div>

      {/* ===== 01 REGIME ===== */}
      <section className="card">
        <div className="sec-head">
          <span className="sec-num">01</span>
          <h2>Macro Regime</h2>
          <span className="hint">what&apos;s driving gold — lean long, short, or stand aside?</span>
        </div>

        <div className="kpis">
          <div className="kpi">
            <div className="lab">XAUUSD spot</div>
            <div className="val">{n0(d.kpi.xau)}</div>
            <div className={`sub ${cls(d.kpi.xauChgPct)}`}>{sign(d.kpi.xauChgPct)}% today</div>
          </div>
          <div className="kpi">
            <div className="lab">GVZ · gold vol</div>
            <div className="val neu">{n1(d.kpi.gvz)}</div>
            <div className="sub">bands 12 / 18 / 24</div>
          </div>
          <div className="kpi">
            <div className="lab">DXY · dollar</div>
            <div className={`val ${cls(-d.kpi.dxyChgPct)}`}>{n1(d.kpi.dxy)}</div>
            <div className={`sub ${cls(-d.kpi.dxyChgPct)}`}>{sign(d.kpi.dxyChgPct)}% · {d.kpi.dxyChgPct <= 0 ? "soft ↓" : "firm ↑"}</div>
          </div>
          <div className="kpi">
            <div className="lab">US 10Y real yield</div>
            <div className={`val ${cls(-d.kpi.realYieldChgBp)}`}>{d.kpi.realYield.toFixed(2)}%</div>
            <div className={`sub ${cls(-d.kpi.realYieldChgBp)}`}>{sign(d.kpi.realYieldChgBp, 0)}bp · {d.kpi.realYieldChgBp <= 0 ? "easing ↓" : "rising ↑"}</div>
          </div>
        </div>

        <div className="regime">
          <div className="badge">{d.regime.badge}</div>
          <div className="txt">{d.regime.text}</div>
        </div>

        <div className="chart-title">
          XAUUSD <span className="m">· last ~40 sessions (last 5 shaded)</span>
        </div>
        <PriceChart data={d.price.values} />

        <div className="grid2" style={{ marginTop: 18 }}>
          <div>
            <div className="chart-title">
              GVZ <span className="m">· gold vol regime bands 12 / 18 / 24</span>
            </div>
            <GvzChart data={d.gvz.values} />
          </div>
          <div>
            <div className="chart-title">
              CFTC managed-money net <span className="m">· weekly Δ</span> <span className="tag">New for gold</span>
            </div>
            <CotChart data={d.cot} />
            <div className="cap">Speculative positioning — the gold analog to FII futures bars. Extremes flag crowding / contrarian risk.</div>
          </div>
        </div>
      </section>

      {/* ===== 02 SCALPING ===== */}
      <section className="card">
        <div className="sec-head">
          <span className="sec-num">02</span>
          <h2>Intraday Scalping Cockpit</h2>
          <span className="tag">Built for scalping</span>
          <span className="hint">top-down {d.scalp.biasTF} → {d.scalp.setupTF} → {d.scalp.triggerTF}</span>
        </div>

        <div className="playbook">
          <span className="lab">Playbook · {d.scalp.playbook}</span>
          <span className="txt">{d.scalp.playbookText}</span>
        </div>

        <div className="tfstack">
          <div className={`tfcard ${d.scalp.biasTone === "Long" ? "up" : "down"}`}>
            <div className="tf">{d.scalp.biasTF} · Bias</div>
            <div className="role">context / filter</div>
            <div className={`st ${d.scalp.biasTone === "Long" ? "up" : "down"}`}>{d.scalp.biasState}</div>
            <div className="desc">EMA + VWAP + structure</div>
          </div>
          <div className="tfcard wait">
            <div className="tf">{d.scalp.setupTF} · Setup</div>
            <div className="role">zone / arming</div>
            <div className="st neu">{d.scalp.setupState}</div>
            <div className="desc">pullback to VWAP / EMA21</div>
          </div>
          <div className={`tfcard ${d.scalp.triggerTone === "Long" ? "up" : "down"}`}>
            <div className="tf">{d.scalp.triggerTF} · Trigger</div>
            <div className="role">precise entry</div>
            <div className={`st ${d.scalp.triggerTone === "Long" ? "up" : "down"}`}>{d.scalp.triggerState}</div>
            <div className="desc">EMA9 × EMA21 cross</div>
          </div>
        </div>

        <div className="scalpwrap">
          <div>
            <div className="chart-title">
              XAUUSD {d.scalp.triggerTF} <span className="m">· VWAP + EMA9 / EMA21 · session shaded</span>
            </div>
            <ScalpChart price={d.scalp.intraday} vwap={d.scalp.vwap} ema9={d.scalp.ema9} ema21={d.scalp.ema21} />
            <div className="chart-title" style={{ marginTop: 10 }}>
              Best hours to scalp gold <span className="m">· GMT</span>
            </div>
            <div className="sessclock">
              <div style={{ background: "#8a94a0", flex: "2 1 0" }}>Asia · thin</div>
              <div style={{ background: "var(--bull)", flex: "1.4 1 0" }}>London 07–10 · active</div>
              <div style={{ background: "var(--gold-2)", flex: "2 1 0" }}>London–NY 12–16 · PRIME</div>
              <div style={{ background: "var(--neutral)", flex: "1.4 1 0" }}>Late NY · fading</div>
            </div>
            <div className="cap">Concentrate scalps in the London open &amp; London–NY overlap; Asia chop &amp; rollover eat spread.</div>
          </div>
          <div>
            <div className="scalpcard">
              <h4>
                Live scalp · {d.scalp.biasTone} {pill(d.scalp.biasTone)}
              </h4>
              <div className="slrow">
                <div className="k">Entry</div>
                <div className="v">{n1(d.scalp.live.entry)}</div>
                <div className="n">on {d.scalp.triggerTF} trigger</div>
                <div className="k">Stop</div>
                <div className="v">{n1(d.scalp.live.stop)}</div>
                <div className="n">{sign(d.scalp.live.stop - d.scalp.live.entry, 1)}</div>
                <div className="k">Target 1</div>
                <div className="v">{n1(d.scalp.live.t1)}</div>
                <div className="n">{sign(d.scalp.live.t1 - d.scalp.live.entry, 1)}</div>
                <div className="k">Target 2</div>
                <div className="v">{n1(d.scalp.live.t2)}</div>
                <div className="n">{sign(d.scalp.live.t2 - d.scalp.live.entry, 1)}</div>
                <div className="k">Spread</div>
                <div className="v">~${d.scalp.live.spread.toFixed(2)}</div>
                <div className="n">size ≥ 15× spread</div>
              </div>
              <div className="cap" style={{ marginTop: 8 }}>Trail to breakeven at +1R; time-stop 6 bars if T1 not tagged.</div>
            </div>
            <div className="tblcap">Scalper&apos;s rules</div>
            <ul className="checklist">
              <li>Trade only in direction of the {d.scalp.biasTF} bias</li>
              <li>Enter only in London / NY-overlap hours</li>
              <li>No new entries ±2 min around CPI / FOMC / NFP</li>
              <li>Min 1.2 : 1 reward-to-risk, fixed $ stop</li>
              <li>Max 3 losers → stop for the day</li>
            </ul>
          </div>
        </div>
        <div className="cap">Rules-based framework, not advice — starting parameters to backtest (see the TradingView Pine strategy in the repo).</div>
      </section>

      {/* ===== 03 DESK CALL ===== */}
      <section className="card">
        <div className="sec-head">
          <span className="sec-num">03</span>
          <h2>Desk Call — XAUUSD</h2>
          <span className="hint">trend + momentum, volatility, key levels · per timeframe</span>
        </div>

        <div className="grid2">
          <div>
            <div className="chart-title" style={{ color: "var(--bull)" }}>
              XAUUSD <span className="m">· S/R band shaded</span>
            </div>
            <DeskChart data={d.price.values} sr={[d.signals[1]?.support ?? d.price.values[0], d.signals[1]?.resist ?? d.price.values[0]]} />
          </div>
          <div>
            <div className="chart-title">
              Real yield (inv.) vs Gold <span className="m">· inverse driver</span> <span className="tag">New for gold</span>
            </div>
            <RealYieldChart gold={d.realYieldVsGold.gold} realInv={d.realYieldVsGold.realInv} />
            <div className="cap">Real yields are gold&apos;s dominant fundamental — falling real yields (rising line) pull gold up.</div>
          </div>
        </div>

        <div className="tblcap">Signals · trend + momentum, volatility, key levels</div>
        <div className="tbl-wrap">
          <table>
            <thead>
              <tr>
                <th>Timeframe</th>
                <th>Verdict</th>
                <th>Momentum</th>
                <th>ADX</th>
                <th>RSI</th>
                <th>Exp.move</th>
                <th>Support</th>
                <th>Resist</th>
              </tr>
            </thead>
            <tbody>
              {d.signals.map((s) => (
                <tr key={s.tf}>
                  <td>{s.tf}</td>
                  <td>{pill(s.verdict)}</td>
                  <td>{s.momentum}</td>
                  <td>{s.adx}</td>
                  <td>{s.rsi}</td>
                  <td>±{s.expMove}</td>
                  <td>{n0(s.support)}</td>
                  <td>{n0(s.resist)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="tblcap">
          Suggested stance <span style={{ fontWeight: 500, color: "var(--muted)" }}>· spot / CFD directional</span>
        </div>
        <div className="stance">
          {d.stance.map((s) => (
            <div key={s.tf} style={{ display: "contents" }}>
              <div className="k">{s.tf}</div>
              <div className="v">{s.text}</div>
            </div>
          ))}
        </div>
        <div className="cap">Trade only when direction AND momentum agree; otherwise reduce size or wait. Not advice.</div>
      </section>

      {/* ===== 04 ROTATION ===== */}
      <section className="card">
        <div className="sec-head">
          <span className="sec-num">04</span>
          <h2>Metals Complex &amp; Intermarket</h2>
          <span className="tag">Reworked for gold</span>
          <span className="hint">the gold analog to sector rotation</span>
        </div>

        <div className="grid2">
          <div>
            <div className="chart-title">
              Precious-metals RRG <span className="m">· strength vs gold</span>
            </div>
            <RRGChart points={d.rrg} />
            <div className="legend">
              <span>
                <i style={{ background: "var(--bull)" }} />
                Leading
              </span>
              <span>
                <i style={{ background: "var(--blue)" }} />
                Improving
              </span>
              <span>
                <i style={{ background: "var(--neutral)" }} />
                Weakening
              </span>
              <span>
                <i style={{ background: "var(--bear)" }} />
                Lagging
              </span>
            </div>
          </div>
          <div>
            <div className="chart-title">
              XAUUSD 20-day correlation <span className="m">· to key drivers</span> <span className="tag">New for gold</span>
            </div>
            <CorrChart rows={d.corr} />
            <div className="cap">What&apos;s actually moving gold now — silver &amp; real yields dominate; dollar inverse still strong.</div>
          </div>
        </div>

        <div className="tblcap">Metals complex · ranked by relative strength vs gold</div>
        <div className="tbl-wrap">
          <table>
            <thead>
              <tr>
                <th>Rank</th>
                <th>Instrument</th>
                <th>Quadrant</th>
                <th>Direction</th>
                <th>RS-Ratio</th>
                <th>Momentum</th>
              </tr>
            </thead>
            <tbody>
              {d.rrg.map((r) => {
                const dir: Bias = r.quadrant === "Leading" || r.quadrant === "Improving" ? "Long" : r.quadrant === "Lagging" ? "Short" : "Neutral";
                return (
                  <tr key={r.name}>
                    <td>{r.rank}</td>
                    <td>{r.name}</td>
                    <td>{r.quadrant}</td>
                    <td>{pill(dir)}</td>
                    <td>{r.x.toFixed(1)}</td>
                    <td>{r.y.toFixed(2)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="cap">Leading / Improving quadrants favour longs; Lagging / Weakening favour caution.</div>
      </section>

      {/* ===== 05 IDEAS ===== */}
      <section className="card">
        <div className="sec-head">
          <span className="sec-num">05</span>
          <h2>Setups, Levels &amp; Event Risk</h2>
          <span className="hint">actionable this week + honest scorecard</span>
        </div>

        <div className="grid2" style={{ alignItems: "start" }}>
          <div>
            <div className="tblcap first">Trade setups · entry / stop / targets</div>
            <div className="tbl-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Setup</th>
                    <th>Bias</th>
                    <th>Entry</th>
                    <th>Stop</th>
                    <th>T1</th>
                    <th>T2</th>
                    <th>R:R</th>
                  </tr>
                </thead>
                <tbody>
                  {d.setups.map((s) => (
                    <tr key={s.name}>
                      <td>{s.name}</td>
                      <td>{pill(s.bias)}</td>
                      <td>{n0(s.entry)}</td>
                      <td>{n0(s.stop)}</td>
                      <td>{n0(s.t1)}</td>
                      <td>{n0(s.t2)}</td>
                      <td>{s.rr.toFixed(1)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="tblcap">
              Key levels <span className="tag">New for gold</span>
            </div>
            <div className="tbl-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Level</th>
                    <th>Type</th>
                    <th>Price</th>
                  </tr>
                </thead>
                <tbody>
                  {d.levels.map((l) => (
                    <tr key={l.name}>
                      <td>{l.name}</td>
                      <td>{l.type}</td>
                      <td>{n0(l.price)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="tblcap">Reversal watch</div>
            <div className="tbl-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Signal</th>
                    <th>What</th>
                    <th>RSI</th>
                    <th>Score</th>
                  </tr>
                </thead>
                <tbody>
                  {d.reversal.map((r) => (
                    <tr key={r.signal}>
                      <td>{r.signal}</td>
                      <td>{r.what}</td>
                      <td>{r.rsi}</td>
                      <td>{r.score}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div>
            <div className="tblcap first">
              Event risk this week <span className="tag">New for gold</span>
            </div>
            <div className="tbl-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Event</th>
                    <th>Impact</th>
                    <th>Gold watch</th>
                  </tr>
                </thead>
                <tbody>
                  {d.events.length === 0 && (
                    <tr>
                      <td colSpan={4} style={{ textAlign: "center", color: "var(--faint)" }}>
                        No major scheduled US events in the next 10 days.
                      </td>
                    </tr>
                  )}
                  {d.events.map((e, i) => (
                    <tr key={i}>
                      <td>{e.date.slice(5)}</td>
                      <td>{e.event}</td>
                      <td className={`imp ${e.impact.toLowerCase()}`}>{e.impact}</td>
                      <td>{e.watch}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="cap">Missing from equity templates — but event risk is decisive on a 5-day gold horizon.</div>

            <div className="tblcap">
              Seasonality · avg monthly return <span className="tag">New for gold</span>
            </div>
            <SeasonalityChart data={d.seasonality} month={d.seasonalityMonth} />
            <div className="cap">Current month highlighted; Aug–Sep &amp; Dec–Jan are gold&apos;s historically strong stretches.</div>

            <div className="tblcap">Track record · backtested EMA9/21 signal</div>
            <div className="tbl-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Bias</th>
                    <th>Trades</th>
                    <th>Avg 10D</th>
                    <th>Hit T1</th>
                    <th>Stopped</th>
                  </tr>
                </thead>
                <tbody>
                  {d.track.map((t) => (
                    <tr key={t.bias}>
                      <td>{pill(t.bias)}</td>
                      <td>{t.trades}</td>
                      <td className={cls(t.avg)}>{sign(t.avg)}%</td>
                      <td>{t.hit}%</td>
                      <td>{t.stopped}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div className="tblcap">
          Predictions vs actuals · recent calls <span className="tag">illustrative</span>
        </div>
        <div className="tbl-wrap">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Call</th>
                <th>Bias</th>
                <th>Return 1D</th>
                <th>Return 5D</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {d.predictions.map((p, i) => (
                <tr key={i}>
                  <td>{p.date}</td>
                  <td>{p.call}</td>
                  <td>{pill(p.bias)}</td>
                  <td className={p.r1 == null ? "" : cls(p.r1)}>{p.r1 == null ? "—" : sign(p.r1) + "%"}</td>
                  <td className={p.r5 == null ? "" : cls(p.r5)}>{p.r5 == null ? "—" : sign(p.r5) + "%"}</td>
                  <td>{p.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className="foot">
        XAU·Desk — 5-Day Gold Report. {d.meta.live ? "Live free-data build." : "Sample build."} Not investment advice and not a trade trigger.
        <br />
        {d.meta.notes.join(" · ")}
      </div>
    </div>
  );
}
