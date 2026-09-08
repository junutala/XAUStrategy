//+------------------------------------------------------------------+
//|                                                ARUN_PRO_v7.mq5   |
//| Native MT5 conversion of ARUN Indicator Pro v7 - Confidence     |
//| Engine. Signal logic is kept aligned with the supplied Pine v7. |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN PRO v7 - Native MT5 Confidence Engine"
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

#include <Canvas\Canvas.mqh>

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
input bool     InpShowPotentialStats   = false;
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

input bool     InpShowDashboard        = true;
input int      InpDashX               = 330;
input int      InpDashY               = 35;
input int      InpDashFontSize        = 9;
input bool     InpDashTransparent     = true;   // see candles through the panel
input int      InpDashOpacity         = 25;     // 0 = invisible panel, 100 = solid
input color    InpDashBgColor         = clrWhite;
input color    InpDashHeaderColor     = clrGray;
input color    InpDashBorderColor     = clrGray;
input color    InpDashTextColor       = clrBlack;
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
string PREFIX = "ARUNPRO7_";

//--- Semi-transparent dashboard background (ARGB bitmap, blends with the chart)
CCanvas DashCanvas;
bool    dashCanvasReady = false;
int     dashCanvasW = 0, dashCanvasH = 0;
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
   if(dashCanvasReady)
   {
      DashCanvas.Destroy();
      dashCanvasReady=false; dashCanvasW=0; dashCanvasH=0;
   }
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX)==0) ObjectDelete(0,n);
   }
}
void LabelCreate(string name,string text,int x,int y,color clr,int fs,bool bold=false)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetString(0,name,OBJPROP_FONT,bold ? "Arial Bold" : "Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void RectCreate(string name,int x,int y,int w,int h,color bg,color border)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void DeleteDashboardTexts()
{
   int total=ObjectsTotal(0,-1,OBJ_LABEL);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,OBJ_LABEL);
      if(StringFind(n,PREFIX)==0) ObjectDelete(0,n);
   }
}
//--- Draws the panel as an ARGB bitmap so the candles stay visible behind it.
//--- Falls back to the opaque rectangles when transparency is off or unavailable.
bool PanelCreate(int x,int y,int w,int h,int headerH)
{
   int op=InpDashOpacity;
   if(op<0)   op=0;
   if(op>100) op=100;
   uchar alpha=(uchar)MathRound(255.0*op/100.0);
   // Keep the frame and the title bar readable even at a very low body opacity.
   uchar borderAlpha=(uchar)MathMax((int)alpha,120);
   uchar headerAlpha=(uchar)MathMax((int)alpha,170);

   string name=PREFIX+"PANEL";
   if(dashCanvasReady && (dashCanvasW!=w || dashCanvasH!=h || ObjectFind(0,name)<0))
   {
      DashCanvas.Destroy();
      dashCanvasReady=false;
   }
   if(!dashCanvasReady)
   {
      if(!DashCanvas.CreateBitmapLabel(0,0,name,0,0,w,h,COLOR_FORMAT_ARGB_NORMALIZE)) return false;
      dashCanvasReady=true; dashCanvasW=w; dashCanvasH=h;
      // The chart draws objects in creation order, so rebuild the texts after
      // the panel to keep them in front of it.
      DeleteDashboardTexts();
   }

   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);

   DashCanvas.Erase(ColorToARGB(InpDashBgColor,alpha));
   DashCanvas.FillRectangle(0,0,w-1,headerH-1,ColorToARGB(InpDashHeaderColor,headerAlpha));
   DashCanvas.Rectangle(0,0,w-1,h-1,ColorToARGB(InpDashBorderColor,borderAlpha));
   DashCanvas.Update(true);
   return true;
}
void DashRow(int &r,string key,string value,color valueColor=clrBlack,bool boldValue=false)
{
   int y=InpDashY+28+r*20;
   LabelCreate(PREFIX+"K"+IntegerToString(r),key,InpDashX+185,y,InpDashTextColor,InpDashFontSize);
   LabelCreate(PREFIX+"V"+IntegerToString(r),value,InpDashX+20,y,valueColor,InpDashFontSize,boldValue);
   r++;
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

void AlertSignal(bool buy,datetime barTime,double price)
{
   string side=buy ? "BUY" : "SELL";
   if(buy && lastBuyAlertBar==barTime) return;
   if(!buy && lastSellAlertBar==barTime) return;
   if(buy) lastBuyAlertBar=barTime; else lastSellAlertBar=barTime;

   string msg="ARUN PRO "+side+" on "+_Symbol+" @ "+DoubleToString(price,_Digits);
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

   string trend=bull?"BULLISH":bear?"BEARISH":"NEUTRAL";
   string setup=buySignal?"BUY":sellSignal?"SELL":"WAIT";
   string mtfText=TFText(InpMTF1)+" "+(t1>0?"OK":"-")+"   "+
                  TFText(InpMTF2)+" "+(t2>0?"OK":"-")+"   "+
                  TFText(InpMTF3)+" "+(t3>0?"OK":"-");
   string mtfStatus=mtfBull?"BULL":mtfBear?"BEAR":"MIXED";
   string angleStatus=angleBull?"ALIGNED UP":angleBear?"ALIGNED DN":"MIXED";

   double target=(InpTargetMode==TARGET_ATR_MULTIPLE ? InpTargetAtrMult*atr : InpTargetPoints);

   // Compact panel: title + 9 essential rows.
   int rows=10;
   int panelW=320, panelH=rows*20+38, headerH=25;
   bool drawn=false;
   if(InpDashTransparent) drawn=PanelCreate(InpDashX,InpDashY,panelW,panelH,headerH);
   if(!drawn)
   {
      RectCreate(PREFIX+"BG",InpDashX,InpDashY,panelW,panelH,InpDashBgColor,InpDashBorderColor);
      RectCreate(PREFIX+"HDR",InpDashX,InpDashY,panelW,headerH,InpDashHeaderColor,InpDashBorderColor);
   }
   else
   {
      ObjectDelete(0,PREFIX+"BG");
      ObjectDelete(0,PREFIX+"HDR");
   }
   LabelCreate(PREFIX+"TITLE","ARUN PRO v7",InpDashX+20,InpDashY+4,clrWhite,11,true);

   int r=0;
   DashRow(r,"TREND",trend,bull?clrGreen:bear?clrRed:InpDashTextColor,true);
   DashRow(r,"SETUP",setup,buySignal?clrGreen:sellSignal?clrRed:InpDashTextColor,true);
   DashRow(r,"MTF",mtfText,mtfAligned?clrGreen:clrRed,false);
   DashRow(r,"MTF STATUS",mtfStatus,mtfBull?clrGreen:mtfBear?clrRed:clrOrange,true);
   DashRow(r,"ANGLES",angleStatus,angleAligned?clrGreen:clrOrange,true);
   DashRow(r,"BUY CONF",ConfidenceText(bw,bc),ConfidenceColor(bw,bc),true);
   DashRow(r,"SELL CONF",ConfidenceText(sw,sc),ConfidenceColor(sw,sc),true);
   DashRow(r,"TARGET",DistText(target,atr),InpDashTextColor,false);

   // Show the historical maximum potential for the active direction when available.
   if(buySignal && bx!=EMPTY_VALUE)
      DashRow(r,"POTENTIAL",DistText(bx,atr)+" BUY",clrGreen,false);
   else if(sellSignal && sx!=EMPTY_VALUE)
      DashRow(r,"POTENTIAL",DistText(sx,atr)+" SELL",clrRed,false);
   else
      DashRow(r,"POTENTIAL","WAIT",clrGray,false);

   DashRow(r,"CHART",TFText((ENUM_TIMEFRAMES)Period()),InpDashTextColor,false);
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

   IndicatorSetString(INDICATOR_SHORTNAME,"ARUN PRO v7 MT5");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
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
      if(BuyBuffer[1]!=EMPTY_VALUE) AlertSignal(true,time[1],close[1]);
      if(SellBuffer[1]!=EMPTY_VALUE) AlertSignal(false,time[1],close[1]);
   }

   if(InpShowDashboard) UpdateDashboard(0,time,high,low,open,close);
   else DeleteDashboard();

   ChartRedraw(0);
   return rates_total;
}
