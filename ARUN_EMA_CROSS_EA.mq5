//+------------------------------------------------------------------+
//|                                            ARUN_EMA_CROSS_EA.mq5 |
//| Expert Advisor built on the ARUN_EMA_CROSS_V1 indicator logic.    |
//|                                                                  |
//| ENTRY                                                            |
//|   Stage 1 : Fast crosses Mid                                     |
//|   Stage 2 : Fast crosses Slow                                    |
//|             Either order, both inside InpMaxBarsBetween candles.  |
//|   Stage 3 : a confirmation candle that opens AND closes on the    |
//|             correct side of the Slow EMA, within                  |
//|             InpConfirmWithinBars candles of the second cross.     |
//|   Stage 4 : optional RSI divergence agreeing with the direction.  |
//|   Entry is at market on the open of the bar after the             |
//|   confirmation candle closes. Nothing is evaluated intrabar.      |
//|                                                                  |
//| EXIT                                                             |
//|   Take profit  : see ENUM_TP_MODE - default is the average CANDLE |
//|                  RANGE of the N candles before the cross.         |
//|   Stop loss    : see ENUM_SL_MODE - default ATR multiple.         |
//|   Optional breakeven, ATR trail, time stop, opposite-signal exit. |
//|                                                                  |
//| TWO SPEC AMBIGUITIES, RESOLVED AS OPTIONS RATHER THAN GUESSES     |
//|                                                                  |
//| 1. "complete candle opens and closes above/below the Slow line"   |
//|    reads as the BODY (open and close). InpConfirmMode defaults to |
//|    CONFIRM_BODY for that literal reading; CONFIRM_FULL also       |
//|    requires the wicks to be clear of the Slow EMA.                |
//|                                                                  |
//| 2. "take profit - average of the last five candles" can mean the  |
//|    average candle SIZE or an average PRICE level. As a price      |
//|    level it usually sits behind the entry - the mean of the five  |
//|    candles before an upward cross is below where you buy - so     |
//|    TP_AVG_RANGE (average high-low, applied as a distance) is the  |
//|    default. TP_AVG_PRICE implements the literal level reading and |
//|    SKIPS any trade where that level is on the wrong side of the   |
//|    entry, which will show you quickly how often it is unusable.   |
//|                                                                  |
//| NOT COMPILED BY ITS AUTHOR - open in MetaEditor and compile (F7)  |
//| before trusting a single number it produces.                      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN EMA CROSS EA - two stage cross + slow-EMA confirmation candle"

#include <Trade\Trade.mqh>

//--- how the confirmation candle is judged against the Slow EMA
enum ENUM_CONFIRM_MODE
{
   CONFIRM_BODY = 0,   // open and close beyond the Slow EMA
   CONFIRM_FULL = 1    // the whole candle, wicks included, beyond it
};

//--- how take profit is derived
enum ENUM_TP_MODE
{
   TP_AVG_RANGE = 0,   // distance = average (high-low) of the N candles before the cross
   TP_AVG_PRICE = 1,   // level    = average typical price of those candles (literal reading)
   TP_ATR_MULT  = 2    // distance = ATR x multiplier
};

//--- how stop loss is derived
enum ENUM_SL_MODE
{
   SL_ATR      = 0,    // ATR x multiplier
   SL_SLOW_EMA = 1,    // the Slow EMA, plus a buffer
   SL_SWING    = 2,    // recent swing low / high, plus a buffer
   SL_FIXED    = 3     // fixed points
};

//--- position sizing
enum ENUM_LOT_MODE
{
   LOT_FIXED    = 0,   // always InpFixedLots
   LOT_RISK_PCT = 1    // size so the stop costs InpRiskPercent of equity
};

//=== EMA / cross engine (mirrors ARUN_EMA_CROSS_V1) =================
input int    InpFastLen            = 7;        // Fast EMA
input int    InpMidLen             = 21;       // Mid EMA
input int    InpSlowLen            = 50;       // Slow EMA
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;
input int    InpMaxBarsBetween     = 5;        // max candles between the two crosses

//=== Confirmation candle ===========================================
input ENUM_CONFIRM_MODE InpConfirmMode = CONFIRM_BODY;
input int    InpConfirmWithinBars  = 3;        // candles allowed for the confirmation to appear
input bool   InpConfirmSameBarOK   = true;     // the second-cross bar may itself confirm

