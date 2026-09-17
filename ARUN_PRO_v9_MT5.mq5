//+------------------------------------------------------------------+
//|                                                ARUN_PRO_v9.mq5   |
//| Native MT5 ARUN Indicator Pro v9 - Confidence Engine.           |
//|                                                                 |
//| New in v9: the fair value gap guard. See the block above         |
//| FvgAt() for what it measures and why the gap's own direction     |
//| decides which signal it warns about.                            |
//| Signal logic is unchanged from v7. The panel differs: the three  |
//| measured angles are printed and coloured individually, TARGET    |
//| and POTENTIAL are gone, and a countdown to the candle close was  |
//| added. Object names carry their own version prefix so v7 and v8  |
//| can sit on the same chart without overwriting each other.       |
//+------------------------------------------------------------------+
#property strict
#property version   "9.00"
#property description "ARUN PRO v9 - Native MT5 Confidence Engine"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "Fast EMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label2  "Mid EMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label3  "Slow EMA"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_width3  2
#property indicator_label4  "BUY"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2
#property indicator_label5  "SELL"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  2

//--- Inputs
input int      InpFastLen              = 7;
input int      InpMidLen               = 21;
input int      InpSlowLen              = 50;
input int      InpAngleLookback        = 5;
input int      InpATRLen               = 14;

input bool     InpLinkRangeToSlow      = true;
input int      InpRangeLenManual       = 50;
input bool     InpShowRangeLines       = true;

input int      InpConfidenceLookback   = 15;
// The target is no longer shown on the panel, but it still defines what
// counts as a win for BUY CONF / SELL CONF, so the settings stay.
enum ENUM_TARGET_MODE { TARGET_ATR_MULTIPLE=0, TARGET_FIXED_POINTS=1 };
input ENUM_TARGET_MODE InpTargetMode   = TARGET_ATR_MULTIPLE;
input double   InpTargetAtrMult        = 0.50;
input double   InpTargetPoints         = 2.0;
input int      InpPotentialWindowBars  = 10;
input datetime InpAnalysisStartDate    = D'2026.08.21 00:00';

input bool     InpShowSignals          = true;
input bool     InpShowEntryPrice       = false;

enum ENUM_CANDLE_SIDE_MODE { CANDLE_FULL=0, CANDLE_BODY=1, CANDLE_CLOSE=2 };
input ENUM_CANDLE_SIDE_MODE InpCandleSideMode = CANDLE_FULL;

input bool     InpUseMTFFilter         = false;
input bool     InpUseAngleFilter       = false;
input ENUM_TIMEFRAMES InpMTF1           = PERIOD_M3;
input ENUM_TIMEFRAMES InpMTF2           = PERIOD_M5;
input ENUM_TIMEFRAMES InpMTF3           = PERIOD_M10;

//=== Fair value gap guard ==========================================
// A three candle imbalance: the middle candle travels far enough that
// the outer two do not overlap, leaving a band price skipped over.
// Price commonly returns to trade through that band before continuing.
// So a cross that fires with an unfilled gap behind it tends to detour
// first - which is the drawdown, not the trade going wrong.
input bool     InpUseFvgGuard          = true;
input int      InpFvgLookback          = 20;    // candles scanned for gaps
input double   InpFvgMinAtr            = 0.20;  // ignore gaps narrower than this x ATR
// A gap far enough away cannot reach into a short trade, and without
// this a single wide gap left behind blocks every signal indefinitely.
// One ATR is the default because that is roughly how far these trades
// actually run against themselves before resolving - measured average
// adverse excursion was 2.18 against an M1 ATR of 2.09. A gap beyond
// that is not what takes a thin stop out.
input double   InpFvgMaxDistAtr        = 1.00;  // ignore gaps further than this x ATR. 0 = no limit
enum ENUM_FVG_FILL
{
   FVG_FILL_TOUCH = 0,   // any trade back into the band counts as filled
   FVG_FILL_FULL  = 1    // the band must be covered end to end
};
input ENUM_FVG_FILL InpFvgFillMode     = FVG_FILL_TOUCH;
input bool     InpDrawFvgBoxes         = true;  // shade the live gaps on the chart
input color    InpFvgBullColor         = clrGold;
input color    InpFvgBearColor         = clrPlum;
input bool     InpFvgMutesAlert        = true;  // stay silent when a gap blocks the signal

input bool     InpShowDashboard        = true;
input int      InpDashX               = 330;
input int      InpDashY               = 35;
input int      InpDashFontSize        = 9;
input bool     InpEnableSoundAlert    = true;
input string   InpBuySound            = "alert.wav";
input string   InpSellSound           = "alert2.wav";
input bool     InpEnablePopupAlert    = true;
input bool     InpEnablePushAlert     = false;

input color    InpFastColor            = clrLime;
input color    InpMidColor             = clrRed;
input color    InpSlowColor            = clrBlue;

//--- Indicator buffers
double FastBuffer[], MidBuffer[], SlowBuffer[], BuyBuffer[], SellBuffer[];

