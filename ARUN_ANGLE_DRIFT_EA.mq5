//+------------------------------------------------------------------+
//|                                          ARUN_ANGLE_DRIFT_EA.mq5 |
//| Two stage EMA cross, gated by angle drift, exited by momentum     |
//| decay. No fixed take profit, no fixed stop distance, no RSI.      |
//|                                                                  |
//| ANGLE                                                            |
//|   angle = 90 + atan( slope / ATR ) * 180/pi   on the Fast EMA     |
//|   slope is measured over InpAngleLookback bars and divided by ATR |
//|   so the scale means the same thing on any symbol or timeframe:   |
//|     90  = flat, 135 = +1 ATR per bar, 45 = -1 ATR per bar.        |
//|   In practice the Fast EMA lives between about 80 and 100, and    |
//|   bar to bar increments run 0.2 - 0.6 degrees.                    |
//|                                                                  |
//| DRIFT                                                            |
//|   drift  = the bar-to-bar change in that angle                    |
//|   a run  = consecutive bars whose drift keeps the same sign       |
//|                                                                  |
//| ENTRY   all of:                                                   |
//|   - Fast x Mid and Fast x Slow both cross inside                  |
//|     InpMaxBarsBetween bars (unchanged from ARUN_EMA_CROSS)        |
//|   - on the bar the pair completes, the drift run is between       |
//|     InpDriftMinBars and InpDriftMaxBars long and points the same  |
//|     way as the signal. That is the "after the 3rd, within the     |
//|     5th candle" rule: the trend must be established but not yet   |
//|     stale.                                                        |
//|   - optionally the angle is on the correct side of 90             |
//|                                                                  |
//| EXIT    whichever comes first:                                    |
//|   1. Angle gives back more in one bar than it has been gaining    |
//|      per bar on average since entry (AAI). Self-scaling: a steep  |
//|      trade tolerates a bigger wobble than a shallow one. Armed    |
//|      after InpAaiArmBars, floored, and with a multiplier so the   |
//|      sensitivity can be tuned.                                    |
//|   2. Peak profit gives back InpGivebackPct, once peak has         |
//|      exceeded InpGivebackArmAtr x ATR.                            |
//|   3. A catastrophic stop at InpStopAtrMult x ATR, placed with the |
//|      order so it survives gaps and disconnections. It is not the  |
//|      working exit - it bounds the unknown.                        |
//|   4. The opposite signal, if enabled.                             |
//|                                                                  |
//| DIAGNOSTICS                                                      |
//|   At the end of a run it prints where every signal went, a        |
//|   histogram of drift run lengths, which exit fired how often, and |
//|   average MFE / MAE. The run-length histogram is the one to read  |
//|   first: it says whether Min/Max of 3 and 5 leave any trades at   |
//|   all, and what values would.                                     |
//|                                                                  |
//| NOT COMPILED BY ITS AUTHOR - compile in MetaEditor before use.    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN ANGLE DRIFT EA - cross gated by angle drift, exit on momentum decay"

#include <Trade\Trade.mqh>

enum ENUM_LOTS_MODE { LOTS_FIXED = 0, LOTS_RISK_PCT = 1 };

//=== EMA / cross engine (unchanged from ARUN_EMA_CROSS_V1) =========
input int    InpFastLen           = 7;
input int    InpMidLen            = 21;
input int    InpSlowLen           = 50;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;
input int    InpMaxBarsBetween    = 5;      // max bars between the two crosses

//=== Angle ==========================================================
input int    InpAngleLookback     = 5;      // bars the slope is measured over
input int    InpAtrPeriod         = 14;     // ATR that normalises it

//=== Drift gate =====================================================
input int    InpDriftMinBars      = 3;      // run must be at least this long at the cross
input int    InpDriftMaxBars      = 5;      // ... and at most this long. 0 = no upper limit
input bool   InpRequireAngleSide  = true;   // angle must also be past 90 in the trade's direction
input double InpDriftEps          = 0.0;    // increments smaller than this count as no move

