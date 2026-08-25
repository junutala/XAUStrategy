import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Desk — multi-pair trading report",
  description:
    "Trading desk report for any pair you select: macro regime, intraday scalping cockpit, relative strength, correlations, setups & event risk.",
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