//--- EMA/ATR handles
int hFast = INVALID_HANDLE, hMid = INVALID_HANDLE, hSlow = INVALID_HANDLE, hATR = INVALID_HANDLE;
int hMtfFast1 = INVALID_HANDLE, hMtfMid1 = INVALID_HANDLE, hMtfSlow1 = INVALID_HANDLE;
int hMtfFast2 = INVALID_HANDLE, hMtfMid2 = INVALID_HANDLE, hMtfSlow2 = INVALID_HANDLE;
int hMtfFast3 = INVALID_HANDLE, hMtfMid3 = INVALID_HANDLE, hMtfSlow3 = INVALID_HANDLE;

//--- Dashboard object prefix
string PREFIX = "ARUNPRO9_";

//--- Live panel origin. Starts at the inputs, then follows the title
//--- label when it is dragged. X grows leftwards from the right edge.
int gDashX = 0, gDashY = 0;

//--- column offsets inside a row, relative to gDashX
#define COL_KEY   185     // row label
#define COL_VAL    20     // row value, and the first of the three angles
#define COL_STEP   60     // the angles step rightwards, so X decreases
datetime lastBuyAlertBar = 0, lastSellAlertBar = 0;

//--- Helpers
string TFText(ENUM_TIMEFRAMES tf)
{
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
}
string PriceText(double v)
{
   if(v==EMPTY_VALUE || !MathIsValidNumber(v)) return "N/A";
   return DoubleToString(v,_Digits);
}
string DistText(double v,double atr)
{
   if(v==EMPTY_VALUE || !MathIsValidNumber(v)) return "N/A";
   double x=(atr>0.0 ? v/atr : 0.0);
   return DoubleToString(v,_Digits)+" ("+DoubleToString(x,2)+"x ATR)";
}
string TrendText(int v) { return v>0 ? "Bull" : "Bear"; }
string DirectionText(double a)
{
   if(!MathIsValidNumber(a)) return "";
   if(a>90.0) return "↑";
   if(a<90.0) return "↓";
   return "→";
}
color DirectionColor(double a)
{
   if(!MathIsValidNumber(a)) return clrGray;
   if(a>90.0) return clrGreen;
   if(a<90.0) return clrRed;
   return clrOrange;
}
//--- Green above 90, red at or below it. Grey when the angle is not
//--- computable yet (not enough bars for the lookback).
color AngleColor(double a)
{
   if(a==EMPTY_VALUE || !MathIsValidNumber(a)) return clrGray;
   return (a>90.0) ? clrGreen : clrRed;
}
string AngleText(string tag,double a)
{
   if(a==EMPTY_VALUE || !MathIsValidNumber(a)) return tag+" --";
   return tag+" "+DoubleToString(a,1);
}
color ConfidenceColor(int wins,int count)
{
   if(count<=0) return clrGray;
   if(wins >= (int)MathCeil(count*0.80)) return clrGreen;
   if(wins >= (int)MathCeil(count*0.60)) return clrOrange;
   return clrRed;
}
string ConfidenceText(int wins,int count)
{
   return count<=0 ? "N/A" : IntegerToString(wins)+"/"+IntegerToString(count);
}
void DeleteDashboard()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX)==0) ObjectDelete(0,n);
   }
}
void LabelCreate(string name,string text,int x,int y,color clr,int fs,bool bold=false,bool selectable=false)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetString(0,name,OBJPROP_FONT,bold ? "Arial Bold" : "Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,!selectable);
}
void DashRow(int &r,string key,string value,color valueColor=clrBlack,bool boldValue=false)
{
   int y=gDashY+28+r*20;
   LabelCreate(PREFIX+"K"+IntegerToString(r),key,gDashX+COL_KEY,y,clrBlack,InpDashFontSize);
   LabelCreate(PREFIX+"V"+IntegerToString(r),value,gDashX+COL_VAL,y,valueColor,InpDashFontSize,boldValue);
   r++;
}

//--- The three angles on one row, each coloured on its own. They need
//--- separate objects because a label carries a single colour.
//--- X grows leftwards from the right edge, so Fast sits leftmost.
void DashRowAngles(int &r,double fa,double ma,double sa)
{
   int y=gDashY+28+r*20;
   LabelCreate(PREFIX+"K"+IntegerToString(r),"ANGLE",gDashX+COL_KEY,y,clrBlack,InpDashFontSize);
   //--- first angle shares the value column with every other row, the
   //--- other two step rightwards from it
   LabelCreate(PREFIX+"ANG_F",AngleText("F",fa),gDashX+COL_VAL,            y,AngleColor(fa),InpDashFontSize,true);
   LabelCreate(PREFIX+"ANG_M",AngleText("M",ma),gDashX+COL_VAL-COL_STEP,   y,AngleColor(ma),InpDashFontSize,true);
   LabelCreate(PREFIX+"ANG_S",AngleText("S",sa),gDashX+COL_VAL-2*COL_STEP, y,AngleColor(sa),InpDashFontSize,true);
   r++;
}

//--- Seconds left on the forming candle. Driven by OnTimer rather than
//--- OnCalculate, so it keeps counting when no ticks arrive.
int gCountdownY = -1;

