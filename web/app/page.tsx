import { buildReport } from "@/lib/report";
import ReportView from "@/components/Report";

// Rebuild on each request (cheap: fetches are individually cached via revalidate).
export const dynamic = "force-dynamic";

export default async function Page() {
  const data = await buildReport();
  return <ReportView data={data} />;
}
