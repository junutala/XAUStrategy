//+------------------------------------------------------------------+
//|                                             ARUN_MTF_TPSL_EA.mq5 |
//| Multi timeframe EMA cross with a fixed money take profit and stop |
//|                                                                  |
//| Nothing here is shared with ARUN_ANGLE_DRIFT_EA. No angles, no    |
//| drift, no AAI, no giveback. A trade is opened and then left alone |
//| until one of the two brackets is hit, so the CSV measures the     |
//| ENTRY and nothing else.                                          |
//|                                                                  |
//| ENTRY   all of:                                                   |
//|   1. On the higher timeframe the Fast EMA crosses the Mid or the  |
//|      Slow EMA (which of the two is selectable).                   |
//|   2. On the chart timeframe the same cross happens in the same    |
//|      direction, no more than InpHtfValidBars higher timeframe     |
//|      bars later.                                                  |
//|   3. The last closed candle is completely on the trade's side of  |
//|      the Slow EMA - above it to buy, below it to sell.            |
//|                                                                  |
//| EXIT   the bracket only:                                          |
//|   take profit at +InpTargetUSD, stop loss at -InpLossUSD, both    |
//|   converted from money to a price distance using the symbol's     |
//|   tick value and the lot size actually traded. At the default     |
//|   0.03 lots that is the +$2 / -$2 that was asked for; change the  |
//|   lot size and the money targets are still honoured because the   |
//|   distance is recomputed, not hard coded.                         |
//|                                                                  |
//| A WORD ON THE SPREAD, because it decides how to read the output.  |
//|   Both brackets are checked against the same side of the book,    |
//|   and entry is on the other side. So in mid price terms the take  |
//|   profit sits one spread further away than the stop. With a       |
//|   symmetric bracket of distance d and spread s, a market with no  |
//|   drift at all hits the stop first with probability (d+s)/2d.     |
//|   At 0.03 lots, $2 is roughly 66 points on gold; a 20 point       |
//|   spread therefore needs a win rate near 65% just to break even.  |
//|   InpTargetUSD and InpLossUSD are inputs so that this can be      |
//|   tested rather than argued about.                                |
//|                                                                  |
//| OUTPUT                                                            |
//|   One CSV row per trade carrying the features it was taken on -   |
//|   which EMA was crossed, how stale the higher timeframe cross     |
//|   was, ATR on both timeframes, how far beyond the Slow EMA the    |
//|   candle closed, the spread at entry, hour and weekday - so the   |
//|   result can be sliced afterwards instead of only totalled.       |
//|                                                                  |
//| NOT COMPILED BY ITS AUTHOR - compile in MetaEditor before use.    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN MTF TPSL EA - higher and lower timeframe EMA cross, fixed money bracket"

#include <Trade\Trade.mqh>

//--- which EMA the Fast line has to cut
enum ENUM_CROSS_TARGET
{
   CROSS_EITHER    = 0,   // Mid or Slow, whichever comes first
   CROSS_MID_ONLY  = 1,   // Fast x Mid only
   CROSS_SLOW_ONLY = 2    // Fast x Slow only
};

//--- how the candle is judged against the Slow EMA
enum ENUM_CANDLE_MODE
{
   CANDLE_BODY = 0,   // open and close both beyond the Slow EMA
   CANDLE_FULL = 1    // the whole candle, wicks included, beyond it
};

//--- where that candle test is applied
enum ENUM_CANDLE_TF
{
   CANDLE_TF_LOWER = 0,   // chart timeframe only
   CANDLE_TF_BOTH  = 1    // chart timeframe and higher timeframe
};

//=== Timeframes =====================================================
input ENUM_TIMEFRAMES InpHigherTF = PERIOD_M5;   // higher timeframe. Chart TF is the lower one.

//=== EMAs ===========================================================
input int    InpFastLen           = 7;
input int    InpMidLen            = 21;
input int    InpSlowLen           = 50;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;