long SecondsToCandleClose()
{
   int per=PeriodSeconds(PERIOD_CURRENT);
   if(per<=0) return -1;
   datetime t0=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t0==0) return -1;
   long rem=(long)(t0+per)-(long)TimeCurrent();
   if(rem<0)   rem=0;
   if(rem>per) rem=per;
   return rem;
}
string CountdownText()
{
   long rem=SecondsToCandleClose();
   if(rem<0) return "--";
   int h=(int)(rem/3600), m=(int)((rem%3600)/60), sec=(int)(rem%60);
   if(h>0) return StringFormat("%d:%02d:%02d",h,m,sec);
   return StringFormat("%02d:%02d",m,sec);
}
color CountdownColor()
{
   long rem=SecondsToCandleClose();
   if(rem<0)  return clrGray;
   if(rem<=5) return clrRed;
   if(rem<=15) return clrOrange;
   return clrBlack;
}
void DrawCountdown(int y)
{
   LabelCreate(PREFIX+"KCD","CANDLE CLOSE",gDashX+COL_KEY,y,clrBlack,InpDashFontSize);
   LabelCreate(PREFIX+"VCD",CountdownText(),gDashX+COL_VAL,y,CountdownColor(),InpDashFontSize,true);
}

//--- Copy handle data
bool CopySeries(int handle,int count,double &arr[])
{
   ArraySetAsSeries(arr,true);
   int n=CopyBuffer(handle,0,0,count,arr);
   return n>=count;
}
double Highest(const double &a[],int start,int len)
{
   double x=-DBL_MAX;
   for(int i=start;i<start+len && i<ArraySize(a);i++) x=MathMax(x,a[i]);
   return x;
}
double Lowest(const double &a[],int start,int len)
{
   double x=DBL_MAX;
   for(int i=start;i<start+len && i<ArraySize(a);i++) x=MathMin(x,a[i]);
   return x;
}
double MedianFromArray(double &a[])
{
   int n=ArraySize(a);
   if(n<=0) return EMPTY_VALUE;
   ArraySort(a);
   if((n % 2) != 0) return a[n/2];
   return (a[n/2-1]+a[n/2])/2.0;
}
int MTFTrend(int handleMid,int handleSlow,datetime t)
{
   int shift=iBarShift(_Symbol,(ENUM_TIMEFRAMES)Period(),t,false);
   double m[1],s[1];
   if(CopyBuffer(handleMid,0,0,1,m)<1 || CopyBuffer(handleSlow,0,0,1,s)<1) return 0;
   return m[0]>s[0] ? 1 : -1;
}
int MTFTrendAtTime(int hm,int hs,ENUM_TIMEFRAMES tf,datetime t)
{
   int sh=iBarShift(_Symbol,tf,t,false);
   if(sh<0) return 0;
   double m[1],s[1];
   if(CopyBuffer(hm,0,sh,1,m)<1 || CopyBuffer(hs,0,sh,1,s)<1) return 0;
   return m[0]>s[0] ? 1 : -1;
}
bool GetMTFAlignment(datetime t,int &t1,int &t2,int &t3)
{
   t1=MTFTrendAtTime(hMtfMid1,hMtfSlow1,InpMTF1,t);
   t2=MTFTrendAtTime(hMtfMid2,hMtfSlow2,InpMTF2,t);
   t3=MTFTrendAtTime(hMtfMid3,hMtfSlow3,InpMTF3,t);
   return (t1==1 && t2==1 && t3==1) || (t1==-1 && t2==-1 && t3==-1);
}

//+------------------------------------------------------------------+
//| FAIR VALUE GAP                                                   |
//|                                                                  |
//| Three candles, the outer two not overlapping. Taking i as the     |
//| newest of the triple:                                            |
//|   bullish  low[i]  > high[i+2]   band = high[i+2] .. low[i]       |
//|   bearish  high[i] < low[i+2]    band = high[i]   .. low[i+2]     |
//|                                                                  |
//| WHICH SIGNAL A GAP THREATENS                                     |
//|   A bullish gap is left BELOW price, because price rose away from |
//|   it. Filling it means falling. So an unfilled bullish gap is     |
//|   what threatens a fresh BUY - not a SELL. A bearish gap sits     |
//|   above and threatens a SELL. The gap's own direction is          |
//|   therefore the direction of the signal it warns about, which is  |
//|   why nothing here takes a separate "side" argument.              |
//|                                                                  |
//| A gap is filled once later bars trade into the band - the whole   |
//| band under FVG_FILL_FULL, any part of it under FVG_FILL_TOUCH.    |
//| Bar 0 counts: the guard has to reflect what price is doing now.   |
//+------------------------------------------------------------------+
bool FvgAt(int i,int dir,double atr,double &lo,double &hi)
{
   lo=0.0; hi=0.0;
   if(atr<=0.0 || dir==0 || i<1) return false;

   double hA=iHigh(_Symbol,PERIOD_CURRENT,i+2), lA=iLow(_Symbol,PERIOD_CURRENT,i+2);
   double hC=iHigh(_Symbol,PERIOD_CURRENT,i),   lC=iLow(_Symbol,PERIOD_CURRENT,i);
   if(hA<=0.0||lA<=0.0||hC<=0.0||lC<=0.0) return false;

   if(dir>0) { if(lC<=hA) return false; lo=hA; hi=lC; }
   else      { if(hC>=lA) return false; lo=hC; hi=lA; }

   if(hi-lo < InpFvgMinAtr*atr) return false;

   //--- what every bar since, the forming one included, did to the band
   double mn=DBL_MAX, mx=-DBL_MAX;
   for(int j=0;j<i;j++)
   {
      double l=iLow(_Symbol,PERIOD_CURRENT,j), h=iHigh(_Symbol,PERIOD_CURRENT,j);
      if(l>0.0) mn=MathMin(mn,l);
      if(h>0.0) mx=MathMax(mx,h);
   }
   bool filled;
   if(dir>0) filled=(InpFvgFillMode==FVG_FILL_FULL) ? (mn<=lo) : (mn<hi);
   else      filled=(InpFvgFillMode==FVG_FILL_FULL) ? (mx>=hi) : (mx>lo);
   return !filled;
}