//=== Exit 1: average angle increment (AAI) ==========================
input int    InpAaiArmBars        = 3;      // bars in trade before this exit arms
input double InpAaiMult           = 1.0;    // exit when the adverse move exceeds AAI x this
input double InpAaiFloor          = 0.15;   // AAI is never treated as smaller than this

//=== Exit 2: peak profit giveback ===================================
input double InpGivebackPct       = 50.0;   // exit when profit falls to this % of its peak
input double InpGivebackArmAtr    = 0.5;    // ... once peak profit passed this x ATR

//=== Exit 3: catastrophic stop ======================================
input double InpStopAtrMult       = 3.0;    // 0 disables. Not the working exit.

//=== Exit 4 =========================================================
input bool   InpCloseOnOpposite   = true;

//=== Risk / execution ===============================================
input ENUM_LOTS_MODE InpLotsMode  = LOTS_FIXED;
input double InpFixedLots         = 0.01;
input double InpRiskPercent       = 0.5;
input int    InpMaxSpreadPoints   = 0;      // 0 = no filter
input int    InpSlippagePoints    = 20;
input long   InpMagic             = 20260911;

//=== Session filter (server time) ===================================
input bool   InpUseSession        = false;
input int    InpSessionStartHour  = 7;
input int    InpSessionEndHour    = 20;

//=== Misc ===========================================================
input bool   InpShowComment       = true;
input bool   InpVerboseLog        = false;  // off by default: 6 months of logs is unreadable

//=== Per-trade CSV ==================================================
// One row per trade with the features it was taken on, written to the
// terminal's Common\Files folder. This is what lets the entry be tested
// by bucket - by angle, by drift run, by hour - instead of only in
// aggregate. Automatically skipped during optimisation, where parallel
// agents would fight over the file.
input bool   InpWriteCsv          = true;
input string InpCsvName           = "arun_drift_trades.csv";

//--- handles
int hFast = INVALID_HANDLE, hMid = INVALID_HANDLE, hSlow = INVALID_HANDLE, hATR = INVALID_HANDLE;

//--- cross state, in bars since, -1 for no live leg
int bullFMAge = -1, bullFSAge = -1, bearFMAge = -1, bearFSAge = -1;

//--- drift state
int    driftDir = 0;        // +1 rising, -1 falling, 0 flat
int    driftRun = 0;        // bars the current run has lasted
double anglePrev = EMPTY_VALUE;

//--- open trade state
bool     inTrade      = false;
int      tradeDir     = 0;
double   entryPrice   = 0.0;
double   entryAngle   = 0.0;
double   entryAtr     = 0.0;
double   lastAngle    = 0.0;
int      barsInTrade  = 0;
double   peakProfit   = 0.0;   // MFE in price terms
double   worstProfit  = 0.0;   // MAE in price terms
string   closeReason  = "";

datetime lastBarTime = 0;
string   lastNote    = "";

//--- CSV state and the features captured at entry
int      csvHandle    = INVALID_HANDLE;
int      tradeIdx     = 0;
datetime entryTime    = 0;
int      entryRun     = 0;
int      entryHour    = 0;
int      entryDow     = 0;

//--- diagnostics
int cntSignals = 0, cntDriftWrongWay = 0, cntDriftTooShort = 0, cntDriftTooLong = 0;
int cntAngleSide = 0, cntPosOpen = 0, cntFilters = 0, cntEntries = 0;
int cntExitAai = 0, cntExitGiveback = 0, cntExitOpposite = 0, cntExitStop = 0;
int runHistUp[13], runHistDn[13];
double sumMfe = 0.0, sumMae = 0.0, sumBars = 0.0;
int    nClosed = 0;

CTrade trade;

