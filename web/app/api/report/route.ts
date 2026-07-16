import { NextResponse } from "next/server";
import { buildReport } from "@/lib/report";

export const dynamic = "force-dynamic";

// JSON endpoint for the full report — handy for debugging or a future
// mobile/native client. GET /api/report
export async function GET() {
  const data = await buildReport();
  return NextResponse.json(data);
}