//--- The nearest unfilled gap of direction dir.
//---
//--- dNear is how far price must travel to touch the band, dFar how far
//--- to cover it end to end. The pair is the point: dNear says whether
//--- the detour starts inside your stop, dFar whether the whole of it
//--- fits. One number alone cannot answer that.
struct FvgHit
{
   bool   found;
   double dNear, dFar;
   double widthAtr;
   double lo, hi;
   int    age;        // bars back to the newest candle of the triple
};

FvgHit NearestUnfilledFvg(int dir,double atr)
{
   FvgHit h;
   h.found=false; h.dNear=0.0; h.dFar=0.0; h.widthAtr=0.0;
   h.lo=0.0; h.hi=0.0; h.age=0;
   if(!InpUseFvgGuard) return h;

   double px=iClose(_Symbol,PERIOD_CURRENT,0);
   if(px<=0.0) return h;

   int    n=MathMax(3,InpFvgLookback);
   double best=DBL_MAX, lo=0.0, hi=0.0;

   for(int i=1;i<=n;i++)
   {
      if(!FvgAt(i,dir,atr,lo,hi)) continue;

      double dn=(dir>0) ? (px-hi) : (lo-px);
      double df=(dir>0) ? (px-lo) : (hi-px);
      if(dn<0.0) dn=0.0;
      if(df<0.0) df=0.0;

      //--- too far to reach into a trade of this length
      if(InpFvgMaxDistAtr>0.0 && atr>0.0 && dn>InpFvgMaxDistAtr*atr) continue;

      if(dn<best)
      {
         best=dn;
         h.found=true; h.dNear=dn; h.dFar=df;
         h.widthAtr=(atr>0.0 ? (hi-lo)/atr : 0.0);
         h.lo=lo; h.hi=hi; h.age=i;
      }
   }
   return h;
}

void DeleteFvgBoxes()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX+"FVG_")==0) ObjectDelete(0,n);
   }
}

//--- Redrawn from scratch each pass: a gap that has just been filled
//--- must disappear, and tracking that incrementally is more state
//--- than a dozen rectangles are worth.
void DrawFvgBoxes(double atr)
{
   DeleteFvgBoxes();
   if(!InpDrawFvgBoxes || !InpUseFvgGuard || atr<=0.0) return;

   datetime tRight=iTime(_Symbol,PERIOD_CURRENT,0);
   int n=MathMax(3,InpFvgLookback), drawn=0;

   for(int i=1;i<=n && drawn<16;i++)
      for(int d=1;d>=-1;d-=2)
      {
         double lo=0.0,hi=0.0;
         if(!FvgAt(i,d,atr,lo,hi)) continue;
         datetime tLeft=iTime(_Symbol,PERIOD_CURRENT,i+2);
         if(tLeft==0) continue;
         string nm=PREFIX+"FVG_"+IntegerToString(i)+"_"+IntegerToString(d);
         if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE,0,tLeft,lo,tRight,hi);
         ObjectSetInteger(0,nm,OBJPROP_TIME,0,tLeft);
         ObjectSetDouble (0,nm,OBJPROP_PRICE,0,lo);
         ObjectSetInteger(0,nm,OBJPROP_TIME,1,tRight);
         ObjectSetDouble (0,nm,OBJPROP_PRICE,1,hi);
         ObjectSetInteger(0,nm,OBJPROP_COLOR,(d>0?InpFvgBullColor:InpFvgBearColor));
         ObjectSetInteger(0,nm,OBJPROP_FILL,true);
         ObjectSetInteger(0,nm,OBJPROP_BACK,true);
         ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
         drawn++;
      }
}

void AlertSignal(bool buy,datetime barTime,double price,bool blocked)
{
   string side=buy ? "BUY" : "SELL";
   if(buy && lastBuyAlertBar==barTime) return;
   if(!buy && lastSellAlertBar==barTime) return;
   if(buy) lastBuyAlertBar=barTime; else lastSellAlertBar=barTime;

   string msg="ARUN PRO "+side+" on "+_Symbol+" @ "+DoubleToString(price,_Digits);
   if(blocked) msg+="  [FVG UNFILLED - do not trade]";

   //--- a blocked signal is one you have decided not to take, so the
   //--- default is to say nothing rather than train you to ignore it
   if(blocked && InpFvgMutesAlert) return;

   if(InpEnablePopupAlert) Alert(msg);
   if(InpEnableSoundAlert) PlaySound(buy ? InpBuySound : InpSellSound);
   if(InpEnablePushAlert) SendNotification(msg);
}