//+------------------------------------------------------------------+
int OnInit()
{
   hFast = iMA(_Symbol, PERIOD_CURRENT, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMid  = iMA(_Symbol, PERIOD_CURRENT, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlow = iMA(_Symbol, PERIOD_CURRENT, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(hFast == INVALID_HANDLE || hMid == INVALID_HANDLE ||
      hSlow == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ARUN DRIFT: indicator handle failed");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   ArrayInitialize(runHistUp, 0);
   ArrayInitialize(runHistDn, 0);
   lastBarTime = 0;

   if(InpWriteCsv && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      csvHandle = FileOpen(InpCsvName,
                           FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
      if(csvHandle == INVALID_HANDLE)
         Print("ARUN DRIFT: could not open ", InpCsvName, " err ", GetLastError());
      else
      {
         // The tester sandboxes agents, so "Common\Files" is not the folder
         // under the terminal you would expect. Print where it actually went.
         PrintFormat("ARUN DRIFT: writing trades to %s\\Files\\%s",
                     TerminalInfoString(TERMINAL_COMMONDATA_PATH), InpCsvName);
         FileWrite(csvHandle,
                   "idx", "entry_time", "dir", "entry_price", "angle", "drift_run",
                   "atr", "hour", "dow", "exit_time", "exit_reason", "bars_held",
                   "mfe", "mae", "approx_points");
      }
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(csvHandle != INVALID_HANDLE)
   {
      FileClose(csvHandle);
      csvHandle = INVALID_HANDLE;
      PrintFormat("ARUN DRIFT: wrote %d trades to Common\\Files\\%s", tradeIdx, InpCsvName);
   }
   PrintReport();
   int hs[] = {hFast, hMid, hSlow, hATR};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
   Comment("");
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0 || t == lastBarTime) return false;
   lastBarTime = t;
   return true;
}

double BufAt(int handle, int shift)
{
   double v[];
   ArraySetAsSeries(v, true);
   if(CopyBuffer(handle, 0, shift, 1, v) < 1) return EMPTY_VALUE;
   return v[0];
}

double AtrAt(int shift)
{
   double a = BufAt(hATR, shift);
   if(a == EMPTY_VALUE || a <= 0.0) return 0.0;
   return a;
}

//--- 90 = flat, 135 = +1 ATR per bar, 45 = -1 ATR per bar
double AngleAt(int shift)
{
   double e0 = BufAt(hFast, shift);
   double e1 = BufAt(hFast, shift + InpAngleLookback);
   double atr = AtrAt(shift);
   if(e0 == EMPTY_VALUE || e1 == EMPTY_VALUE || atr <= 0.0) return EMPTY_VALUE;
   double slope = (e0 - e1) / (double)InpAngleLookback;
   return 90.0 + MathArctan(slope / atr) * 180.0 / M_PI;
}

int MyPosition(ulong &ticket)
{
   ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = tk;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return 0;
}

double NormalizeLots(double lots)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0.0) st = 0.01;
   lots = MathFloor(lots / st) * st;
   if(lots < mn) lots = mn;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, 2);
}

double CalcLots(double stopDist)
{
   if(InpLotsMode == LOTS_FIXED || stopDist <= 0.0) return NormalizeLots(InpFixedLots);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0) return NormalizeLots(InpFixedLots);
   double lossPerLot = (stopDist / ts) * tv;
   if(lossPerLot <= 0.0) return NormalizeLots(InpFixedLots);
   return NormalizeLots(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 / lossPerLot);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints);
}

