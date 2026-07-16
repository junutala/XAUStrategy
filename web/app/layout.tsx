import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "XAU·Desk — 5-Day Gold Report",
  description:
    "XAUUSD trading desk report: macro regime, intraday scalping cockpit, intermarket rotation, setups & event risk.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