//--- Confidence calculation, matching Pine's completed-trade concept.
// Entry is at the setup bar CLOSE. MFE begins on the following bar.
// A trade finishes on opposite Fast/Mid or Mid/Slow cross, or window expiry.
void CalculateConfidence(const datetime &time[],const double &high[],const double &low[],
                         int rates_total,int startShift,int &buyCount,int &buyWins,
                         double &buyAvg,double &buyMax,double &buyMedian,
                         int &sellCount,int &sellWins,double &sellAvg,double &sellMax,double &sellMedian)
{
   double buyMFE[],buyTGT[],sellMFE[],sellTGT[];
   ArrayResize(buyMFE,0); ArrayResize(buyTGT,0); ArrayResize(sellMFE,0); ArrayResize(sellTGT,0);

   bool active=false; int dir=0,bars=0; double entry=0,mfe=0,target=0;
   int newest=startShift;
   // Walk from older history toward the current completed bar.
   for(int i=rates_total-2;i>=newest;i--)
   {
      double atr=0.0;
      double av[1];
      if(CopyBuffer(hATR,0,i,1,av)>0) atr=av[0];
      if(atr<=0) atr=_Point;

      bool bullCross=(FastBuffer[i]>MidBuffer[i] && FastBuffer[i+1]<=MidBuffer[i+1]);
      bool bearCross=(FastBuffer[i]<MidBuffer[i] && FastBuffer[i+1]>=MidBuffer[i+1]);
      bool msBull=(MidBuffer[i]>SlowBuffer[i] && MidBuffer[i+1]<=SlowBuffer[i+1]);
      bool msBear=(MidBuffer[i]<SlowBuffer[i] && MidBuffer[i+1]>=SlowBuffer[i+1]);

      if(active)
      {
         bars++;
         if(dir==1)
         {
            mfe=MathMax(mfe,high[i]-entry);
            if(bearCross || msBear || bars>=InpPotentialWindowBars)
            {
               int n=ArraySize(buyMFE);
               if(n<InpConfidenceLookback)
               {
                  ArrayResize(buyMFE,n+1); ArrayResize(buyTGT,n+1);
                  buyMFE[n]=MathMax(0.0,mfe); buyTGT[n]=target;
               }
               else
               {
                  for(int k=1;k<n;k++){buyMFE[k-1]=buyMFE[k];buyTGT[k-1]=buyTGT[k];}
                  buyMFE[n-1]=MathMax(0.0,mfe); buyTGT[n-1]=target;
               }
               active=false; dir=0; bars=0; entry=0;mfe=0;target=0;
            }
         }
         else
         {
            mfe=MathMax(mfe,entry-low[i]);
            if(bullCross || msBull || bars>=InpPotentialWindowBars)
            {
               int n=ArraySize(sellMFE);
               if(n<InpConfidenceLookback)
               {
                  ArrayResize(sellMFE,n+1); ArrayResize(sellTGT,n+1);
                  sellMFE[n]=MathMax(0.0,mfe); sellTGT[n]=target;
               }
               else
               {
                  for(int k=1;k<n;k++){sellMFE[k-1]=sellMFE[k];sellTGT[k-1]=sellTGT[k];}
                  sellMFE[n-1]=MathMax(0.0,mfe); sellTGT[n-1]=target;
               }
               active=false; dir=0; bars=0; entry=0;mfe=0;target=0;
            }
         }
      }

      if(!active && time[i]>=InpAnalysisStartDate)
      {
         bool above=false,below=false;
         if(InpCandleSideMode==CANDLE_FULL){above=low[i]>SlowBuffer[i];below=high[i]<SlowBuffer[i];}
         else if(InpCandleSideMode==CANDLE_BODY){above=MathMin(iOpen(_Symbol,Period(),i),iClose(_Symbol,Period(),i))>SlowBuffer[i];below=MathMax(iOpen(_Symbol,Period(),i),iClose(_Symbol,Period(),i))<SlowBuffer[i];}
         else {above=iClose(_Symbol,Period(),i)>SlowBuffer[i];below=iClose(_Symbol,Period(),i)<SlowBuffer[i];}

         double fA=EMPTY_VALUE,mA=EMPTY_VALUE,sA=EMPTY_VALUE;
         if(i+InpAngleLookback<rates_total)
         {
            double atrSafe=atr;
            fA=90.0+MathArctan(((FastBuffer[i]-FastBuffer[i+InpAngleLookback])/InpAngleLookback)/atrSafe)*180.0/M_PI;
            mA=90.0+MathArctan(((MidBuffer[i]-MidBuffer[i+InpAngleLookback])/InpAngleLookback)/atrSafe)*180.0/M_PI;
            sA=90.0+MathArctan(((SlowBuffer[i]-SlowBuffer[i+InpAngleLookback])/InpAngleLookback)/atrSafe)*180.0/M_PI;
         }
         bool angBull=fA>90&&mA>90&&sA>90, angBear=fA<90&&mA<90&&sA<90;
         int a1,a2,a3; GetMTFAlignment(time[i],a1,a2,a3);
         bool mtfBull=a1==1&&a2==1&&a3==1, mtfBear=a1==-1&&a2==-1&&a3==-1;
         bool buy=bullCross&&above&&(!InpUseMTFFilter||mtfBull)&&(!InpUseAngleFilter||angBull);
         bool sell=bearCross&&below&&(!InpUseMTFFilter||mtfBear)&&(!InpUseAngleFilter||angBear);

         if(buy||sell)
         {
            active=true;dir=buy?1:-1;entry=iClose(_Symbol,Period(),i);mfe=0;bars=0;
            target=(InpTargetMode==TARGET_ATR_MULTIPLE ? InpTargetAtrMult*atr : InpTargetPoints);
         }
      }
   }

   buyCount=ArraySize(buyMFE); sellCount=ArraySize(sellMFE);
   buyWins=0;sellWins=0;buyAvg=0;sellAvg=0;buyMax=EMPTY_VALUE;sellMax=EMPTY_VALUE;
   double bmed[],smed[];
   ArrayResize(bmed,buyCount);ArrayResize(smed,sellCount);
   for(int i=0;i<buyCount;i++){if(buyMFE[i]>=buyTGT[i])buyWins++;buyAvg+=buyMFE[i];bmed[i]=buyMFE[i];buyMax=(buyMax==EMPTY_VALUE?buyMFE[i]:MathMax(buyMax,buyMFE[i]));}
   for(int i=0;i<sellCount;i++){if(sellMFE[i]>=sellTGT[i])sellWins++;sellAvg+=sellMFE[i];smed[i]=sellMFE[i];sellMax=(sellMax==EMPTY_VALUE?sellMFE[i]:MathMax(sellMax,sellMFE[i]));}
   if(buyCount>0)buyAvg/=buyCount;
   if(sellCount>0)sellAvg/=sellCount;
   buyMedian=MedianFromArray(bmed);sellMedian=MedianFromArray(smed);
}