bool SessionOK()
{
   if(!InpUseSession) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| Cross engine - identical rules to ARUN_EMA_CROSS_V1              |
//+------------------------------------------------------------------+
void UpdateCross(int &signalDir)
{
   signalDir = 0;
   double f[], m[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(m, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hFast, 0, 1, 2, f) < 2) return;
   if(CopyBuffer(hMid,  0, 1, 2, m) < 2) return;
   if(CopyBuffer(hSlow, 0, 1, 2, s) < 2) return;

   int N = MathMax(0, InpMaxBarsBetween);
   if(bullFMAge >= 0) { bullFMAge++; if(bullFMAge > N) bullFMAge = -1; }
   if(bullFSAge >= 0) { bullFSAge++; if(bullFSAge > N) bullFSAge = -1; }
   if(bearFMAge >= 0) { bearFMAge++; if(bearFMAge > N) bearFMAge = -1; }
   if(bearFSAge >= 0) { bearFSAge++; if(bearFSAge > N) bearFSAge = -1; }

   bool fmUp = (f[0] >  m[0] && f[1] <= m[1]);
   bool fmDn = (f[0] <  m[0] && f[1] >= m[1]);
   bool fsUp = (f[0] >  s[0] && f[1] <= s[1]);
   bool fsDn = (f[0] <  s[0] && f[1] >= s[1]);

   if(fmUp) { bullFMAge = 0; bearFMAge = -1; }
   if(fmDn) { bearFMAge = 0; bullFMAge = -1; }
   if(fsUp) { bullFSAge = 0; bearFSAge = -1; }
   if(fsDn) { bearFSAge = 0; bullFSAge = -1; }

   bool buy  = (bullFMAge >= 0 && bullFSAge >= 0 && MathAbs(bullFMAge - bullFSAge) <= N);
   bool sell = (bearFMAge >= 0 && bearFSAge >= 0 && MathAbs(bearFMAge - bearFSAge) <= N);
   if(buy)  { bullFMAge = -1; bullFSAge = -1; signalDir =  1; }
   if(sell) { bearFMAge = -1; bearFSAge = -1; if(signalDir == 0) signalDir = -1; }
}

//+------------------------------------------------------------------+
//| Drift run: consecutive bars whose angle moves the same way       |
//| Completed runs go into the histogram, which is the point of the  |
//| first run - it tells us what Min/Max values are even possible.    |
//+------------------------------------------------------------------+
void UpdateDrift(double angleNow)
{
   if(angleNow == EMPTY_VALUE) return;
   if(anglePrev == EMPTY_VALUE) { anglePrev = angleNow; return; }

   double inc = angleNow - anglePrev;
   anglePrev = angleNow;

   int dir = 0;
   if(inc >  InpDriftEps) dir =  1;
   if(inc < -InpDriftEps) dir = -1;

   if(dir == 0 || dir != driftDir)
   {
      if(driftRun > 0 && driftDir != 0)
      {
         int b = MathMin(driftRun, 12);
         if(driftDir > 0) runHistUp[b]++; else runHistDn[b]++;
      }
      driftDir = dir;
      driftRun = (dir == 0 ? 0 : 1);
      return;
   }
   driftRun++;
}

//+------------------------------------------------------------------+
//| Entry                                                            |
//+------------------------------------------------------------------+
void OpenTrade(int dir, double angleNow)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double px  = (dir > 0) ? ask : bid;
   double atr = AtrAt(1);
   if(atr <= 0.0) return;

   double sl = 0.0;
   double stopDist = atr * InpStopAtrMult;
   if(InpStopAtrMult > 0.0)
   {
      double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(stopDist < minDist) stopDist = minDist;
      sl = NormalizeDouble((dir > 0) ? px - stopDist : px + stopDist, _Digits);
   }

   double lots = CalcLots(stopDist);
   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, 0.0, "ARUN DRIFT BUY")
                       : trade.Sell(lots, _Symbol, 0.0, sl, 0.0, "ARUN DRIFT SELL");
   if(!ok)
   {
      Print("ARUN DRIFT: order failed ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return;
   }

   cntEntries++;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   entryTime   = TimeCurrent();
   entryRun    = driftRun;
   entryHour   = dt.hour;
   entryDow    = dt.day_of_week;
   inTrade     = true;
   tradeDir    = dir;
   entryPrice  = px;
   entryAngle  = angleNow;
   lastAngle   = angleNow;
   entryAtr    = atr;
   barsInTrade = 0;
   peakProfit  = 0.0;
   worstProfit = 0.0;
   closeReason = "";
   lastNote    = StringFormat("%s @ %s  angle %.2f  run %d",
                              (dir > 0 ? "BUY" : "SELL"),
                              DoubleToString(px, _Digits), angleNow, driftRun);
   if(InpVerboseLog) Print("ARUN DRIFT: ", lastNote);
}

