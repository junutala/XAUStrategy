//+------------------------------------------------------------------+
//|                                        ARUN_SIGNAL_PROBE_EA.mq5  |
//| Measures the signal. Does not trade it.                          |
//|                                                                  |
//| WHY THIS EXISTS                                                  |
//|   A fixed bracket answers one question - "does this entry beat    |
//|   the spread over the distance I happened to choose". Choose the  |
//|   distance too short and the answer is always no, because the     |
//|   spread toll per trade is flat in the bracket width while the    |
//|   edge, if any, grows with its square. At 0.03 lots on gold a $2  |
//|   bracket is 67 points against a 24 point spread, and 93% of      |
//|   those trades closed inside one minute. That measured the        |
//|   spread, not the signal.                                        |
//|                                                                  |
//|   So this build takes the bracket away. At every signal it        |
//|   records where price went over eight horizons at once, with the  |
//|   best and worst excursion inside each. No orders, no positions,  |
//|   no one-trade-at-a-time constraint, no spread. Overlapping       |
//|   signals are all measured. What comes out says whether the       |
//|   entry has any forward drift at all, at which horizon it is      |
//|   largest, and what the MFE to MAE ratio there implies for a      |
//|   take profit and a stop. Those numbers then set the bracket.     |
//|                                                                  |
//| ENTRY SIGNAL - identical to ARUN_MTF_TPSL_EA, deliberately, so    |
//|   the two runs describe the same population:                      |
//|   1. Fast EMA cuts Mid or Slow on the higher timeframe            |
//|   2. the same cut, same direction, on the chart timeframe, while  |
//|      the higher timeframe one is still within InpHtfValidBars     |
//|   3. the last closed candle wholly clear of the Slow EMA          |
//|                                                                  |
//| READING THE OUTPUT                                               |
//|   Every return is signed by the trade direction, so positive      |
//|   always means the signal was right. ret_N is the move N chart    |
//|   bars later; mfe_N and mae_N are the best and worst it reached   |
//|   at any point inside those N bars. A signal with no edge shows   |
//|   mean ret near zero at every horizon and mfe roughly equal to    |
//|   -mae. A signal with edge shows mean ret rising with the horizon |
//|   and mfe pulling away from mae.                                 |
//|                                                                  |
//| NOT COMPILED BY ITS AUTHOR - compile in MetaEditor before use.    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN SIGNAL PROBE - measures forward returns after each signal. Places no trades."

//--- which EMA the Fast line has to cut
enum ENUM_CROSS_TARGET
{
   CROSS_EITHER    = 0,   // Mid or Slow, whichever comes first
   CROSS_MID_ONLY  = 1,
   CROSS_SLOW_ONLY = 2
};

enum ENUM_CANDLE_MODE
{
   CANDLE_BODY = 0,   // open and close both beyond the Slow EMA
   CANDLE_FULL = 1    // the whole candle, wicks included, beyond it
};

enum ENUM_CANDLE_TF
{
   CANDLE_TF_LOWER = 0,   // chart timeframe only
   CANDLE_TF_BOTH  = 1
};

//=== Timeframes =====================================================
input ENUM_TIMEFRAMES InpHigherTF = PERIOD_M5;

//=== EMAs ===========================================================
input int    InpFastLen        = 7;
input int    InpMidLen         = 21;
input int    InpSlowLen        = 50;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;

//=== Cross rules ====================================================
input ENUM_CROSS_TARGET InpCrossTarget = CROSS_EITHER;
input int    InpHtfValidBars   = 3;
input bool   InpRequireSameLeg = false;

//=== Candle must clear the Slow EMA =================================
input bool   InpRequireCandle  = true;
input ENUM_CANDLE_MODE InpCandleMode = CANDLE_BODY;
input ENUM_CANDLE_TF   InpCandleTf   = CANDLE_TF_LOWER;

//=== Horizons, in bars of the CHART timeframe =======================
// On an M1 chart these are minutes. Must be in increasing order; a
// zero switches the rest off.
input int    InpH1 = 1;
input int    InpH2 = 3;
input int    InpH3 = 5;
input int    InpH4 = 10;
input int    InpH5 = 15;
input int    InpH6 = 30;
input int    InpH7 = 60;
input int    InpH8 = 120;

//=== Misc ===========================================================
input int    InpAtrPeriod      = 14;
input bool   InpShowComment    = true;
input string InpCsvName        = "arun_probe.csv";

#define NH 8
#define MAXOBS 4096

//--- indicator handles, L = chart timeframe, H = higher timeframe
int hFastL = INVALID_HANDLE, hMidL = INVALID_HANDLE, hSlowL = INVALID_HANDLE, hAtrL = INVALID_HANDLE;
int hFastH = INVALID_HANDLE, hMidH = INVALID_HANDLE, hSlowH = INVALID_HANDLE, hAtrH = INVALID_HANDLE;

