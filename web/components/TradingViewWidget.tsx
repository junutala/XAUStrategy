"use client";
import { useEffect, useRef } from "react";

// Free, legitimate TradingView embed (Advanced Real-Time Chart widget).
// This is a *display-only* live chart rendered in the visitor's browser — it does
// not, and cannot, feed the app's own calculations (TradingView has no free data
// API; their real-time feed is licensed and can't be redistributed). The bias /
// VWAP / scalp numbers still come from Yahoo Finance in lib/report.ts.
export default function TradingViewWidget({
  symbol = "OANDA:XAUUSD",
  interval = "5",
}: {
  symbol?: string;
  interval?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = ref.current;
    if (!container) return;
    // Clear any prior render (React strict-mode / re-mounts).
    container.innerHTML = "";

    const root = document.documentElement.getAttribute("data-theme");
    const prefersDark =
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches;
    const theme = (root ? root === "dark" : prefersDark) ? "dark" : "light";

    const widget = document.createElement("div");
    widget.className = "tradingview-widget-container__widget";
    widget.style.height = "100%";
    widget.style.width = "100%";
    container.appendChild(widget);

    const script = document.createElement("script");
    script.src =
      "https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js";
    script.type = "text/javascript";
    script.async = true;
    script.innerHTML = JSON.stringify({
      autosize: true,
      symbol,
      interval,
      timezone: "Asia/Kolkata",
      theme,
      style: "1",
      locale: "en",
      hide_side_toolbar: true,
      allow_symbol_change: false,
      studies: ["STD;VWAP", "STD;EMA"],
      support_host: "https://www.tradingview.com",
    });
    container.appendChild(script);
  }, [symbol, interval]);

  return (
    <div
      className="tradingview-widget-container"
      ref={ref}
      style={{ height: 320, width: "100%" }}
    />
  );
}