//=== Cross rules ====================================================
input ENUM_CROSS_TARGET InpCrossTarget = CROSS_EITHER;
input int    InpHtfValidBars      = 3;      // higher TF bars the HTF cross stays live
input bool   InpRequireSameLeg    = false;  // LTF must cut the same EMA the HTF cut

//=== Candle must clear the Slow EMA =================================
input bool   InpRequireCandle     = true;
input ENUM_CANDLE_MODE InpCandleMode = CANDLE_BODY;
input ENUM_CANDLE_TF   InpCandleTf   = CANDLE_TF_LOWER;

//=== The bracket, in money ==========================================
input double InpTargetUSD         = 2.0;    // take profit, account currency
input double InpLossUSD           = 2.0;    // stop loss, account currency
input double InpFixedLots         = 0.03;   // the lot size those amounts refer to

//=== Optional safety net ============================================
input int    InpMaxBarsInTrade    = 0;      // 0 = off. Close after this many chart bars.

//=== Execution ======================================================
input int    InpAtrPeriod         = 14;     // recorded in the CSV, not used to trade
input int    InpMaxSpreadPoints   = 0;      // 0 = no filter
input int    InpSlippagePoints    = 20;
input long   InpMagic             = 20260912;

//=== Session filter (server time) ===================================
input bool   InpUseSession        = false;
input int    InpSessionStartHour  = 7;
input int    InpSessionEndHour    = 20;

//=== Misc ===========================================================
input bool   InpShowComment       = true;
input bool   InpVerboseLog        = false;

//=== Per-trade CSV ==================================================
input bool   InpWriteCsv          = true;
input string InpCsvName           = "arun_mtf_trades.csv";

//--- indicator handles, L = chart timeframe, H = higher timeframe
int hFastL = INVALID_HANDLE, hMidL = INVALID_HANDLE, hSlowL = INVALID_HANDLE, hAtrL = INVALID_HANDLE;
int hFastH = INVALID_HANDLE, hMidH = INVALID_HANDLE, hSlowH = INVALID_HANDLE, hAtrH = INVALID_HANDLE;

//--- the live higher timeframe cross
int      htfDir      = 0;
string   htfLeg      = "";
datetime htfCrossBar = 0;

//--- new bar tracking
datetime lastBarL = 0, lastBarH = 0;

//--- open trade state
bool     inTrade    = false;
int      tradeDir   = 0;
ulong    posId      = 0;
double   entryPrice = 0.0, tpPrice = 0.0, slPrice = 0.0;
double   peakProfit = 0.0, worstProfit = 0.0;
int      barsInTrade = 0;

//--- features captured at entry, written out when the trade closes
datetime fEntryTime = 0;
string   fHtfLeg = "", fLtfLeg = "";
int      fHtfAge = 0, fHour = 0, fDow = 0, fSpread = 0;
double   fAtrL = 0.0, fAtrH = 0.0, fSlowDistAtr = 0.0, fLots = 0.0;

//--- diagnostics
int cntHtfCross = 0, cntLtfCross = 0, cntNoHtfDir = 0, cntHtfStale = 0, cntWrongLeg = 0;
int cntNoCandle = 0, cntPosOpen = 0, cntFilters = 0, cntEntries = 0;
int cntTP = 0, cntSL = 0, cntTimeout = 0, cntOther = 0;
double sumMfe = 0.0, sumMae = 0.0, sumBars = 0.0, sumUsd = 0.0;
int    nClosed = 0;

int      csvHandle = INVALID_HANDLE;
int      tradeIdx  = 0;
string   lastNote  = "";