void UpdateDashboard(int shift,const datetime &time[],const double &high[],const double &low[],const double &open[],const double &close[])
{
   if(!InpShowDashboard) return;

   // Keep all calculations available internally, but show only the information
   // needed for a fast trading decision.
   double atr=0,a[1];
   if(CopyBuffer(hATR,0,shift,1,a)>0) atr=a[0];
   if(atr<=0) atr=_Point;

   bool bull=MidBuffer[shift]>SlowBuffer[shift];
   bool bear=MidBuffer[shift]<SlowBuffer[shift];

   int t1,t2,t3;
   GetMTFAlignment(time[shift],t1,t2,t3);
   bool mtfBull=t1==1&&t2==1&&t3==1;
   bool mtfBear=t1==-1&&t2==-1&&t3==-1;
   bool mtfAligned=mtfBull||mtfBear;

   double fa=EMPTY_VALUE,ma=EMPTY_VALUE,sa=EMPTY_VALUE;
   if(shift+InpAngleLookback<ArraySize(FastBuffer))
   {
      fa=90+MathArctan(((FastBuffer[shift]-FastBuffer[shift+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
      ma=90+MathArctan(((MidBuffer[shift]-MidBuffer[shift+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
      sa=90+MathArctan(((SlowBuffer[shift]-SlowBuffer[shift+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
   }

   bool angleBull=fa>90&&ma>90&&sa>90;
   bool angleBear=fa<90&&ma<90&&sa<90;
   bool angleAligned=angleBull||angleBear;

   int bc,bw,sc,sw;
   double ba,bx,bmed,saAvg,sx,smed;
   CalculateConfidence(time,high,low,ArraySize(time),MathMin(ArraySize(time)-2,2000),
                       bc,bw,ba,bx,bmed,sc,sw,saAvg,sx,smed);

   bool buySignal=(BuyBuffer[shift]!=EMPTY_VALUE);
   bool sellSignal=(SellBuffer[shift]!=EMPTY_VALUE);

   //--- the guard. Both directions are evaluated every pass so the row
   //--- is informative while waiting, not only once a signal fires.
   FvgHit gb = NearestUnfilledFvg( 1,atr);
   FvgHit gs = NearestUnfilledFvg(-1,atr);
   bool blocked = (buySignal && gb.found) || (sellSignal && gs.found);

   string fvgText; color fvgColor;
   if(!InpUseFvgGuard) { fvgText="OFF"; fvgColor=clrGray; }
   else if(gb.found && gs.found)
   {
      fvgText=StringFormat("BOTH  B %s  S %s",
                           DoubleToString(gb.dFar,_Digits),DoubleToString(gs.dFar,_Digits));
      fvgColor=clrRed;
   }
   else if(gb.found)
   {
      //--- the pull is down: the dip runs from dNear to dFar
      fvgText=StringFormat("BLOCKS BUY  %s-%s  %db",
                           DoubleToString(gb.dNear,_Digits),
                           DoubleToString(gb.dFar,_Digits), gb.age);
      fvgColor=clrRed;
   }
   else if(gs.found)
   {
      fvgText=StringFormat("BLOCKS SELL  %s-%s  %db",
                           DoubleToString(gs.dNear,_Digits),
                           DoubleToString(gs.dFar,_Digits), gs.age);
      fvgColor=clrRed;
   }
   else { fvgText="CLEAR"; fvgColor=clrGreen; }

   //--- red only when it blocks the signal actually on the table
   if(InpUseFvgGuard && (gb.found||gs.found) && !blocked) fvgColor=clrOrange;

   string trend=bull?"BULLISH":bear?"BEARISH":"NEUTRAL";
   string setup=buySignal?"BUY":sellSignal?"SELL":"WAIT";
   if(blocked) setup+="  x FVG";
   string mtfText=TFText(InpMTF1)+" "+(t1>0?"OK":"-")+"   "+
                  TFText(InpMTF2)+" "+(t2>0?"OK":"-")+"   "+
                  TFText(InpMTF3)+" "+(t3>0?"OK":"-");
   string mtfStatus=mtfBull?"BULL":mtfBear?"BEAR":"MIXED";
   string angleStatus=angleBull?"ALIGNED UP":angleBear?"ALIGNED DN":"MIXED";

   // No background panel or header bar: the rectangles anchor from the
   // right corner while the labels anchor from their own left edge, so
   // the box never lined up behind the text. Text straight on the chart.
   //--- the title doubles as the drag handle, so it is the one object
   //--- on the panel that is selectable
   LabelCreate(PREFIX+"TITLE","ARUN PRO v9",gDashX+COL_KEY,gDashY+4,clrBlack,11,true,true);

   int r=0;
   DashRow(r,"TREND",trend,bull?clrGreen:bear?clrRed:clrBlack,true);
   DashRow(r,"SETUP",setup,
           blocked ? clrOrange : (buySignal?clrGreen:sellSignal?clrRed:clrBlack),true);
   DashRow(r,"FVG",fvgText,fvgColor,true);
   DashRow(r,"MTF",mtfText,mtfAligned?clrGreen:clrRed,false);
   DashRow(r,"MTF STATUS",mtfStatus,mtfBull?clrGreen:mtfBear?clrRed:clrOrange,true);
   DashRow(r,"ANGLES",angleStatus,angleAligned?clrGreen:clrOrange,true);
   DashRowAngles(r,fa,ma,sa);
   DashRow(r,"BUY CONF",ConfidenceText(bw,bc),ConfidenceColor(bw,bc),true);
   DashRow(r,"SELL CONF",ConfidenceText(sw,sc),ConfidenceColor(sw,sc),true);
   DashRow(r,"CHART",TFText((ENUM_TIMEFRAMES)Period()),clrBlack,false);

   gCountdownY=gDashY+28+r*20;
   DrawCountdown(gCountdownY);
   r++;
}

//--- Ticks can be minutes apart on a quiet chart, so the countdown is
//--- refreshed on its own one second timer instead of with the panel.
void OnTimer()
{
   if(!InpShowDashboard || gCountdownY<0) return;
   LabelCreate(PREFIX+"VCD",CountdownText(),gDashX+COL_VAL,gCountdownY,
               CountdownColor(),InpDashFontSize,true);
   ChartRedraw(0);
}

//--- Move every panel object by the same delta. Used when the title is
//--- dragged: MT5 moves the dragged object itself, the rest follow here.
void ShiftDashboard(int dx,int dy)
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX)!=0) continue;
      if(n==PREFIX+"TITLE") continue;
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,(int)ObjectGetInteger(0,n,OBJPROP_XDISTANCE)+dx);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,(int)ObjectGetInteger(0,n,OBJPROP_YDISTANCE)+dy);
   }
}

//--- Dragging the title moves the whole panel. The new origin is kept
//--- in gDashX / gDashY so the next redraw rebuilds it in place.
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_DRAG) return;
   if(sparam!=PREFIX+"TITLE")     return;

   int nx=(int)ObjectGetInteger(0,sparam,OBJPROP_XDISTANCE);
   int ny=(int)ObjectGetInteger(0,sparam,OBJPROP_YDISTANCE);
   int dx=nx-(gDashX+COL_KEY);
   int dy=ny-(gDashY+4);
   if(dx==0 && dy==0) return;

   gDashX+=dx; gDashY+=dy;
   if(gCountdownY>=0) gCountdownY+=dy;
   ShiftDashboard(dx,dy);
   ChartRedraw(0);
}

//--- initialization
int OnInit()
{
   SetIndexBuffer(0,FastBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,MidBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,SlowBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,SellBuffer,INDICATOR_DATA);

   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpFastColor);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpMidColor);
   PlotIndexSetInteger(2,PLOT_LINE_COLOR,InpSlowColor);
   PlotIndexSetInteger(3,PLOT_ARROW,233);
   PlotIndexSetInteger(4,PLOT_ARROW,234);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(4,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   hFast=iMA(_Symbol,PERIOD_CURRENT,InpFastLen,0,MODE_EMA,PRICE_CLOSE);
   hMid=iMA(_Symbol,PERIOD_CURRENT,InpMidLen,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(_Symbol,PERIOD_CURRENT,InpSlowLen,0,MODE_EMA,PRICE_CLOSE);
   hATR=iATR(_Symbol,PERIOD_CURRENT,InpATRLen);

   hMtfMid1=iMA(_Symbol,InpMTF1,InpMidLen,0,MODE_EMA,PRICE_CLOSE);
   hMtfSlow1=iMA(_Symbol,InpMTF1,InpSlowLen,0,MODE_EMA,PRICE_CLOSE);
   hMtfMid2=iMA(_Symbol,InpMTF2,InpMidLen,0,MODE_EMA,PRICE_CLOSE);
   hMtfSlow2=iMA(_Symbol,InpMTF2,InpSlowLen,0,MODE_EMA,PRICE_CLOSE);
   hMtfMid3=iMA(_Symbol,InpMTF3,InpMidLen,0,MODE_EMA,PRICE_CLOSE);
   hMtfSlow3=iMA(_Symbol,InpMTF3,InpSlowLen,0,MODE_EMA,PRICE_CLOSE);

   if(hFast==INVALID_HANDLE||hMid==INVALID_HANDLE||hSlow==INVALID_HANDLE||hATR==INVALID_HANDLE) return INIT_FAILED;
   ArraySetAsSeries(FastBuffer,true);ArraySetAsSeries(MidBuffer,true);ArraySetAsSeries(SlowBuffer,true);
   ArraySetAsSeries(BuyBuffer,true);ArraySetAsSeries(SellBuffer,true);

   IndicatorSetString(INDICATOR_SHORTNAME,"ARUN PRO v9 MT5");
   gDashX=InpDashX; gDashY=InpDashY;
   gCountdownY=-1;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   int hs[]={hFast,hMid,hSlow,hATR,hMtfMid1,hMtfSlow1,hMtfMid2,hMtfSlow2,hMtfMid3,hMtfSlow3};
   for(int i=0;i<ArraySize(hs);i++) if(hs[i]!=INVALID_HANDLE) IndicatorRelease(hs[i]);
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   int need=MathMax(MathMax(InpSlowLen,InpATRLen),InpAngleLookback)+InpPotentialWindowBars+20;
   if(rates_total<need) return 0;

   ArraySetAsSeries(time,true);ArraySetAsSeries(open,true);ArraySetAsSeries(high,true);ArraySetAsSeries(low,true);ArraySetAsSeries(close,true);

   if(CopyBuffer(hFast,0,0,rates_total,FastBuffer)<rates_total) return prev_calculated;
   if(CopyBuffer(hMid,0,0,rates_total,MidBuffer)<rates_total) return prev_calculated;
   if(CopyBuffer(hSlow,0,0,rates_total,SlowBuffer)<rates_total) return prev_calculated;

   ArrayInitialize(BuyBuffer,EMPTY_VALUE);
   ArrayInitialize(SellBuffer,EMPTY_VALUE);

   int limit=rates_total-InpSlowLen-InpAngleLookback-2;
   if(limit>2000) limit=2000;

   for(int i=limit;i>=1;i--)
   {
      bool bullCross=FastBuffer[i]>MidBuffer[i] && FastBuffer[i+1]<=MidBuffer[i+1];
      bool bearCross=FastBuffer[i]<MidBuffer[i] && FastBuffer[i+1]>=MidBuffer[i+1];

      bool above=false,below=false;
      if(InpCandleSideMode==CANDLE_FULL){above=low[i]>SlowBuffer[i];below=high[i]<SlowBuffer[i];}
      else if(InpCandleSideMode==CANDLE_BODY){above=MathMin(open[i],close[i])>SlowBuffer[i];below=MathMax(open[i],close[i])<SlowBuffer[i];}
      else {above=close[i]>SlowBuffer[i];below=close[i]<SlowBuffer[i];}

      double atr=0,a[1];if(CopyBuffer(hATR,0,i,1,a)>0)atr=a[0];if(atr<=0)atr=_Point;
      double fa=90+MathArctan(((FastBuffer[i]-FastBuffer[i+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
      double ma=90+MathArctan(((MidBuffer[i]-MidBuffer[i+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
      double sa=90+MathArctan(((SlowBuffer[i]-SlowBuffer[i+InpAngleLookback])/InpAngleLookback)/atr)*180/M_PI;
      bool angBull=fa>90&&ma>90&&sa>90,angBear=fa<90&&ma<90&&sa<90;

      int t1,t2,t3;GetMTFAlignment(time[i],t1,t2,t3);
      bool mtfBull=t1==1&&t2==1&&t3==1,mtfBear=t1==-1&&t2==-1&&t3==-1;

      bool buy=bullCross&&above&&(!InpUseMTFFilter||mtfBull)&&(!InpUseAngleFilter||angBull);
      bool sell=bearCross&&below&&(!InpUseMTFFilter||mtfBear)&&(!InpUseAngleFilter||angBear);

      if(time[i]>=InpAnalysisStartDate)
      {
         if(InpShowSignals && buy) BuyBuffer[i]=low[i]-MathMax(atr*0.20,10*_Point);
         if(InpShowSignals && sell) SellBuffer[i]=high[i]+MathMax(atr*0.20,10*_Point);
      }
   }

   // Only the closed candle (shift 1) can generate a live alert.
   if(time[1]>=InpAnalysisStartDate)
   {
      double atrNow=0,an[1];
      if(CopyBuffer(hATR,0,1,1,an)>0) atrNow=an[0];
      if(atrNow<=0) atrNow=_Point;
      if(BuyBuffer[1]!=EMPTY_VALUE)
      {
         FvgHit g=NearestUnfilledFvg(1,atrNow);
         AlertSignal(true,time[1],close[1],g.found);
      }
      if(SellBuffer[1]!=EMPTY_VALUE)
      {
         FvgHit g=NearestUnfilledFvg(-1,atrNow);
         AlertSignal(false,time[1],close[1],g.found);
      }
   }

   if(InpShowDashboard) UpdateDashboard(0,time,high,low,open,close);
   else { DeleteDashboard(); gCountdownY=-1; }

   //--- after the panel, because DeleteDashboard() clears everything
   //--- carrying the prefix, the gap rectangles included
   double atrBox=0,ab[1];
   if(CopyBuffer(hATR,0,1,1,ab)>0) atrBox=ab[0];
   if(atrBox<=0) atrBox=_Point;
   DrawFvgBoxes(atrBox);

   ChartRedraw(0);
   return rates_total;
}