//=== Take profit ====================================================
input ENUM_TP_MODE InpTPMode       = TP_AVG_RANGE;
input int    InpTPAvgCandles       = 5;        // candles averaged, taken BEFORE the cross bar
input double InpTPAtrMult          = 1.5;      // used only by TP_ATR_MULT
input double InpTPMinAtrMult       = 0.30;     // reject targets smaller than this x ATR

//=== Stop loss ======================================================
input ENUM_SL_MODE InpSLMode       = SL_ATR;
input double InpSLAtrMult          = 1.10;     // used by SL_ATR
input int    InpSLSwingBars        = 10;       // used by SL_SWING
input double InpSLBufferAtrMult    = 0.20;     // buffer for SL_SLOW_EMA / SL_SWING
input int    InpSLFixedPoints      = 300;      // used by SL_FIXED

//=== RSI divergence filter (optional) ==============================
input bool   InpUseDivergence      = false;    // require RSI divergence to agree
input int    InpRSIPeriod          = 14;
input int    InpDivPivotBars       = 2;        // bars either side that define a swing
input int    InpDivLookback        = 40;       // how far back to hunt for the two swings

//=== Trade management ==============================================
input bool   InpUseBreakeven       = false;
input double InpBreakevenAtR       = 1.0;      // move to breakeven at this multiple of risk
input bool   InpUseTrail           = false;
input double InpTrailAtrMult       = 1.50;
input bool   InpUseTimeStop        = false;
input int    InpTimeStopBars       = 20;       // close after this many bars in trade
input bool   InpCloseOnOpposite    = true;     // close when the opposite signal fires

//=== Risk / execution ==============================================
input ENUM_LOT_MODE InpLotMode     = LOT_FIXED;
input double InpFixedLots          = 0.01;
input double InpRiskPercent        = 0.5;      // used by LOT_RISK_PCT
input int    InpMaxSpreadPoints    = 0;        // 0 = no spread filter
input int    InpSlippagePoints     = 20;
input long   InpMagic              = 20260910;

//=== Session filter (server time) ==================================
input bool   InpUseSession         = false;
input int    InpSessionStartHour   = 7;
input int    InpSessionEndHour     = 20;

//=== Misc ===========================================================
input bool   InpShowComment        = true;     // status text on the chart
input bool   InpVerboseLog         = true;     // explain skipped setups in the journal

//--- handles
int hFast = INVALID_HANDLE, hMid = INVALID_HANDLE, hSlow = INVALID_HANDLE;
int hATR  = INVALID_HANDLE, hRSI = INVALID_HANDLE;

//--- cross state, expressed as "bars since", -1 meaning no live leg
int bullFMAge = -1, bullFSAge = -1, bearFMAge = -1, bearFSAge = -1;

//--- pending setup awaiting its confirmation candle
int    pendDir       = 0;    // +1 buy, -1 sell, 0 none
int    pendAge       = 0;    // bars since the second cross completed
double pendTPValue   = 0.0;  // distance or level, per InpTPMode
double pendRefPrice  = 0.0;  // close of the cross bar, for logging

//--- bookkeeping
datetime lastBarTime = 0;
datetime entryBarTime = 0;
double   entryRisk   = 0.0;  // price distance to the stop at entry, for breakeven maths
bool     beDone      = false;
string   lastNote    = "";

CTrade trade;

//+------------------------------------------------------------------+
//| Init / deinit                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   hFast = iMA(_Symbol, PERIOD_CURRENT, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMid  = iMA(_Symbol, PERIOD_CURRENT, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlow = iMA(_Symbol, PERIOD_CURRENT, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, 14);
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);

   if(hFast == INVALID_HANDLE || hMid == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
      hATR  == INVALID_HANDLE || hRSI == INVALID_HANDLE)
   {
      Print("ARUN EA: failed to create an indicator handle");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   lastBarTime = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   int hs[] = {hFast, hMid, hSlow, hATR, hRSI};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
   Comment("");
}

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0 || t == lastBarTime) return false;
   lastBarTime = t;
   return true;
}