CTrade trade;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastLen >= InpMidLen || InpMidLen >= InpSlowLen)
   {
      Print("ARUN MTF: need Fast < Mid < Slow");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTargetUSD <= 0.0 || InpLossUSD <= 0.0)
   {
      Print("ARUN MTF: target and loss must both be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   ENUM_TIMEFRAMES htf = InpHigherTF;
   if(PeriodSeconds(htf) <= PeriodSeconds(PERIOD_CURRENT))
      Print("ARUN MTF: note - the higher timeframe is not higher than the chart. ",
            "Useful as a control run, but the MTF condition then adds nothing.");

   hFastL = iMA(_Symbol, PERIOD_CURRENT, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMidL  = iMA(_Symbol, PERIOD_CURRENT, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlowL = iMA(_Symbol, PERIOD_CURRENT, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hAtrL  = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   hFastH = iMA(_Symbol, htf, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMidH  = iMA(_Symbol, htf, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlowH = iMA(_Symbol, htf, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hAtrH  = iATR(_Symbol, htf, InpAtrPeriod);

   int hs[] = {hFastL, hMidL, hSlowL, hAtrL, hFastH, hMidH, hSlowH, hAtrH};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] == INVALID_HANDLE)
      {
         Print("ARUN MTF: indicator handle failed");
         return INIT_FAILED;
      }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   lastBarL = 0; lastBarH = 0;

   //--- say out loud what the money bracket actually is in points, so
   //--- the spread arithmetic is on the record before the run, not after
   double lots = NormalizeLots(InpFixedLots);
   double tpD  = MoneyToDistance(InpTargetUSD, lots);
   double slD  = MoneyToDistance(InpLossUSD,   lots);
   long   spr  = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   PrintFormat("ARUN MTF: %s lots -> TP %.1f points (%s), SL %.1f points (%s), spread now %d points",
               DoubleToString(lots, 2),
               (_Point > 0 ? tpD / _Point : 0.0), DoubleToString(tpD, _Digits),
               (_Point > 0 ? slD / _Point : 0.0), DoubleToString(slD, _Digits),
               (int)spr);
   if(tpD > 0.0 && spr > 0)
      PrintFormat("ARUN MTF: a driftless market hits the stop first about %.1f%% of the time at that spread",
                  100.0 * (tpD + spr * _Point) / (tpD + slD));

   if(InpWriteCsv && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      csvHandle = FileOpen(InpCsvName, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
      if(csvHandle == INVALID_HANDLE)
         Print("ARUN MTF: could not open ", InpCsvName, " err ", GetLastError());
      else
      {
         PrintFormat("ARUN MTF: writing trades to %s\\Files\\%s",
                     TerminalInfoString(TERMINAL_COMMONDATA_PATH), InpCsvName);
         FileWrite(csvHandle,
                   "idx", "entry_time", "dir", "lots", "entry_price", "tp_price", "sl_price",
                   "htf_leg", "htf_age", "ltf_leg", "atr_ltf", "atr_htf", "slow_dist_atr",
                   "spread_pts", "hour", "dow",
                   "exit_time", "exit_reason", "bars_held", "mfe", "mae",
                   "points", "profit_usd");
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
      PrintFormat("ARUN MTF: wrote %d trades to Common\\Files\\%s", tradeIdx, InpCsvName);
   }
   PrintReport();
   int hs[] = {hFastL, hMidL, hSlowL, hAtrL, hFastH, hMidH, hSlowH, hAtrH};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
   Comment("");
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double BufAt(int handle, int shift)
{
   double v[];
   ArraySetAsSeries(v, true);
   if(CopyBuffer(handle, 0, shift, 1, v) < 1) return EMPTY_VALUE;
   return v[0];
}

double AtrAt(int handle, int shift)
{
   double a = BufAt(handle, shift);
   if(a == EMPTY_VALUE || a <= 0.0) return 0.0;
   return a;
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

//--- money -> price distance for the lot size actually being traded
double MoneyToDistance(double usd, double lots)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0 || lots <= 0.0) return 0.0;
   double perTick = tv * lots;                 // account currency per tick
   if(perTick <= 0.0) return 0.0;
   return (usd / perTick) * ts;
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

//+------------------------------------------------------------------+
//| Cross detection, shared by both timeframes                       |
//| Looks at the last two CLOSED bars of whichever timeframe the      |
//| handles belong to. Returns +1 / -1 and names the EMA that was cut.|
//+------------------------------------------------------------------+
int DetectCross(int hF, int hM, int hS, string &leg)
{
   leg = "";
   double f[], m[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(m, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hF, 0, 1, 2, f) < 2) return 0;
   if(CopyBuffer(hM, 0, 1, 2, m) < 2) return 0;
   if(CopyBuffer(hS, 0, 1, 2, s) < 2) return 0;

   bool fmUp = (f[0] >  m[0] && f[1] <= m[1]);
   bool fmDn = (f[0] <  m[0] && f[1] >= m[1]);
   bool fsUp = (f[0] >  s[0] && f[1] <= s[1]);
   bool fsDn = (f[0] <  s[0] && f[1] >= s[1]);

   bool wantMid  = (InpCrossTarget != CROSS_SLOW_ONLY);
   bool wantSlow = (InpCrossTarget != CROSS_MID_ONLY);

   //--- Slow is tested first: it is the stronger of the two events
   if(wantSlow && fsUp) { leg = "SLOW"; return  1; }
   if(wantSlow && fsDn) { leg = "SLOW"; return -1; }
   if(wantMid  && fmUp) { leg = "MID";  return  1; }
   if(wantMid  && fmDn) { leg = "MID";  return -1; }
   return 0;
}

//+------------------------------------------------------------------+
//| Is the last closed candle wholly on the trade's side of Slow?    |
//| Also reports how far beyond it the close sits, in ATR, which is   |
//| the feature worth slicing on later.                               |
//+------------------------------------------------------------------+
bool CandleClearsSlow(ENUM_TIMEFRAMES tf, int hSlow, int hAtr, int dir, double &distAtr)
{
   distAtr = 0.0;
   double o = iOpen(_Symbol,  tf, 1);
   double c = iClose(_Symbol, tf, 1);
   double h = iHigh(_Symbol,  tf, 1);
   double l = iLow(_Symbol,   tf, 1);
   double e = BufAt(hSlow, 1);
   if(e == EMPTY_VALUE || o <= 0.0 || c <= 0.0) return false;

   double atr = AtrAt(hAtr, 1);
   if(atr > 0.0) distAtr = dir * (c - e) / atr;

   if(dir > 0)
   {
      if(InpCandleMode == CANDLE_FULL) return (l > e);
      return (o > e && c > e);
   }
   if(InpCandleMode == CANDLE_FULL) return (h < e);
   return (o < e && c < e);
}

//+------------------------------------------------------------------+
//| Entry                                                            |
//+------------------------------------------------------------------+
void OpenTrade(int dir, string ltfLeg, int htfAge, double slowDistAtr)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double px  = (dir > 0) ? ask : bid;
   if(px <= 0.0) return;

   double lots = NormalizeLots(InpFixedLots);
   double tpD  = MoneyToDistance(InpTargetUSD, lots);
   double slD  = MoneyToDistance(InpLossUSD,   lots);
   if(tpD <= 0.0 || slD <= 0.0)
   {
      Print("ARUN MTF: cannot convert money to distance - check tick value");
      return;
   }

   //--- brokers refuse brackets closer than the stops level
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(tpD < minDist) tpD = minDist;
   if(slD < minDist) slD = minDist;

   double tp = NormalizeDouble((dir > 0) ? px + tpD : px - tpD, _Digits);
   double sl = NormalizeDouble((dir > 0) ? px - slD : px + slD, _Digits);

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "ARUN MTF BUY")
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, "ARUN MTF SELL");
   if(!ok)
   {
      Print("ARUN MTF: order failed ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return;
   }

   //--- remember the position id so the close can be read back from
   //--- history, which is the only place the true exit reason lives
   posId = 0;
   ulong dealTk = trade.ResultDeal();
   if(dealTk > 0 && HistoryDealSelect(dealTk))
      posId = (ulong)HistoryDealGetInteger(dealTk, DEAL_POSITION_ID);
   if(posId == 0) posId = trade.ResultOrder();

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   cntEntries++;
   inTrade      = true;
   tradeDir     = dir;
   entryPrice   = px;
   tpPrice      = tp;
   slPrice      = sl;
   peakProfit   = 0.0;
   worstProfit  = 0.0;
   barsInTrade  = 0;
   fEntryTime   = TimeCurrent();
   fHtfLeg      = htfLeg;
   fLtfLeg      = ltfLeg;
   fHtfAge      = htfAge;
   fHour        = dt.hour;
   fDow         = dt.day_of_week;
   fSpread      = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   fAtrL        = AtrAt(hAtrL, 1);
   fAtrH        = AtrAt(hAtrH, 1);
   fSlowDistAtr = slowDistAtr;
   fLots        = lots;

   lastNote = StringFormat("%s @ %s  htf %s(%d)  ltf %s",
                           (dir > 0 ? "BUY" : "SELL"),
                           DoubleToString(px, _Digits), htfLeg, htfAge, ltfLeg);
   if(InpVerboseLog) Print("ARUN MTF: ", lastNote);
}

//+------------------------------------------------------------------+
//| Read the close back out of history and write the row             |
//| The exit reason comes from the closing deal, not from a guess     |
//| about which way the last tick was going.                          |
//+------------------------------------------------------------------+
void FinaliseTrade(string fallbackReason)
{
   string   reason = fallbackReason;
   double   usd    = 0.0;
   double   exitPx = 0.0;
   datetime exitTm = TimeCurrent();

   if(posId > 0 && HistorySelectByPosition(posId))
   {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         usd += HistoryDealGetDouble(d, DEAL_PROFIT)
              + HistoryDealGetDouble(d, DEAL_SWAP)
              + HistoryDealGetDouble(d, DEAL_COMMISSION);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            long rs = HistoryDealGetInteger(d, DEAL_REASON);
            if(rs == DEAL_REASON_TP)      reason = "TP";
            else if(rs == DEAL_REASON_SL) reason = "SL";
            else                          reason = fallbackReason;
            exitPx = HistoryDealGetDouble(d, DEAL_PRICE);
            exitTm = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         }
      }
   }
   if(exitPx <= 0.0)
      exitPx = (tradeDir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(reason == "TP")           cntTP++;
   else if(reason == "SL")      cntSL++;
   else if(reason == "timeout") cntTimeout++;
   else                         cntOther++;

   if(csvHandle != INVALID_HANDLE)
   {
      tradeIdx++;
      FileWrite(csvHandle,
                IntegerToString(tradeIdx),
                TimeToString(fEntryTime, TIME_DATE | TIME_SECONDS),
                IntegerToString(tradeDir),
                DoubleToString(fLots, 2),
                DoubleToString(entryPrice, _Digits),
                DoubleToString(tpPrice, _Digits),
                DoubleToString(slPrice, _Digits),
                fHtfLeg,
                IntegerToString(fHtfAge),
                fLtfLeg,
                DoubleToString(fAtrL, _Digits),
                DoubleToString(fAtrH, _Digits),
                DoubleToString(fSlowDistAtr, 4),
                IntegerToString(fSpread),
                IntegerToString(fHour),
                IntegerToString(fDow),
                TimeToString(exitTm, TIME_DATE | TIME_SECONDS),
                reason,
                IntegerToString(barsInTrade),
                DoubleToString(peakProfit, _Digits),
                DoubleToString(worstProfit, _Digits),
                DoubleToString(tradeDir * (exitPx - entryPrice), _Digits),
                DoubleToString(usd, 2));
   }

   sumMfe  += peakProfit;
   sumMae  += worstProfit;
   sumBars += barsInTrade;
   sumUsd  += usd;
   nClosed++;

   inTrade     = false;
   tradeDir    = 0;
   posId       = 0;
   barsInTrade = 0;
   peakProfit  = 0.0;
   worstProfit = 0.0;
   lastNote    = "closed: " + reason;
   if(InpVerboseLog) Print("ARUN MTF: ", lastNote);
}

//+------------------------------------------------------------------+
//| Every tick: track MFE / MAE and notice the bracket firing        |
//+------------------------------------------------------------------+
void ManageTick()
{
   ulong ticket = 0;
   int posDir = MyPosition(ticket);

   //--- the position is gone and nothing here closed it, so the
   //--- bracket did. History says which side.
   if(inTrade && posDir == 0)
   {
      FinaliseTrade("closed");
      return;
   }
   if(!inTrade || posDir == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (tradeDir > 0) ? bid : ask;
   double profit = tradeDir * (px - entryPrice);
   if(profit > peakProfit)  peakProfit  = profit;
   if(profit < worstProfit) worstProfit = profit;
}

//+------------------------------------------------------------------+
//| On-chart status - the funnel as it fills, so a live run can be   |
//| read without opening the Journal                                 |
//+------------------------------------------------------------------+
void ShowComment()
{
   if(!InpShowComment) return;
   Comment(StringFormat(
      "ARUN MTF TPSL  %s + %s\n"
      "bracket  +%.2f / -%.2f  @ %.2f lots\n"
      "HTF arm  %s %s\n"
      "entries %d   TP %d   SL %d\n"
      "%s",
      EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpHigherTF),
      InpTargetUSD, InpLossUSD, NormalizeLots(InpFixedLots),
      (htfDir > 0 ? "BUY" : (htfDir < 0 ? "SELL" : "-")), htfLeg,
      cntEntries, cntTP, cntSL,
      lastNote));
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageTick();
   ShowComment();

   //--- higher timeframe first: a new HTF bar may arm a cross
   datetime tH = iTime(_Symbol, InpHigherTF, 0);
   if(tH != 0 && tH != lastBarH)
   {
      lastBarH = tH;
      string leg = "";
      int d = DetectCross(hFastH, hMidH, hSlowH, leg);
      if(d != 0)
      {
         cntHtfCross++;
         htfDir      = d;
         htfLeg      = leg;
         htfCrossBar = iTime(_Symbol, InpHigherTF, 1);
      }
   }

   //--- chart timeframe
   datetime tL = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(tL == 0 || tL == lastBarL) return;
   lastBarL = tL;

   if(inTrade)
   {
      barsInTrade++;
      if(InpMaxBarsInTrade > 0 && barsInTrade >= InpMaxBarsInTrade)
      {
         ulong tk = 0;
         if(MyPosition(tk) != 0 && trade.PositionClose(tk))
         {
            FinaliseTrade("timeout");
            return;
         }
      }
   }

   string ltfLeg = "";
   int signalDir = DetectCross(hFastL, hMidL, hSlowL, ltfLeg);
   if(signalDir == 0) return;
   cntLtfCross++;

   //--- 1. the higher timeframe must already agree
   if(htfDir != signalDir)
   {
      cntNoHtfDir++;
      lastNote = "no HTF agreement";
      return;
   }

   //--- 2. ... and its cross must still be fresh
   int htfAge = (htfCrossBar > 0) ? iBarShift(_Symbol, InpHigherTF, htfCrossBar, false) : 9999;
   if(htfAge < 0) htfAge = 9999;
   if(InpHtfValidBars > 0 && htfAge > InpHtfValidBars)
   {
      cntHtfStale++;
      lastNote = StringFormat("HTF cross stale (%d bars)", htfAge);
      return;
   }

   if(InpRequireSameLeg && ltfLeg != htfLeg)
   {
      cntWrongLeg++;
      lastNote = "HTF cut " + htfLeg + ", LTF cut " + ltfLeg;
      return;
   }

   //--- 3. the candle must be clear of the Slow EMA
   double distAtr = 0.0;
   if(InpRequireCandle)
   {
      if(!CandleClearsSlow(PERIOD_CURRENT, hSlowL, hAtrL, signalDir, distAtr))
      {
         cntNoCandle++;
         lastNote = "candle not clear of Slow";
         return;
      }
      if(InpCandleTf == CANDLE_TF_BOTH)
      {
         double dh = 0.0;
         if(!CandleClearsSlow(InpHigherTF, hSlowH, hAtrH, signalDir, dh))
         {
            cntNoCandle++;
            lastNote = "HTF candle not clear of Slow";
            return;
         }
      }
   }
   else
      CandleClearsSlow(PERIOD_CURRENT, hSlowL, hAtrL, signalDir, distAtr);

   ulong tk = 0;
   if(MyPosition(tk) != 0 || inTrade) { cntPosOpen++; return; }
   if(!SpreadOK() || !SessionOK())    { cntFilters++; return; }

   OpenTrade(signalDir, ltfLeg, htfAge, distAtr);

   //--- the HTF cross has been used; it does not arm a second trade
   htfDir = 0;
   htfLeg = "";
   htfCrossBar = 0;
}

//+------------------------------------------------------------------+
//| Where every signal went                                          |
//+------------------------------------------------------------------+
void PrintReport()
{
   Print("================ ARUN MTF TPSL - run summary ================");
   PrintFormat("timeframes            : chart %s  +  higher %s",
               EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpHigherTF));
   PrintFormat("bracket               : +%.2f / -%.2f %s at %.2f lots",
               InpTargetUSD, InpLossUSD, AccountInfoString(ACCOUNT_CURRENCY),
               NormalizeLots(InpFixedLots));
   Print("--- funnel ---");
   PrintFormat("higher TF crosses     : %d", cntHtfCross);
   PrintFormat("chart TF crosses      : %d", cntLtfCross);
   PrintFormat("  rejected, no HTF agreement : %d", cntNoHtfDir);
   PrintFormat("  rejected, HTF cross stale  : %d", cntHtfStale);
   PrintFormat("  rejected, different EMA cut: %d", cntWrongLeg);
   PrintFormat("  rejected, candle not clear : %d", cntNoCandle);
   PrintFormat("  rejected, trade already on : %d", cntPosOpen);
   PrintFormat("  rejected, spread / session : %d", cntFilters);
   PrintFormat("entries taken         : %d", cntEntries);
   Print("--- exits ---");
   PrintFormat("take profit           : %d", cntTP);
   PrintFormat("stop loss             : %d", cntSL);
   PrintFormat("timeout               : %d", cntTimeout);
   PrintFormat("other                 : %d", cntOther);
   if(nClosed > 0)
   {
      PrintFormat("closed                : %d   win rate %.1f%%",
                  nClosed, 100.0 * cntTP / (double)nClosed);
      PrintFormat("net                   : %.2f %s   avg %.3f",
                  sumUsd, AccountInfoString(ACCOUNT_CURRENCY), sumUsd / nClosed);
      PrintFormat("avg MFE / MAE / bars  : %.5f / %.5f / %.1f",
                  sumMfe / nClosed, sumMae / nClosed, sumBars / nClosed);
      //--- the number the win rate has to beat, given the bracket
      double lots = NormalizeLots(InpFixedLots);
      double tpD = MoneyToDistance(InpTargetUSD, lots);
      double slD = MoneyToDistance(InpLossUSD, lots);
      if(tpD > 0.0 && slD > 0.0)
         PrintFormat("breakeven win rate    : %.1f%%  (ignoring spread)",
                     100.0 * slD / (tpD + slD));
   }
   Print("=============================================================");
}
