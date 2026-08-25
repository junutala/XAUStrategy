"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { catalogOptions, type AssetClass } from "@/lib/instruments";

const GROUPS: { klass: AssetClass; label: string }[] = [
  { klass: "metal", label: "Metals" },
  { klass: "fx", label: "FX majors" },
  { klass: "index", label: "Indices" },
  { klass: "energy", label: "Energy" },
  { klass: "crypto", label: "Crypto" },
];

/**
 * Pair selector. Changing it re-renders the whole dashboard for that
 * instrument (`/?pair=…`), so every number — regime, signals, levels, setups,
 * RRG, correlations, COT, the TradingView chart — follows the selection.
 * The free-text box accepts any TradingView symbol (e.g. "OANDA:EURJPY",
 * "NASDAQ:AAPL"); we map it to a data symbol by convention.
 */
export default function PairPicker({ current, custom }: { current: string; custom: boolean }) {
  const router = useRouter();
  const [typed, setTyped] = useState(custom ? current : "");
  const [busy, setBusy] = useState(false);
  const options = catalogOptions();

  const go = (pair: string) => {
    const p = pair.trim();
    if (!p) return;
    setBusy(true);
    router.push(`/?pair=${encodeURIComponent(p)}`);
    router.refresh();
    setTimeout(() => setBusy(false), 1200);
  };

  return (
    <div className="pairpick">
      <label className="pp-lab" htmlFor="pair-select">
        Pair
      </label>
      <select
        id="pair-select"
        className="pp-select"
        value={custom ? "" : current}
        onChange={(e) => go(e.target.value)}
      >
        {custom && <option value="">{current} (custom)</option>}
        {GROUPS.map((g) => {
          const items = options.filter((o) => o.klass === g.klass);
          if (!items.length) return null;
          return (
            <optgroup key={g.klass} label={g.label}>
              {items.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </optgroup>
          );
        })}
      </select>
      <form
        className="pp-form"
        onSubmit={(e) => {
          e.preventDefault();
          go(typed);
        }}
      >
        <input
          className="pp-input"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          placeholder="or a TradingView symbol…"
          aria-label="TradingView symbol"
          spellCheck={false}
        />
        <button className="pp-go" type="submit" disabled={busy}>
          {busy ? "…" : "Load"}
        </button>
      </form>
    </div>
  );
}
