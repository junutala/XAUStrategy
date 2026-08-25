import { buildReport } from "@/lib/report";
import ReportView from "@/components/Report";

// Rebuild on each request (cheap: fetches are individually cached via revalidate).
export const dynamic = "force-dynamic";

// The whole dashboard is computed for whatever pair is in ?pair= — a catalog id
// ("EURUSD"), an alias ("GOLD", "US100") or a TradingView symbol
// ("OANDA:EURJPY"). Defaults to XAUUSD.
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ pair?: string | string[] }>;
}) {
  const sp = await searchParams;
  const raw = Array.isArray(sp.pair) ? sp.pair[0] : sp.pair;
  const data = await buildReport(raw);
  return <ReportView data={data} />;
}
