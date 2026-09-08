//+------------------------------------------------------------------+
//|                                           ARUN_EMA_CROSS_V1.mq5  |
//| Two stage EMA cross engine.                                      |
//|   Stage 1 : Fast crosses Medium -> setup is armed, status WAIT   |
//|   Stage 2 : Fast crosses Slow   -> BUY / SELL signal             |
//| Either cross may come first, but both must happen inside the     |
//| configured window of candles (default 5).                        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "ARUN EMA CROSS V1 - two stage Fast/Mid + Fast/Slow cross"
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
#property indicator_width4  3
#property indicator_label5  "SELL"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  3

#include <Canvas\Canvas.mqh>

//--- EMA settings
input int      InpFastLen              = 7;
input int      InpMidLen               = 21;
input int      InpSlowLen              = 50;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;

//--- Cross sequence settings
input int      InpMaxBarsBetween       = 5;      // max candles between the two crosses
input bool     InpClosedBarOnly        = true;   // confirm on closed candles only (no repaint)
input int      InpMaxBarsCalc          = 3000;   // history bars to scan
input datetime InpAnalysisStartDate     = D'1970.01.01 00:00'; // ignore signals before this

//--- Display
input bool     InpShowSignals          = true;
input int      InpBuyArrowCode         = 233;
input int      InpSellArrowCode        = 234;
input int      InpATRLen               = 14;     // used only to offset the arrows
input color    InpFastColor            = clrLime;
input color    InpMidColor             = clrRed;
input color    InpSlowColor            = clrBlue;

//--- Alerts
input bool     InpEnablePopupAlert     = true;
input bool     InpEnableSoundAlert     = true;
input string   InpBuySound             = "alert.wav";
input string   InpSellSound            = "alert2.wav";
input bool     InpEnablePushAlert      = false;
input bool     InpAlertOnWait          = false;  // also alert when stage 1 arms the setup

//--- Dashboard
input bool     InpShowDashboard        = true;
input int      InpDashX                = 330;
input int      InpDashY                = 35;
input int      InpDashFontSize         = 9;
input bool     InpDashShowPanel        = false;  // draw the background box / title bar
input bool     InpDashTransparent      = true;   // see candles through the panel
input int      InpDashOpacity          = 25;     // 0 = invisible panel, 100 = solid
input color    InpDashBgColor          = clrWhite;
input color    InpDashHeaderColor      = clrGray;
input color    InpDashBorderColor      = clrGray;
input color    InpDashTextColor        = clrBlack;

//--- Indicator buffers
double FastBuffer[], MidBuffer[], SlowBuffer[], BuyBuffer[], SellBuffer[];

//--- Handles
int hFast = INVALID_HANDLE, hMid = INVALID_HANDLE, hSlow = INVALID_HANDLE, hATR = INVALID_HANDLE;

//--- Objects / state
string PREFIX = "ARUNEMAX_";
CCanvas DashCanvas;
bool    dashCanvasReady = false;
int     dashCanvasW = 0, dashCanvasH = 0;
datetime lastBuyAlertBar = 0, lastSellAlertBar = 0, lastWaitAlertBar = 0;

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
string TFText(ENUM_TIMEFRAMES tf)
{
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return s;
}
string BarsAgoText(int bars)
{
   if(bars<0) return "";
   if(bars==0) return "this bar";
   if(bars==1) return "1 bar ago";
   return IntegerToString(bars)+" bars ago";
}
string LegText(int legBar,int refBar,int dir)
{
   if(legBar<0) return "-";
   return (dir>0 ? "UP  " : "DN  ")+BarsAgoText(legBar-refBar);
}