//--- one value from an indicator buffer at a given shift
double BufAt(int handle, int shift)
{
   double v[];
   ArraySetAsSeries(v, true);
   if(CopyBuffer(handle, 0, shift, 1, v) < 1) return EMPTY_VALUE;
   return v[0];
}

double AtrNow()
{
   double a = BufAt(hATR, 1);
   if(a == EMPTY_VALUE || a <= 0.0) return 0.0;
   return a;
}

//--- our position on this symbol, if any: +1 long, -1 short, 0 none
int MyPositionDir(ulong &ticket)
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
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   if(lots < mn) lots = mn;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, 2);
}

//--- lots such that slDistance costs InpRiskPercent of equity
double CalcLots(double slDistance)
{
   if(InpLotMode == LOT_FIXED || slDistance <= 0.0)
      return NormalizeLots(InpFixedLots);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return NormalizeLots(InpFixedLots);

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return NormalizeLots(InpFixedLots);

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   return NormalizeLots(riskMoney / lossPerLot);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return true;
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (sp <= InpMaxSpreadPoints);
}

bool SessionOK()
{
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   // window wraps past midnight
   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
}

//--- keep stops legal for the broker
double MinStopDistance()
{
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (double)lvl * _Point;
}

//+------------------------------------------------------------------+
//| Stage 1 + 2: the two-stage cross, mirroring the indicator        |
//| Ages are in bars, 0 meaning "on the bar that just closed".        |
//+------------------------------------------------------------------+
void UpdateCrossState(int &signalDir)
{
   signalDir = 0;

   double f[], m[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(m, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hFast, 0, 1, 2, f) < 2) return;
   if(CopyBuffer(hMid,  0, 1, 2, m) < 2) return;
   if(CopyBuffer(hSlow, 0, 1, 2, s) < 2) return;

   int N = MathMax(0, InpMaxBarsBetween);

   // age the live legs, and drop the ones that have run out of window
   if(bullFMAge >= 0) { bullFMAge++; if(bullFMAge > N) bullFMAge = -1; }
   if(bullFSAge >= 0) { bullFSAge++; if(bullFSAge > N) bullFSAge = -1; }
   if(bearFMAge >= 0) { bearFMAge++; if(bearFMAge > N) bearFMAge = -1; }
   if(bearFSAge >= 0) { bearFSAge++; if(bearFSAge > N) bearFSAge = -1; }

   // f[0]/m[0]/s[0] = the bar that just closed, f[1]/... = the one before it
   bool fmUp = (f[0] >  m[0] && f[1] <= m[1]);
   bool fmDn = (f[0] <  m[0] && f[1] >= m[1]);
   bool fsUp = (f[0] >  s[0] && f[1] <= s[1]);
   bool fsDn = (f[0] <  s[0] && f[1] >= s[1]);

   // a cross the other way cancels the pending leg of the same pair
   if(fmUp) { bullFMAge = 0; bearFMAge = -1; }
   if(fmDn) { bearFMAge = 0; bullFMAge = -1; }
   if(fsUp) { bullFSAge = 0; bearFSAge = -1; }
   if(fsDn) { bearFSAge = 0; bullFSAge = -1; }

   bool buy  = (bullFMAge >= 0 && bullFSAge >= 0 && MathAbs(bullFMAge - bullFSAge) <= N);
   bool sell = (bearFMAge >= 0 && bearFSAge >= 0 && MathAbs(bearFMAge - bearFSAge) <= N);

   if(buy)  { bullFMAge = -1; bullFSAge = -1; signalDir =  1; }
   if(sell) { bearFMAge = -1; bearFSAge = -1; signalDir = (signalDir == 1 ? signalDir : -1); }
}

//+------------------------------------------------------------------+
//| Stage 3: the confirmation candle                                 |
//+------------------------------------------------------------------+
bool ConfirmCandle(int shift, int dir)
{
   double o = iOpen(_Symbol,  PERIOD_CURRENT, shift);
   double c = iClose(_Symbol, PERIOD_CURRENT, shift);
   double h = iHigh(_Symbol,  PERIOD_CURRENT, shift);
   double l = iLow(_Symbol,   PERIOD_CURRENT, shift);
   double e = BufAt(hSlow, shift);
   if(e == EMPTY_VALUE || o == 0.0 || c == 0.0) return false;

   if(dir > 0)
   {
      if(InpConfirmMode == CONFIRM_FULL) return (l > e);
      return (o > e && c > e);
   }
   if(InpConfirmMode == CONFIRM_FULL) return (h < e);
   return (o < e && c < e);
}

