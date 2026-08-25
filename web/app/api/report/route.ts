import { NextResponse } from "next/server";
import { buildReport } from "@/lib/report";

export const dynamic = "force-dynamic";

// JSON endpoint for the full report — handy for debugging or a future
// mobile/native client. GET /api/report?pair=EURUSD
export async function GET(req: Request) {
  const pair = new URL(req.url).searchParams.get("pair");
  const data = await buildReport(pair);
  return NextResponse.json(data);
}