void FinaliseTrade(string reason)
{
   if(csvHandle != INVALID_HANDLE)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double exitPx = (tradeDir > 0) ? bid : ask;
      tradeIdx++;
      FileWrite(csvHandle,
                IntegerToString(tradeIdx),
                TimeToString(entryTime, TIME_DATE | TIME_SECONDS),
                IntegerToString(tradeDir),
                DoubleToString(entryPrice, _Digits),
                DoubleToString(entryAngle, 3),
                IntegerToString(entryRun),
                DoubleToString(entryAtr, _Digits),
                IntegerToString(entryHour),
                IntegerToString(entryDow),
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                reason,
                IntegerToString(barsInTrade),
                DoubleToString(peakProfit, _Digits),
                DoubleToString(worstProfit, _Digits),
                DoubleToString(tradeDir * (exitPx - entryPrice), _Digits));
   }

   sumMfe  += peakProfit;
   sumMae  += worstProfit;
   sumBars += barsInTrade;
   nClosed++;
   inTrade     = false;
   tradeDir    = 0;
   barsInTrade = 0;
   peakProfit  = 0.0;
   worstProfit = 0.0;
   lastNote    = "closed: " + reason;
   if(InpVerboseLog) Print("ARUN DRIFT: ", lastNote);
}

void CloseTrade(ulong ticket, string reason)
{
   if(trade.PositionClose(ticket)) FinaliseTrade(reason);
}