//+------------------------------------------------------------------+
//| Take profit inputs, measured on the candles BEFORE the cross bar |
//+------------------------------------------------------------------+
double AvgRangeBefore(int crossShift, int count)
{
   double sum = 0.0;
   int n = 0;
   for(int i = crossShift + 1; i <= crossShift + count; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol,  PERIOD_CURRENT, i);
      if(h <= 0.0 || l <= 0.0) continue;
      sum += (h - l);
      n++;
   }
   return (n > 0 ? sum / n : 0.0);
}

double AvgTypicalBefore(int crossShift, int count)
{
   double sum = 0.0;
   int n = 0;
   for(int i = crossShift + 1; i <= crossShift + count; i++)
   {
      double h = iHigh(_Symbol,  PERIOD_CURRENT, i);
      double l = iLow(_Symbol,   PERIOD_CURRENT, i);
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      if(h <= 0.0 || l <= 0.0 || c <= 0.0) continue;
      sum += (h + l + c) / 3.0;
      n++;
   }
   return (n > 0 ? sum / n : 0.0);
}

//+------------------------------------------------------------------+
//| Stage 4: optional RSI divergence                                 |
//| Bullish - price makes a lower low, RSI a higher low.             |
//| Bearish - price makes a higher high, RSI a lower high.           |
//+------------------------------------------------------------------+
bool FindTwoPivots(int startShift, int dir, int &p1, int &p2)
{
   int lr = MathMax(1, InpDivPivotBars);
   p1 = -1; p2 = -1;

   for(int i = startShift + lr; i <= startShift + InpDivLookback; i++)
   {
      double v = (dir > 0) ? iLow(_Symbol, PERIOD_CURRENT, i)
                           : iHigh(_Symbol, PERIOD_CURRENT, i);
      if(v <= 0.0) continue;

      bool isPivot = true;
      for(int k = 1; k <= lr; k++)
      {
         double a = (dir > 0) ? iLow(_Symbol, PERIOD_CURRENT, i - k)
                              : iHigh(_Symbol, PERIOD_CURRENT, i - k);
         double b = (dir > 0) ? iLow(_Symbol, PERIOD_CURRENT, i + k)
                              : iHigh(_Symbol, PERIOD_CURRENT, i + k);
         if(a <= 0.0 || b <= 0.0) { isPivot = false; break; }
         if(dir > 0) { if(a < v || b < v) { isPivot = false; break; } }
         else        { if(a > v || b > v) { isPivot = false; break; } }
      }
      if(!isPivot) continue;

      if(p1 < 0) { p1 = i; i += lr; }
      else       { p2 = i; return true; }
   }
   return false;
}

bool HasDivergence(int dir, int startShift)
{
   int p1 = -1, p2 = -1;
   if(!FindTwoPivots(startShift, dir, p1, p2)) return false;

   double r1 = BufAt(hRSI, p1);
   double r2 = BufAt(hRSI, p2);
   if(r1 == EMPTY_VALUE || r2 == EMPTY_VALUE) return false;

   if(dir > 0)
   {
      double l1 = iLow(_Symbol, PERIOD_CURRENT, p1);
      double l2 = iLow(_Symbol, PERIOD_CURRENT, p2);
      return (l1 < l2 && r1 > r2);   // lower low in price, higher low in RSI
   }
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, p1);
   double h2 = iHigh(_Symbol, PERIOD_CURRENT, p2);
   return (h1 > h2 && r1 < r2);      // higher high in price, lower high in RSI
}