//+------------------------------------------------------------------+
//| Chart object helpers                                             |
//+------------------------------------------------------------------+
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
void PanelDestroy()
{
   if(dashCanvasReady)
   {
      DashCanvas.Destroy();
      dashCanvasReady=false; dashCanvasW=0; dashCanvasH=0;
   }
   ObjectDelete(0,PREFIX+"BG");
   ObjectDelete(0,PREFIX+"HDR");
}
void DeleteDashboard()
{
   PanelDestroy();
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX)==0) ObjectDelete(0,n);
   }
}
//--- Draws the panel as an ARGB bitmap so the candles stay visible behind it.
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
void DashRow(int &r,string key,string value,color valueColor,bool boldValue=false)
{
   int y=InpDashY+28+r*20;
   LabelCreate(PREFIX+"K"+IntegerToString(r),key,InpDashX+185,y,InpDashTextColor,InpDashFontSize);
   LabelCreate(PREFIX+"V"+IntegerToString(r),value,InpDashX+20,y,valueColor,InpDashFontSize,boldValue);
   r++;
}

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void AlertSignal(bool buy,datetime barTime,double price)
{
   if(buy  && lastBuyAlertBar ==barTime) return;
   if(!buy && lastSellAlertBar==barTime) return;
   if(buy) lastBuyAlertBar=barTime; else lastSellAlertBar=barTime;

   string msg="ARUN EMA CROSS "+(buy?"BUY":"SELL")+" on "+_Symbol+" "+
              TFText((ENUM_TIMEFRAMES)Period())+" @ "+DoubleToString(price,_Digits);
   if(InpEnablePopupAlert) Alert(msg);
   if(InpEnableSoundAlert) PlaySound(buy ? InpBuySound : InpSellSound);
   if(InpEnablePushAlert)  SendNotification(msg);
}
void AlertWait(bool up,datetime barTime)
{
   if(!InpAlertOnWait) return;
   if(lastWaitAlertBar==barTime) return;
   lastWaitAlertBar=barTime;

   string msg="ARUN EMA CROSS WAIT ("+(up?"UP":"DOWN")+") on "+_Symbol+" "+
              TFText((ENUM_TIMEFRAMES)Period());
   if(InpEnablePopupAlert) Alert(msg);
   if(InpEnablePushAlert)  SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard(int refBar,int pendingDir,int fmBar,int fmDir,int fsBar,int fsDir,
                     int signalDir,int lastSignalDir,double lastSignalPrice,int lastSignalBar)
{
   if(!InpShowDashboard) return;

   int rows=8;
   int panelW=320, panelH=rows*20+38, headerH=25;
   bool headerBar=false;
   if(InpDashShowPanel)
   {
      if(InpDashTransparent) headerBar=PanelCreate(InpDashX,InpDashY,panelW,panelH,headerH);
      if(headerBar)
      {
         ObjectDelete(0,PREFIX+"BG");
         ObjectDelete(0,PREFIX+"HDR");
      }
      else
      {
         RectCreate(PREFIX+"BG",InpDashX,InpDashY,panelW,panelH,InpDashBgColor,InpDashBorderColor);
         RectCreate(PREFIX+"HDR",InpDashX,InpDashY,panelW,headerH,InpDashHeaderColor,InpDashBorderColor);
         headerBar=true;
      }
   }
   else PanelDestroy();

   LabelCreate(PREFIX+"TITLE","ARUN EMA CROSS V1",InpDashX+185,InpDashY+4,
               headerBar?clrWhite:InpDashTextColor,11,true);

   bool bull=FastBuffer[refBar]>MidBuffer[refBar] && MidBuffer[refBar]>SlowBuffer[refBar];
   bool bear=FastBuffer[refBar]<MidBuffer[refBar] && MidBuffer[refBar]<SlowBuffer[refBar];
   string trend=bull?"BULLISH":bear?"BEARISH":"MIXED";
   color  trendColor=bull?clrGreen:bear?clrRed:clrOrange;

   string status; color statusColor;
   if(signalDir>0)         { status="BUY";  statusColor=clrGreen; }
   else if(signalDir<0)    { status="SELL"; statusColor=clrRed;   }
   else if(pendingDir>0)   { status="WAIT (UP)";   statusColor=clrOrange; }
   else if(pendingDir<0)   { status="WAIT (DOWN)"; statusColor=clrOrange; }
   else                    { status="IDLE"; statusColor=clrGray;  }

   // Bars still available for the second cross to arrive.
   string windowText="-"; color windowColor=clrGray;
   if(signalDir==0 && pendingDir!=0)
   {
      int legBar=(fmBar>=0 ? fmBar : fsBar);
      int left=InpMaxBarsBetween-(legBar-refBar);
      if(left<0) left=0;
      windowText=IntegerToString(left)+" of "+IntegerToString(InpMaxBarsBetween)+" bars left";
      windowColor=(left>0 ? clrOrange : clrRed);
   }

   string lastText="NONE"; color lastColor=clrGray;
   if(lastSignalDir!=0)
   {
      lastText=(lastSignalDir>0?"BUY  ":"SELL  ")+DoubleToString(lastSignalPrice,_Digits)+
               "  ("+BarsAgoText(lastSignalBar-refBar)+")";
      lastColor=(lastSignalDir>0?clrGreen:clrRed);
   }

   int r=0;
   DashRow(r,"TREND",trend,trendColor,true);
   DashRow(r,"STATUS",status,statusColor,true);
   DashRow(r,"STAGE 1  FAST/MID",LegText(fmBar,refBar,fmDir),fmBar<0?clrGray:(fmDir>0?clrGreen:clrRed),false);
   DashRow(r,"STAGE 2  FAST/SLOW",LegText(fsBar,refBar,fsDir),fsBar<0?clrGray:(fsDir>0?clrGreen:clrRed),false);
   DashRow(r,"WINDOW",windowText,windowColor,false);
   DashRow(r,"LAST SIGNAL",lastText,lastColor,true);
   DashRow(r,"EMAS",IntegerToString(InpFastLen)+" / "+IntegerToString(InpMidLen)+" / "+IntegerToString(InpSlowLen),
           InpDashTextColor,false);
   DashRow(r,"CHART",TFText((ENUM_TIMEFRAMES)Period())+(InpClosedBarOnly?"  (closed bar)":"  (live bar)"),
           InpDashTextColor,false);
}

//+------------------------------------------------------------------+
//| Init / deinit                                                    |
//+------------------------------------------------------------------+
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
   PlotIndexSetInteger(3,PLOT_ARROW,InpBuyArrowCode);
   PlotIndexSetInteger(4,PLOT_ARROW,InpSellArrowCode);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(4,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   hFast=iMA(_Symbol,PERIOD_CURRENT,InpFastLen,0,MODE_EMA,InpAppliedPrice);
   hMid =iMA(_Symbol,PERIOD_CURRENT,InpMidLen ,0,MODE_EMA,InpAppliedPrice);
   hSlow=iMA(_Symbol,PERIOD_CURRENT,InpSlowLen,0,MODE_EMA,InpAppliedPrice);
   hATR =iATR(_Symbol,PERIOD_CURRENT,InpATRLen);
   if(hFast==INVALID_HANDLE||hMid==INVALID_HANDLE||hSlow==INVALID_HANDLE||hATR==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(FastBuffer,true); ArraySetAsSeries(MidBuffer,true); ArraySetAsSeries(SlowBuffer,true);
   ArraySetAsSeries(BuyBuffer,true);  ArraySetAsSeries(SellBuffer,true);

   IndicatorSetString(INDICATOR_SHORTNAME,"ARUN EMA CROSS V1 ("+
                      IntegerToString(InpFastLen)+"/"+IntegerToString(InpMidLen)+"/"+
                      IntegerToString(InpSlowLen)+")");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteDashboard();
   int hs[]={hFast,hMid,hSlow,hATR};
   for(int i=0;i<ArraySize(hs);i++) if(hs[i]!=INVALID_HANDLE) IndicatorRelease(hs[i]);
}

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   int need=InpSlowLen+InpMaxBarsBetween+InpATRLen+10;
   if(rates_total<need) return 0;

   ArraySetAsSeries(time,true);  ArraySetAsSeries(open,true); ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);   ArraySetAsSeries(close,true);

   if(CopyBuffer(hFast,0,0,rates_total,FastBuffer)<rates_total) return prev_calculated;
   if(CopyBuffer(hMid ,0,0,rates_total,MidBuffer )<rates_total) return prev_calculated;
   if(CopyBuffer(hSlow,0,0,rates_total,SlowBuffer)<rates_total) return prev_calculated;

   ArrayInitialize(BuyBuffer,EMPTY_VALUE);
   ArrayInitialize(SellBuffer,EMPTY_VALUE);

   int limit=rates_total-InpSlowLen-2;
   if(limit>InpMaxBarsCalc) limit=InpMaxBarsCalc;
   if(limit<2) return rates_total;

   double atrBuf[];
   ArraySetAsSeries(atrBuf,true);
   int atrCount=CopyBuffer(hATR,0,0,limit+2,atrBuf);

   int lastBar=(InpClosedBarOnly ? 1 : 0);
   int N=MathMax(0,InpMaxBarsBetween);

   // Legs of the pending sequence: the bar index each cross happened on, or -1.
   int bullFM=-1,bullFS=-1,bearFM=-1,bearFS=-1;
   // Signal fired on the most recent processed bar, and the last signal overall.
   int signalDir=0,lastSignalDir=0,lastSignalBar=-1;
   double lastSignalPrice=0.0;

   for(int i=limit;i>=lastBar;i--)
   {
      // A leg only stays valid for InpMaxBarsBetween candles.
      if(bullFM>=0 && bullFM-i>N) bullFM=-1;
      if(bullFS>=0 && bullFS-i>N) bullFS=-1;
      if(bearFM>=0 && bearFM-i>N) bearFM=-1;
      if(bearFS>=0 && bearFS-i>N) bearFS=-1;

      bool fmUp=(FastBuffer[i]>MidBuffer[i]  && FastBuffer[i+1]<=MidBuffer[i+1]);
      bool fmDn=(FastBuffer[i]<MidBuffer[i]  && FastBuffer[i+1]>=MidBuffer[i+1]);
      bool fsUp=(FastBuffer[i]>SlowBuffer[i] && FastBuffer[i+1]<=SlowBuffer[i+1]);
      bool fsDn=(FastBuffer[i]<SlowBuffer[i] && FastBuffer[i+1]>=SlowBuffer[i+1]);

      // A cross the other way cancels the pending leg of the same pair.
      if(fmUp) { bullFM=i; bearFM=-1; }
      if(fmDn) { bearFM=i; bullFM=-1; }
      if(fsUp) { bullFS=i; bearFS=-1; }
      if(fsDn) { bearFS=i; bullFS=-1; }

      signalDir=0;
      bool buy =(bullFM>=0 && bullFS>=0 && MathAbs(bullFM-bullFS)<=N);
      bool sell=(bearFM>=0 && bearFS>=0 && MathAbs(bearFM-bearFS)<=N);

      if(buy || sell)
      {
         // The sequence is consumed, a fresh pair of crosses is needed next time.
         if(buy)  { bullFM=-1; bullFS=-1; }
         if(sell) { bearFM=-1; bearFS=-1; }

         if(time[i]>=InpAnalysisStartDate)
         {
            double atr=(atrCount>i && atrBuf[i]>0.0 ? atrBuf[i] : 0.0);
            double off=MathMax(atr*0.30,15*_Point);

            signalDir=(buy?1:-1);
            lastSignalDir=signalDir;
            lastSignalBar=i;
            lastSignalPrice=close[i];

            if(InpShowSignals)
            {
               if(buy) BuyBuffer[i]=low[i]-off;
               else    SellBuffer[i]=high[i]+off;
            }
            if(i==lastBar) AlertSignal(buy,time[i],close[i]);
         }
      }
      else if(i==lastBar)
      {
         // Stage 1 just armed the setup on the newest processed bar.
         bool armedUp  =(bullFM==i && bullFS<0);
         bool armedDown=(bearFM==i && bearFS<0);
         if(armedUp || armedDown) AlertWait(armedUp,time[i]);
      }
   }

   int pendingDir=0;
   if(bullFM>=0 || bullFS>=0) pendingDir=1;
   if(bearFM>=0 || bearFS>=0) pendingDir=(pendingDir==1 ? 0 : -1);

   int fmBar=(bullFM>=0?bullFM:bearFM), fmDir=(bullFM>=0?1:(bearFM>=0?-1:0));
   int fsBar=(bullFS>=0?bullFS:bearFS), fsDir=(bullFS>=0?1:(bearFS>=0?-1:0));

   if(InpShowDashboard)
      UpdateDashboard(lastBar,pendingDir,fmBar,fmDir,fsBar,fsDir,
                      signalDir,lastSignalDir,lastSignalPrice,lastSignalBar);
   else
      DeleteDashboard();

   ChartRedraw(0);
   return rates_total;
}