int horizons[NH];
int nH = 0;

//--- one signal being followed forward. Legs are held as ints so the
//--- struct stays a plain value type.
struct Obs
{
   bool     active;
   datetime t0;
   int      dir;
   double   px0;
   int      htfLeg;     // 0 = MID, 1 = SLOW
   int      ltfLeg;
   int      htfAge;
   double   atrL, atrH, slowDist;
   int      spread, hour, dow;
   int      age;        // chart bars since the signal
   double   runMfe, runMae;
   double   ret[NH], mfe[NH], mae[NH];
   int      nextH;      // index of the next horizon still to record
};
Obs obs[MAXOBS];

datetime lastBarL = 0, lastBarH = 0;
int      htfDir = 0, htfLegNow = 0;
datetime htfCrossBar = 0;

int    csvHandle = INVALID_HANDLE;
int    rowIdx = 0, cntSignals = 0, cntDropped = 0;
int    cntNoHtfDir = 0, cntHtfStale = 0, cntWrongLeg = 0, cntNoCandle = 0, cntLtfCross = 0;
double sumRet[NH], sumMfe[NH], sumMae[NH];
int    nRet[NH], nUp[NH];

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastLen >= InpMidLen || InpMidLen >= InpSlowLen)
   {
      Print("ARUN PROBE: need Fast < Mid < Slow");
      return INIT_PARAMETERS_INCORRECT;
   }

   int raw[NH];
   raw[0]=InpH1; raw[1]=InpH2; raw[2]=InpH3; raw[3]=InpH4;
   raw[4]=InpH5; raw[5]=InpH6; raw[6]=InpH7; raw[7]=InpH8;
   nH = 0;
   for(int i = 0; i < NH; i++)
   {
      if(raw[i] <= 0) break;
      if(nH > 0 && raw[i] <= horizons[nH-1])
      {
         Print("ARUN PROBE: horizons must increase");
         return INIT_PARAMETERS_INCORRECT;
      }
      horizons[nH++] = raw[i];
   }
   if(nH == 0) { Print("ARUN PROBE: no horizons"); return INIT_PARAMETERS_INCORRECT; }

   hFastL = iMA(_Symbol, PERIOD_CURRENT, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMidL  = iMA(_Symbol, PERIOD_CURRENT, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlowL = iMA(_Symbol, PERIOD_CURRENT, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hAtrL  = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   hFastH = iMA(_Symbol, InpHigherTF, InpFastLen, 0, MODE_EMA, InpAppliedPrice);
   hMidH  = iMA(_Symbol, InpHigherTF, InpMidLen,  0, MODE_EMA, InpAppliedPrice);
   hSlowH = iMA(_Symbol, InpHigherTF, InpSlowLen, 0, MODE_EMA, InpAppliedPrice);
   hAtrH  = iATR(_Symbol, InpHigherTF, InpAtrPeriod);

   int hs[] = {hFastL, hMidL, hSlowL, hAtrL, hFastH, hMidH, hSlowH, hAtrH};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] == INVALID_HANDLE) { Print("ARUN PROBE: handle failed"); return INIT_FAILED; }

   for(int i = 0; i < MAXOBS; i++) obs[i].active = false;
   for(int i = 0; i < NH; i++) { sumRet[i]=0; sumMfe[i]=0; sumMae[i]=0; nRet[i]=0; nUp[i]=0; }
   lastBarL = 0; lastBarH = 0;

   csvHandle = FileOpen(InpCsvName, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(csvHandle == INVALID_HANDLE)
      Print("ARUN PROBE: could not open ", InpCsvName, " err ", GetLastError());
   else
   {
      PrintFormat("ARUN PROBE: writing to %s\\Files\\%s",
                  TerminalInfoString(TERMINAL_COMMONDATA_PATH), InpCsvName);
      //--- header is built to match however many horizons are in use
      string h = "idx,signal_time,dir,price,htf_leg,ltf_leg,htf_age,"
                 "atr_ltf,atr_htf,slow_dist_atr,spread_pts,hour,dow";
      for(int i = 0; i < nH; i++)
         h += StringFormat(",ret_%d,mfe_%d,mae_%d", horizons[i], horizons[i], horizons[i]);
      FileWrite(csvHandle, h);
   }
   Print("ARUN PROBE: measuring only - this expert places no orders");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   //--- anything still in flight never reached its last horizon; the
   //--- partial rows are written so the short horizons are not lost
   for(int i = 0; i < MAXOBS; i++)
      if(obs[i].active) { WriteRow(i, true); obs[i].active = false; }

   if(csvHandle != INVALID_HANDLE) { FileClose(csvHandle); csvHandle = INVALID_HANDLE; }
   PrintReport();
   int hs[] = {hFastL, hMidL, hSlowL, hAtrL, hFastH, hMidH, hSlowH, hAtrH};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
   Comment("");
}

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

int DetectCross(int hF, int hM, int hS, int &leg)
{
   leg = -1;
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

   if(wantSlow && fsUp) { leg = 1; return  1; }
   if(wantSlow && fsDn) { leg = 1; return -1; }
   if(wantMid  && fmUp) { leg = 0; return  1; }
   if(wantMid  && fmDn) { leg = 0; return -1; }
   return 0;
}

bool CandleClearsSlow(ENUM_TIMEFRAMES tf, int hSlow, int hAtr, int dir, double &distAtr)
{
   distAtr = 0.0;
   double o = iOpen(_Symbol, tf, 1), c = iClose(_Symbol, tf, 1);
   double h = iHigh(_Symbol, tf, 1), l = iLow(_Symbol, tf, 1);
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

string LegName(int v) { return (v == 1 ? "SLOW" : (v == 0 ? "MID" : "?")); }

//+------------------------------------------------------------------+
//| Write one observation out. partial = it never reached the end.   |
//+------------------------------------------------------------------+
void WriteRow(int i, bool partial)
{
   if(csvHandle == INVALID_HANDLE) return;
   rowIdx++;
   string line = StringFormat("%d,%s,%d,%s,%s,%s,%d,%s,%s,%.4f,%d,%d,%d",
      rowIdx,
      TimeToString(obs[i].t0, TIME_DATE | TIME_SECONDS),
      obs[i].dir,
      DoubleToString(obs[i].px0, _Digits),
      LegName(obs[i].htfLeg), LegName(obs[i].ltfLeg), obs[i].htfAge,
      DoubleToString(obs[i].atrL, _Digits), DoubleToString(obs[i].atrH, _Digits),
      obs[i].slowDist, obs[i].spread, obs[i].hour, obs[i].dow);

   for(int k = 0; k < nH; k++)
   {
      if(k < obs[i].nextH)
         line += StringFormat(",%.5f,%.5f,%.5f", obs[i].ret[k], obs[i].mfe[k], obs[i].mae[k]);
      else
         line += ",,,";          // horizon never reached - left empty, not zero
   }
   FileWrite(csvHandle, line);
   if(partial) cntDropped++;
}

//+------------------------------------------------------------------+
//| One chart bar has closed: advance every live observation         |
//+------------------------------------------------------------------+
void AdvanceObservations()
{
   double hi = iHigh(_Symbol,  PERIOD_CURRENT, 1);
   double lo = iLow(_Symbol,   PERIOD_CURRENT, 1);
   double cl = iClose(_Symbol, PERIOD_CURRENT, 1);
   if(hi <= 0.0 || lo <= 0.0) return;

   for(int i = 0; i < MAXOBS; i++)
   {
      if(!obs[i].active) continue;
      obs[i].age++;

      //--- excursions are signed by direction, so positive is always
      //--- "the signal was right"
      double up = obs[i].dir * (hi - obs[i].px0);
      double dn = obs[i].dir * (lo - obs[i].px0);
      double best  = MathMax(up, dn);
      double worst = MathMin(up, dn);
      if(best  > obs[i].runMfe) obs[i].runMfe = best;
      if(worst < obs[i].runMae) obs[i].runMae = worst;

      while(obs[i].nextH < nH && obs[i].age >= horizons[obs[i].nextH])
      {
         int k = obs[i].nextH;
         obs[i].ret[k] = obs[i].dir * (cl - obs[i].px0);
         obs[i].mfe[k] = obs[i].runMfe;
         obs[i].mae[k] = obs[i].runMae;
         sumRet[k] += obs[i].ret[k];
         sumMfe[k] += obs[i].mfe[k];
         sumMae[k] += obs[i].mae[k];
         nRet[k]++;
         if(obs[i].ret[k] > 0.0) nUp[k]++;
         obs[i].nextH++;
      }
      if(obs[i].nextH >= nH) { WriteRow(i, false); obs[i].active = false; }
   }
}

//+------------------------------------------------------------------+
void RecordSignal(int dir, int ltfLeg, int htfAge, double slowDist)
{
   int slot = -1;
   for(int i = 0; i < MAXOBS; i++)
      if(!obs[i].active) { slot = i; break; }
   if(slot < 0) { Print("ARUN PROBE: observation table full"); return; }

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   obs[slot].active   = true;
   obs[slot].t0       = TimeCurrent();
   obs[slot].dir      = dir;
   //--- measured from the mid price: this build is about the signal,
   //--- and paying the spread would only re-measure the spread
   obs[slot].px0      = (SymbolInfoDouble(_Symbol, SYMBOL_BID) +
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;
   obs[slot].htfLeg   = htfLegNow;
   obs[slot].ltfLeg   = ltfLeg;
   obs[slot].htfAge   = htfAge;
   obs[slot].atrL     = AtrAt(hAtrL, 1);
   obs[slot].atrH     = AtrAt(hAtrH, 1);
   obs[slot].slowDist = slowDist;
   obs[slot].spread   = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   obs[slot].hour     = dt.hour;
   obs[slot].dow      = dt.day_of_week;
   obs[slot].age      = 0;
   obs[slot].runMfe   = 0.0;
   obs[slot].runMae   = 0.0;
   obs[slot].nextH    = 0;
   for(int k = 0; k < NH; k++) { obs[slot].ret[k]=0; obs[slot].mfe[k]=0; obs[slot].mae[k]=0; }
   cntSignals++;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime tH = iTime(_Symbol, InpHigherTF, 0);
   if(tH != 0 && tH != lastBarH)
   {
      lastBarH = tH;
      int leg = -1;
      int d = DetectCross(hFastH, hMidH, hSlowH, leg);
      if(d != 0) { htfDir = d; htfLegNow = leg; htfCrossBar = iTime(_Symbol, InpHigherTF, 1); }
   }

   datetime tL = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(tL == 0 || tL == lastBarL) return;
   lastBarL = tL;

   AdvanceObservations();

   int ltfLeg = -1;
   int signalDir = DetectCross(hFastL, hMidL, hSlowL, ltfLeg);
   if(signalDir != 0)
   {
      cntLtfCross++;
      bool ok = true;
      int  htfAge = 9999;
      if(htfDir != signalDir) { cntNoHtfDir++; ok = false; }
      if(ok)
      {
         htfAge = (htfCrossBar > 0) ? iBarShift(_Symbol, InpHigherTF, htfCrossBar, false) : 9999;
         if(htfAge < 0) htfAge = 9999;
         if(InpHtfValidBars > 0 && htfAge > InpHtfValidBars) { cntHtfStale++; ok = false; }
      }
      if(ok && InpRequireSameLeg && ltfLeg != htfLegNow) { cntWrongLeg++; ok = false; }

      double distAtr = 0.0;
      if(ok)
      {
         bool clear = CandleClearsSlow(PERIOD_CURRENT, hSlowL, hAtrL, signalDir, distAtr);
         if(InpRequireCandle && !clear) { cntNoCandle++; ok = false; }
         if(ok && InpRequireCandle && InpCandleTf == CANDLE_TF_BOTH)
         {
            double dh = 0.0;
            if(!CandleClearsSlow(InpHigherTF, hSlowH, hAtrH, signalDir, dh))
            { cntNoCandle++; ok = false; }
         }
      }
      if(ok)
      {
         RecordSignal(signalDir, ltfLeg, htfAge, distAtr);
         //--- consume the higher timeframe cross, exactly as the
         //--- trading build does, so the two populations match
         htfDir = 0; htfCrossBar = 0;
      }
   }

   if(InpShowComment)
   {
      int live = 0;
      for(int i = 0; i < MAXOBS; i++) if(obs[i].active) live++;
      Comment(StringFormat("ARUN SIGNAL PROBE (no trading)\nsignals %d   in flight %d   rows %d",
                           cntSignals, live, rowIdx));
   }
}

//+------------------------------------------------------------------+
void PrintReport()
{
   Print("============== ARUN SIGNAL PROBE - run summary ==============");
   PrintFormat("chart %s  +  higher %s",
               EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpHigherTF));
   PrintFormat("chart TF crosses      : %d", cntLtfCross);
   PrintFormat("  no HTF agreement    : %d", cntNoHtfDir);
   PrintFormat("  HTF cross stale     : %d", cntHtfStale);
   PrintFormat("  different EMA cut   : %d", cntWrongLeg);
   PrintFormat("  candle not clear    : %d", cntNoCandle);
   PrintFormat("signals recorded      : %d   rows written %d   partial %d",
               cntSignals, rowIdx, cntDropped);
   Print("--- forward move, signed so positive means the signal was right ---");
   Print("  bars      n   mean ret    mean MFE    mean MAE   MFE/|MAE|   up %");
   for(int k = 0; k < nH; k++)
   {
      if(nRet[k] == 0) continue;
      double mr = sumRet[k]/nRet[k], mf = sumMfe[k]/nRet[k], ma = sumMae[k]/nRet[k];
      PrintFormat("  %4d %6d  %+9.4f  %+9.4f  %+9.4f  %9.3f  %5.1f%%",
                  horizons[k], nRet[k], mr, mf, ma,
                  (MathAbs(ma) > 0.0 ? mf/MathAbs(ma) : 0.0),
                  100.0*nUp[k]/(double)nRet[k]);
   }
   Print("A signal with no edge shows mean ret near zero at every horizon");
   Print("and MFE/|MAE| near 1.0. Edge shows as ret growing with the horizon.");
   Print("============================================================");
}