//+------------------------------------------------------------------+
//| Entry                                                            |
//+------------------------------------------------------------------+
void OpenTrade(int dir, double tpValue)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (dir > 0) ? ask : bid;
   double atr = AtrNow();
   double minDist = MinStopDistance();

   //--- stop loss
   double sl = 0.0;
   double buffer = atr * InpSLBufferAtrMult;
   if(InpSLMode == SL_ATR)
   {
      double d = (atr > 0.0 ? atr * InpSLAtrMult : InpSLFixedPoints * _Point);
      sl = (dir > 0) ? entry - d : entry + d;
   }
   else if(InpSLMode == SL_SLOW_EMA)
   {
      double e = BufAt(hSlow, 1);
      if(e == EMPTY_VALUE) return;
      sl = (dir > 0) ? e - buffer : e + buffer;
   }
   else if(InpSLMode == SL_SWING)
   {
      double ext = (dir > 0) ? iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSLSwingBars, 1))
                             : iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSLSwingBars, 1));
      sl = (dir > 0) ? ext - buffer : ext + buffer;
   }
   else
   {
      double d = InpSLFixedPoints * _Point;
      sl = (dir > 0) ? entry - d : entry + d;
   }

   double slDist = MathAbs(entry - sl);
   if(slDist < minDist || slDist <= 0.0)
   {
      if(InpVerboseLog) Print("ARUN EA: stop too close to price, setup skipped");
      return;
   }

   //--- take profit
   double tp = 0.0;
   if(InpTPMode == TP_AVG_PRICE)
   {
      tp = tpValue;   // an absolute level
      if(dir > 0 && tp <= entry + minDist)
      {
         if(InpVerboseLog)
            PrintFormat("ARUN EA: TP_AVG_PRICE level %.5f is not above entry %.5f - setup skipped",
                        tp, entry);
         return;
      }
      if(dir < 0 && tp >= entry - minDist)
      {
         if(InpVerboseLog)
            PrintFormat("ARUN EA: TP_AVG_PRICE level %.5f is not below entry %.5f - setup skipped",
                        tp, entry);
         return;
      }
   }
   else
   {
      double d = tpValue;   // a distance
      if(atr > 0.0 && d < atr * InpTPMinAtrMult)
      {
         if(InpVerboseLog)
            PrintFormat("ARUN EA: target %.5f below the %.2f x ATR floor - setup skipped",
                        d, InpTPMinAtrMult);
         return;
      }
      if(d < minDist) d = minDist;
      tp = (dir > 0) ? entry + d : entry - d;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalcLots(slDist);
   string cmt = "ARUN " + (dir > 0 ? "BUY" : "SELL");

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt)
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt);

   if(ok)
   {
      entryBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      entryRisk    = slDist;
      beDone       = false;
      lastNote     = cmt + " @ " + DoubleToString(entry, _Digits);
      if(InpVerboseLog)
         PrintFormat("ARUN EA: %s %.2f lots, entry %.5f, SL %.5f, TP %.5f",
                     (dir > 0 ? "BUY" : "SELL"), lots, entry, sl, tp);
   }
   else
   {
      lastNote = "order failed: " + IntegerToString(trade.ResultRetcode());
      Print("ARUN EA: order failed, retcode ", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Position management - runs every tick                            |
//+------------------------------------------------------------------+
void ManagePosition()
{
   ulong ticket = 0;
   int dir = MyPositionDir(ticket);
   if(dir == 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px   = (dir > 0) ? bid : ask;
   double atr  = AtrNow();
   double minDist = MinStopDistance();

   //--- breakeven
   if(InpUseBreakeven && !beDone && entryRisk > 0.0)
   {
      double moved = (dir > 0) ? (px - open) : (open - px);
      if(moved >= entryRisk * InpBreakevenAtR)
      {
         double newSL = NormalizeDouble(open, _Digits);
         if((dir > 0 && newSL > sl && px - newSL > minDist) ||
            (dir < 0 && (sl == 0.0 || newSL < sl) && newSL - px > minDist))
         {
            if(trade.PositionModify(ticket, newSL, tp)) { beDone = true; sl = newSL; }
         }
      }
   }

   //--- ATR trail
   if(InpUseTrail && atr > 0.0)
   {
      double d = atr * InpTrailAtrMult;
      double newSL = (dir > 0) ? px - d : px + d;
      newSL = NormalizeDouble(newSL, _Digits);
      if(dir > 0 && newSL > sl && px - newSL > minDist)
         trade.PositionModify(ticket, newSL, tp);
      if(dir < 0 && (sl == 0.0 || newSL < sl) && newSL - px > minDist)
         trade.PositionModify(ticket, newSL, tp);
   }

   //--- time stop
   if(InpUseTimeStop && entryBarTime > 0)
   {
      int barsIn = iBarShift(_Symbol, PERIOD_CURRENT, entryBarTime, false);
      if(barsIn >= InpTimeStopBars)
      {
         trade.PositionClose(ticket);
         lastNote = "closed on time stop";
      }
   }
}

//+------------------------------------------------------------------+
//| Status text                                                      |
//+------------------------------------------------------------------+
void ShowComment()
{
   if(!InpShowComment) return;

   string pend = "none";
   if(pendDir != 0)
      pend = (pendDir > 0 ? "BUY" : "SELL") + StringFormat(" - waiting on confirm candle (%d of %d bars)",
             pendAge, InpConfirmWithinBars);

   string legs = StringFormat("bullFM %d  bullFS %d  bearFM %d  bearFS %d",
                              bullFMAge, bullFSAge, bearFMAge, bearFSAge);

   ulong tk = 0;
   int dir = MyPositionDir(tk);

   Comment(StringFormat(
      "ARUN EMA CROSS EA\n"
      "EMAs %d / %d / %d   window %d bars\n"
      "legs: %s\n"
      "pending: %s\n"
      "position: %s\n"
      "last: %s",
      InpFastLen, InpMidLen, InpSlowLen, InpMaxBarsBetween,
      legs, pend,
      (dir == 0 ? "flat" : (dir > 0 ? "LONG" : "SHORT")),
      lastNote));
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePosition();

   if(!IsNewBar())
   {
      ShowComment();
      return;
   }

   //--- Stage 1 + 2 on the bar that just closed
   int signalDir = 0;
   UpdateCrossState(signalDir);

   ulong ticket = 0;
   int posDir = MyPositionDir(ticket);

   //--- an opposite signal can close the open trade
   if(signalDir != 0 && posDir != 0 && signalDir != posDir && InpCloseOnOpposite)
   {
      trade.PositionClose(ticket);
      lastNote = "closed on opposite signal";
      posDir = 0;
   }

   //--- a fresh signal arms a setup; the TP inputs are frozen here,
   //--- measured on the candles before the cross bar, as specified
   if(signalDir != 0)
   {
      pendDir      = signalDir;
      pendAge      = 0;
      pendRefPrice = iClose(_Symbol, PERIOD_CURRENT, 1);

      if(InpTPMode == TP_AVG_RANGE)      pendTPValue = AvgRangeBefore(1, InpTPAvgCandles);
      else if(InpTPMode == TP_AVG_PRICE) pendTPValue = AvgTypicalBefore(1, InpTPAvgCandles);
      else                               pendTPValue = AtrNow() * InpTPAtrMult;

      if(InpVerboseLog)
         PrintFormat("ARUN EA: %s cross pair complete at %.5f, TP input %.5f",
                     (signalDir > 0 ? "BUY" : "SELL"), pendRefPrice, pendTPValue);

      //--- the cross bar itself may serve as the confirmation candle
      if(InpConfirmSameBarOK && ConfirmCandle(1, pendDir) && posDir == 0)
      {
         if(!InpUseDivergence || HasDivergence(pendDir, 1))
         {
            if(SpreadOK() && SessionOK()) OpenTrade(pendDir, pendTPValue);
            else if(InpVerboseLog) Print("ARUN EA: blocked by spread or session filter");
         }
         else if(InpVerboseLog) Print("ARUN EA: no RSI divergence, setup skipped");
         pendDir = 0;
      }
      ShowComment();
      return;
   }

   //--- Stage 3: still waiting for a confirmation candle
   if(pendDir != 0)
   {
      pendAge++;
      if(pendAge > InpConfirmWithinBars)
      {
         if(InpVerboseLog) Print("ARUN EA: no confirmation candle in window, setup dropped");
         pendDir = 0;
      }
      else if(ConfirmCandle(1, pendDir))
      {
         if(posDir == 0)
         {
            if(!InpUseDivergence || HasDivergence(pendDir, 1))
            {
               if(SpreadOK() && SessionOK()) OpenTrade(pendDir, pendTPValue);
               else if(InpVerboseLog) Print("ARUN EA: blocked by spread or session filter");
            }
            else if(InpVerboseLog) Print("ARUN EA: no RSI divergence, setup skipped");
         }
         pendDir = 0;
      }
   }

   ShowComment();
}
//+------------------------------------------------------------------+