//+------------------------------------------------------------------+
//| Trade bookkeeping - runs every tick                              |
//+------------------------------------------------------------------+
void ManageTick()
{
   ulong ticket = 0;
   int posDir = MyPosition(ticket);

   //--- still flagged as in a trade but the position is gone: nothing
   //--- here closed it, so the catastrophic stop did
   if(inTrade && posDir == 0)
   {
      cntExitStop++;
      FinaliseTrade("catastrophic stop");
      return;
   }
   if(!inTrade || posDir == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (tradeDir > 0) ? bid : ask;
   double profit = tradeDir * (px - entryPrice);

   if(profit > peakProfit)  peakProfit  = profit;
   if(profit < worstProfit) worstProfit = profit;

   //--- Exit 2: give back too much of the peak
   if(entryAtr > 0.0 && peakProfit >= entryAtr * InpGivebackArmAtr)
   {
      if(profit <= peakProfit * (1.0 - InpGivebackPct / 100.0))
      {
         cntExitGiveback++;
         CloseTrade(ticket, "peak giveback");
      }
   }
}

//+------------------------------------------------------------------+
//| Bar close work                                                   |
//+------------------------------------------------------------------+
void ManageBar(double angleNow)
{
   ulong ticket = 0;
   if(!inTrade || MyPosition(ticket) == 0 || angleNow == EMPTY_VALUE) return;

   barsInTrade++;

   //--- Exit 1: this bar gave back more angle than the trade has been
   //--- gaining per bar on average since entry
   double aai = (barsInTrade > 0)
              ? tradeDir * (angleNow - entryAngle) / (double)barsInTrade
              : 0.0;
   if(aai < InpAaiFloor) aai = InpAaiFloor;

   double adverse = -tradeDir * (angleNow - lastAngle);
   lastAngle = angleNow;

   if(barsInTrade >= InpAaiArmBars && adverse > aai * InpAaiMult)
   {
      cntExitAai++;
      CloseTrade(ticket, StringFormat("angle drift reversed %.2f > AAI %.2f", adverse, aai));
   }
}

//+------------------------------------------------------------------+
//| End of run report                                                |
//+------------------------------------------------------------------+
void PrintReport()
{
   double pct = (cntSignals > 0 ? 100.0 / cntSignals : 0.0);
   Print("=== ARUN DRIFT: where the signals went =====================");
   PrintFormat("  cross pairs completed      : %d", cntSignals);
   PrintFormat("    drift pointing wrong way : %d  (%.1f%%)", cntDriftWrongWay, cntDriftWrongWay * pct);
   PrintFormat("    drift run too short      : %d  (%.1f%%)", cntDriftTooShort, cntDriftTooShort * pct);
   PrintFormat("    drift run too long       : %d  (%.1f%%)", cntDriftTooLong,  cntDriftTooLong  * pct);
   PrintFormat("    angle on the wrong side  : %d  (%.1f%%)", cntAngleSide,     cntAngleSide     * pct);
   PrintFormat("    position already open    : %d  (%.1f%%)", cntPosOpen,       cntPosOpen       * pct);
   PrintFormat("    spread / session         : %d  (%.1f%%)", cntFilters,       cntFilters       * pct);
   PrintFormat("  ENTRIES TAKEN              : %d  (%.1f%%)", cntEntries,       cntEntries       * pct);

   Print("=== ARUN DRIFT: drift run lengths ==========================");
   Print("  (how many runs of each length occurred - read this before");
   Print("   trusting InpDriftMinBars / InpDriftMaxBars)");
   for(int i = 1; i <= 12; i++)
   {
      if(runHistUp[i] == 0 && runHistDn[i] == 0) continue;
      PrintFormat("    run of %2d bar(s) : rising %5d   falling %5d%s",
                  i, runHistUp[i], runHistDn[i], (i == 12 ? "   (12 or more)" : ""));
   }

   Print("=== ARUN DRIFT: exits ======================================");
   PrintFormat("    angle drift reversal (AAI) : %d", cntExitAai);
   PrintFormat("    peak profit giveback       : %d", cntExitGiveback);
   PrintFormat("    opposite signal            : %d", cntExitOpposite);
   PrintFormat("    catastrophic stop          : %d", cntExitStop);
   if(nClosed > 0)
      PrintFormat("    avg MFE %.2f   avg MAE %.2f   avg bars held %.1f  over %d trades",
                  sumMfe / nClosed, sumMae / nClosed, sumBars / nClosed, nClosed);
   Print("============================================================");
}

void ShowComment()
{
   if(!InpShowComment) return;
   Comment(StringFormat(
      "ARUN ANGLE DRIFT EA\n"
      "angle %.2f   drift %s run %d\n"
      "in trade: %s   bars %d   peak %.2f\n"
      "entries %d   last: %s",
      anglePrev == EMPTY_VALUE ? 0.0 : anglePrev,
      (driftDir > 0 ? "UP" : (driftDir < 0 ? "DOWN" : "flat")), driftRun,
      (inTrade ? (tradeDir > 0 ? "LONG" : "SHORT") : "flat"), barsInTrade, peakProfit,
      cntEntries, lastNote));
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageTick();

   if(!IsNewBar()) { ShowComment(); return; }

   double angleNow = AngleAt(1);
   UpdateDrift(angleNow);
   ManageBar(angleNow);

   int signalDir = 0;
   UpdateCross(signalDir);

   ulong ticket = 0;
   int posDir = MyPosition(ticket);

   if(signalDir != 0 && posDir != 0 && signalDir != posDir && InpCloseOnOpposite)
   {
      cntExitOpposite++;
      CloseTrade(ticket, "opposite signal");
      posDir = 0;
   }

   if(signalDir == 0) { ShowComment(); return; }

   cntSignals++;

   //--- the drift gate, in the order that makes the funnel readable
   if(driftDir != signalDir)                             { cntDriftWrongWay++; ShowComment(); return; }
   if(driftRun < InpDriftMinBars)                        { cntDriftTooShort++; ShowComment(); return; }
   if(InpDriftMaxBars > 0 && driftRun > InpDriftMaxBars) { cntDriftTooLong++;  ShowComment(); return; }
   if(InpRequireAngleSide && angleNow != EMPTY_VALUE &&
      ((signalDir > 0 && angleNow <= 90.0) || (signalDir < 0 && angleNow >= 90.0)))
                                                         { cntAngleSide++;     ShowComment(); return; }
   if(posDir != 0)                                       { cntPosOpen++;       ShowComment(); return; }
   if(!SpreadOK() || !SessionOK())                       { cntFilters++;       ShowComment(); return; }

   OpenTrade(signalDir, angleNow);
   ShowComment();
}
//+------------------------------------------------------------------+
