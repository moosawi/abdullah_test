//+------------------------------------------------------------------+
//| AI Support & Resistance EA for MT5                               |
//| Copyright 2025, AI Trading Systems                               |
//| Version 1.0                                                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AI Trading Systems"
#property link      ""
#property version   "1.00"
#property strict

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Create instances
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_SR_STRENGTH
{
   STRENGTH_WEAK = 1,      // Weak (1-2 touches)
   STRENGTH_MEDIUM = 2,    // Medium (3-4 touches)
   STRENGTH_STRONG = 3     // Strong (5+ touches)
};

//+------------------------------------------------------------------+
//| Structure for S/R Levels                                          |
//+------------------------------------------------------------------+
struct SRLevel
{
   double   price;                    // Level price
   int      touches;                  // Number of times tested
   datetime first_touch;              // First time identified
   datetime last_touch;               // Most recent test
   int      strength;                 // 1=Weak, 2=Medium, 3=Strong
   bool     is_support;               // true=support, false=resistance
   double   total_volume;             // Cumulative volume at level
   int      timeframe_confirmations;  // How many TFs confirm
   double   success_rate;             // % of successful bounces
   bool     is_broken;                // Has level been broken?
   bool     active;                   // Is level still active?
};

//+------------------------------------------------------------------+
//| Input Parameters - S/R Detection Settings                         |
//+------------------------------------------------------------------+
input group "=== S/R Detection Settings ==="
input int               SwingLookback = 100;              // Bars to scan for swing points
input int               MinTouches = 2;                   // Minimum touches to confirm level
input double            ClusterTolerance = 10;            // Pips to merge nearby levels
input bool              UseMultiTimeframe = true;         // Check multiple timeframes
input ENUM_TIMEFRAMES   TF1 = PERIOD_H1;                 // Primary timeframe
input ENUM_TIMEFRAMES   TF2 = PERIOD_H4;                 // Secondary timeframe
input ENUM_TIMEFRAMES   TF3 = PERIOD_D1;                 // Tertiary timeframe

//+------------------------------------------------------------------+
//| Input Parameters - Trading Strategy                               |
//+------------------------------------------------------------------+
input group "=== Trading Strategy ==="
input bool              EnableBounceTrading = true;       // Enable bounce trading
input bool              EnableBreakoutTrading = false;    // Enable breakout trading
input bool              EnableRangeTrading = false;       // Enable range trading
input int               MinLevelStrength = 2;            // Min strength (1=Weak, 2=Medium, 3=Strong)

//+------------------------------------------------------------------+
//| Input Parameters - Entry Filters                                  |
//+------------------------------------------------------------------+
input group "=== Entry Filters ==="
input bool              UseVolumeFilter = true;           // Use volume filter
input bool              UseCandlePatterns = true;         // Use candlestick patterns
input bool              UseIndicatorConfirmation = false; // Use RSI confirmation
input int               RSI_Period = 14;                  // RSI period
input int               RSI_Overbought = 70;             // RSI overbought level
input int               RSI_Oversold = 30;               // RSI oversold level
input double            MinDistanceFromLevel = 5;        // Min pips from S/R to enter

//+------------------------------------------------------------------+
//| Input Parameters - Risk Management                                |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double            RiskPercent = 1.0;                // Risk per trade (%)
input double            FixedLotSize = 0.1;              // Fixed lot (if RiskPercent = 0)
input int               StopLossBuffer = 10;             // Pips beyond S/R level
input double            RewardRiskRatio = 2.0;           // Take profit ratio
input bool              UseTrailingStop = true;          // Use trailing stop
input int               TrailingStopStart = 20;          // Pips profit before trailing
input int               TrailingStopDistance = 15;       // Trailing distance (pips)

//+------------------------------------------------------------------+
//| Input Parameters - Position Management                            |
//+------------------------------------------------------------------+
input group "=== Position Management ==="
input int               MaxOpenTrades = 3;               // Maximum open trades
input double            MaxDailyLoss = 5.0;              // Max daily loss (%)
input int               MagicNumber = 123456;            // Magic number
input string            TradeComment = "AI_SR_EA";       // Trade comment

//+------------------------------------------------------------------+
//| Input Parameters - Chart Display                                  |
//+------------------------------------------------------------------+
input group "=== Chart Display ==="
input bool              ShowSRLevels = true;             // Show S/R levels on chart
input bool              ShowTradingZones = true;         // Show trading zones
input color             SupportColor = clrDodgerBlue;    // Support color
input color             ResistanceColor = clrCrimson;    // Resistance color
input ENUM_LINE_STYLE   LevelStyle = STYLE_SOLID;        // Line style

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
SRLevel g_SRLevels[];           // Array to store S/R levels
int     g_SRLevelCount = 0;     // Count of S/R levels
int     g_RSI_Handle = INVALID_HANDLE;  // RSI indicator handle
double  g_PointValue;           // Point value for the symbol
double  g_TickSize;             // Tick size
datetime g_LastBarTime = 0;     // Last bar time for new bar detection
double  g_DailyStartBalance = 0; // Balance at start of day
datetime g_LastDayReset = 0;    // Last day reset time

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize point value
   g_PointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 ||
      SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
      g_PointValue *= 10;

   g_TickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Initialize RSI if needed
   if(UseIndicatorConfirmation)
   {
      g_RSI_Handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
      if(g_RSI_Handle == INVALID_HANDLE)
      {
         Print("Failed to create RSI indicator handle");
         return(INIT_FAILED);
      }
   }

   // Set magic number for trades
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // Initialize daily tracking
   g_DailyStartBalance = account.Balance();
   g_LastDayReset = TimeCurrent();

   // Resize S/R levels array
   ArrayResize(g_SRLevels, 100);

   Print("AI Support & Resistance EA initialized successfully");
   Print("Symbol: ", _Symbol, " | Point: ", g_PointValue, " | Tick Size: ", g_TickSize);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release RSI indicator
   if(g_RSI_Handle != INVALID_HANDLE)
      IndicatorRelease(g_RSI_Handle);

   // Delete all objects created by EA
   DeleteAllObjects();

   Print("AI Support & Resistance EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (currentBarTime != g_LastBarTime);

   if(isNewBar)
   {
      g_LastBarTime = currentBarTime;

      // Check daily reset
      CheckDailyReset();

      // Check if max daily loss reached
      if(CheckMaxDailyLoss())
      {
         Comment("Max daily loss reached. Trading paused for today.");
         return;
      }

      // Update S/R levels on new bar
      UpdateSRLevels();

      // Display S/R levels on chart
      if(ShowSRLevels)
         DrawSRLevels();

      // Check for trading opportunities
      CheckTradingSignals();
   }

   // Manage open positions (trailing stop, etc.)
   ManageOpenPositions();

   // Update chart comment
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Check for daily reset                                            |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime currentTime, lastResetTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(g_LastDayReset, lastResetTime);

   if(currentTime.day != lastResetTime.day)
   {
      g_DailyStartBalance = account.Balance();
      g_LastDayReset = TimeCurrent();
      Print("Daily reset performed. New day started.");
   }
}

//+------------------------------------------------------------------+
//| Check if max daily loss reached                                  |
//+------------------------------------------------------------------+
bool CheckMaxDailyLoss()
{
   if(MaxDailyLoss <= 0)
      return false;

   double currentBalance = account.Balance();
   double dailyLoss = g_DailyStartBalance - currentBalance;
   double maxLossAmount = g_DailyStartBalance * MaxDailyLoss / 100.0;

   return (dailyLoss >= maxLossAmount);
}

//+------------------------------------------------------------------+
//| Update Support & Resistance Levels                               |
//+------------------------------------------------------------------+
void UpdateSRLevels()
{
   // Clear existing levels
   g_SRLevelCount = 0;

   // Detect S/R levels on primary timeframe
   DetectSRLevels(TF1);

   // Multi-timeframe confirmation
   if(UseMultiTimeframe)
   {
      ConfirmSRLevelsWithTimeframe(TF2);
      ConfirmSRLevelsWithTimeframe(TF3);
   }

   // Merge nearby levels
   MergeNearbyLevels();

   // Update level strength
   UpdateLevelStrength();

   // Remove broken levels
   RemoveBrokenLevels();
}

//+------------------------------------------------------------------+
//| Detect S/R levels using swing highs and lows                     |
//+------------------------------------------------------------------+
void DetectSRLevels(ENUM_TIMEFRAMES timeframe)
{
   int barsToScan = MathMin(SwingLookback, iBars(_Symbol, timeframe) - 10);

   for(int i = 5; i < barsToScan; i++)
   {
      double high = iHigh(_Symbol, timeframe, i);
      double low = iLow(_Symbol, timeframe, i);
      datetime time = iTime(_Symbol, timeframe, i);

      // Check for swing high (resistance)
      if(IsSwingHigh(timeframe, i))
      {
         AddOrUpdateSRLevel(high, false, time, timeframe);
      }

      // Check for swing low (support)
      if(IsSwingLow(timeframe, i))
      {
         AddOrUpdateSRLevel(low, true, time, timeframe);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(ENUM_TIMEFRAMES timeframe, int bar)
{
   int lookback = 3;
   double centerHigh = iHigh(_Symbol, timeframe, bar);

   // Check left side
   for(int i = 1; i <= lookback; i++)
   {
      if(iHigh(_Symbol, timeframe, bar + i) >= centerHigh)
         return false;
   }

   // Check right side
   for(int i = 1; i <= lookback; i++)
   {
      if(iHigh(_Symbol, timeframe, bar - i) >= centerHigh)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                      |
//+------------------------------------------------------------------+
bool IsSwingLow(ENUM_TIMEFRAMES timeframe, int bar)
{
   int lookback = 3;
   double centerLow = iLow(_Symbol, timeframe, bar);

   // Check left side
   for(int i = 1; i <= lookback; i++)
   {
      if(iLow(_Symbol, timeframe, bar + i) <= centerLow)
         return false;
   }

   // Check right side
   for(int i = 1; i <= lookback; i++)
   {
      if(iLow(_Symbol, timeframe, bar - i) <= centerLow)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Add or update S/R level                                          |
//+------------------------------------------------------------------+
void AddOrUpdateSRLevel(double price, bool isSupport, datetime time, ENUM_TIMEFRAMES tf)
{
   double tolerance = ClusterTolerance * g_PointValue;

   // Check if similar level exists
   for(int i = 0; i < g_SRLevelCount; i++)
   {
      if(g_SRLevels[i].is_support == isSupport &&
         MathAbs(g_SRLevels[i].price - price) <= tolerance)
      {
         // Update existing level
         g_SRLevels[i].touches++;
         g_SRLevels[i].last_touch = time;
         g_SRLevels[i].price = (g_SRLevels[i].price + price) / 2.0; // Average price
         return;
      }
   }

   // Add new level
   if(g_SRLevelCount >= ArraySize(g_SRLevels))
      ArrayResize(g_SRLevels, g_SRLevelCount + 50);

   g_SRLevels[g_SRLevelCount].price = price;
   g_SRLevels[g_SRLevelCount].touches = 1;
   g_SRLevels[g_SRLevelCount].first_touch = time;
   g_SRLevels[g_SRLevelCount].last_touch = time;
   g_SRLevels[g_SRLevelCount].strength = STRENGTH_WEAK;
   g_SRLevels[g_SRLevelCount].is_support = isSupport;
   g_SRLevels[g_SRLevelCount].total_volume = 0;
   g_SRLevels[g_SRLevelCount].timeframe_confirmations = 1;
   g_SRLevels[g_SRLevelCount].success_rate = 0;
   g_SRLevels[g_SRLevelCount].is_broken = false;
   g_SRLevels[g_SRLevelCount].active = true;

   g_SRLevelCount++;
}

//+------------------------------------------------------------------+
//| Confirm S/R levels with another timeframe                        |
//+------------------------------------------------------------------+
void ConfirmSRLevelsWithTimeframe(ENUM_TIMEFRAMES timeframe)
{
   int barsToScan = MathMin(SwingLookback / 2, iBars(_Symbol, timeframe) - 10);
   double tolerance = ClusterTolerance * g_PointValue * 1.5;

   for(int i = 5; i < barsToScan; i++)
   {
      double high = iHigh(_Symbol, timeframe, i);
      double low = iLow(_Symbol, timeframe, i);

      // Check for swing high
      if(IsSwingHigh(timeframe, i))
      {
         // Find matching level
         for(int j = 0; j < g_SRLevelCount; j++)
         {
            if(!g_SRLevels[j].is_support &&
               MathAbs(g_SRLevels[j].price - high) <= tolerance)
            {
               g_SRLevels[j].timeframe_confirmations++;
               break;
            }
         }
      }

      // Check for swing low
      if(IsSwingLow(timeframe, i))
      {
         // Find matching level
         for(int j = 0; j < g_SRLevelCount; j++)
         {
            if(g_SRLevels[j].is_support &&
               MathAbs(g_SRLevels[j].price - low) <= tolerance)
            {
               g_SRLevels[j].timeframe_confirmations++;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Merge nearby S/R levels                                          |
//+------------------------------------------------------------------+
void MergeNearbyLevels()
{
   double tolerance = ClusterTolerance * g_PointValue;

   for(int i = 0; i < g_SRLevelCount - 1; i++)
   {
      for(int j = i + 1; j < g_SRLevelCount; j++)
      {
         if(g_SRLevels[i].active && g_SRLevels[j].active &&
            g_SRLevels[i].is_support == g_SRLevels[j].is_support &&
            MathAbs(g_SRLevels[i].price - g_SRLevels[j].price) <= tolerance)
         {
            // Merge levels
            g_SRLevels[i].price = (g_SRLevels[i].price + g_SRLevels[j].price) / 2.0;
            g_SRLevels[i].touches += g_SRLevels[j].touches;
            g_SRLevels[i].timeframe_confirmations = MathMax(g_SRLevels[i].timeframe_confirmations,
                                                             g_SRLevels[j].timeframe_confirmations);
            g_SRLevels[j].active = false;
         }
      }
   }

   // Compact array (remove inactive levels)
   int newCount = 0;
   for(int i = 0; i < g_SRLevelCount; i++)
   {
      if(g_SRLevels[i].active)
      {
         if(newCount != i)
            g_SRLevels[newCount] = g_SRLevels[i];
         newCount++;
      }
   }
   g_SRLevelCount = newCount;
}

//+------------------------------------------------------------------+
//| Update strength of S/R levels                                    |
//+------------------------------------------------------------------+
void UpdateLevelStrength()
{
   for(int i = 0; i < g_SRLevelCount; i++)
   {
      int strength = STRENGTH_WEAK;

      // Base strength on touches
      if(g_SRLevels[i].touches >= 5)
         strength = STRENGTH_STRONG;
      else if(g_SRLevels[i].touches >= 3)
         strength = STRENGTH_MEDIUM;

      // Bonus for multi-timeframe confirmation
      if(g_SRLevels[i].timeframe_confirmations >= 3)
         strength = STRENGTH_STRONG;
      else if(g_SRLevels[i].timeframe_confirmations >= 2 && strength < STRENGTH_MEDIUM)
         strength = STRENGTH_MEDIUM;

      g_SRLevels[i].strength = strength;
   }
}

//+------------------------------------------------------------------+
//| Remove broken S/R levels                                         |
//+------------------------------------------------------------------+
void RemoveBrokenLevels()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double breakBuffer = ClusterTolerance * g_PointValue * 2;

   for(int i = 0; i < g_SRLevelCount; i++)
   {
      // Mark support as broken if price went significantly below
      if(g_SRLevels[i].is_support && currentPrice < g_SRLevels[i].price - breakBuffer)
      {
         g_SRLevels[i].is_broken = true;
         g_SRLevels[i].active = false;
      }

      // Mark resistance as broken if price went significantly above
      if(!g_SRLevels[i].is_support && currentPrice > g_SRLevels[i].price + breakBuffer)
      {
         g_SRLevels[i].is_broken = true;
         g_SRLevels[i].active = false;
      }
   }

   // Compact array
   int newCount = 0;
   for(int i = 0; i < g_SRLevelCount; i++)
   {
      if(g_SRLevels[i].active)
      {
         if(newCount != i)
            g_SRLevels[newCount] = g_SRLevels[i];
         newCount++;
      }
   }
   g_SRLevelCount = newCount;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   // Check if we can open more positions
   if(CountOpenPositions() >= MaxOpenTrades)
      return;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDistance = MinDistanceFromLevel * g_PointValue;

   // Check each S/R level for trading opportunities
   for(int i = 0; i < g_SRLevelCount; i++)
   {
      // Skip if level strength is below minimum
      if(g_SRLevels[i].strength < MinLevelStrength)
         continue;

      double distanceFromLevel = MathAbs(currentPrice - g_SRLevels[i].price);

      // Bounce trading at support
      if(EnableBounceTrading && g_SRLevels[i].is_support && distanceFromLevel <= minDistance)
      {
         if(CheckBuySignal(g_SRLevels[i]))
         {
            OpenBuyTrade(g_SRLevels[i]);
            return; // One trade per tick
         }
      }

      // Bounce trading at resistance
      if(EnableBounceTrading && !g_SRLevels[i].is_support && distanceFromLevel <= minDistance)
      {
         if(CheckSellSignal(g_SRLevels[i]))
         {
            OpenSellTrade(g_SRLevels[i]);
            return; // One trade per tick
         }
      }

      // Breakout trading
      if(EnableBreakoutTrading)
      {
         CheckBreakoutSignals(g_SRLevels[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| Check buy signal (bounce from support)                           |
//+------------------------------------------------------------------+
bool CheckBuySignal(SRLevel &level)
{
   // Check candlestick pattern
   if(UseCandlePatterns)
   {
      if(!IsBullishRejectionPattern())
         return false;
   }

   // Check RSI
   if(UseIndicatorConfirmation)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(g_RSI_Handle, 0, 0, 2, rsi) <= 0)
         return false;

      if(rsi[0] > RSI_Oversold)
         return false;
   }

   // Check volume
   if(UseVolumeFilter)
   {
      if(!IsHighVolume())
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check sell signal (bounce from resistance)                       |
//+------------------------------------------------------------------+
bool CheckSellSignal(SRLevel &level)
{
   // Check candlestick pattern
   if(UseCandlePatterns)
   {
      if(!IsBearishRejectionPattern())
         return false;
   }

   // Check RSI
   if(UseIndicatorConfirmation)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(g_RSI_Handle, 0, 0, 2, rsi) <= 0)
         return false;

      if(rsi[0] < RSI_Overbought)
         return false;
   }

   // Check volume
   if(UseVolumeFilter)
   {
      if(!IsHighVolume())
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check for bullish rejection pattern                              |
//+------------------------------------------------------------------+
bool IsBullishRejectionPattern()
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   // Pin bar pattern
   if(lowerWick > body * 2 && lowerWick > upperWick * 2 && close > open)
      return true;

   // Bullish engulfing
   double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
   if(close > open && prevClose < prevOpen &&
      close > prevOpen && open < prevClose)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish rejection pattern                              |
//+------------------------------------------------------------------+
bool IsBearishRejectionPattern()
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   // Pin bar pattern
   if(upperWick > body * 2 && upperWick > lowerWick * 2 && close < open)
      return true;

   // Bearish engulfing
   double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
   if(close < open && prevClose > prevOpen &&
      close < prevOpen && open > prevClose)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Check for high volume                                            |
//+------------------------------------------------------------------+
bool IsHighVolume()
{
   long currentVolume = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVolume = 0;

   // Calculate average volume
   for(int i = 2; i <= 21; i++)
   {
      avgVolume += iVolume(_Symbol, PERIOD_CURRENT, i);
   }
   avgVolume /= 20;

   return (currentVolume > avgVolume * 1.2);
}

//+------------------------------------------------------------------+
//| Check for breakout signals                                       |
//+------------------------------------------------------------------+
void CheckBreakoutSignals(SRLevel &level)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double breakBuffer = ClusterTolerance * g_PointValue;

   // Resistance breakout (buy signal)
   if(!level.is_support && currentPrice > level.price + breakBuffer)
   {
      if(UseVolumeFilter && !IsHighVolume())
         return;

      // Check if not already traded this breakout
      if(!HasRecentBreakoutTrade(level.price, true))
      {
         OpenBuyTrade(level);
      }
   }

   // Support breakdown (sell signal)
   if(level.is_support && currentPrice < level.price - breakBuffer)
   {
      if(UseVolumeFilter && !IsHighVolume())
         return;

      // Check if not already traded this breakout
      if(!HasRecentBreakoutTrade(level.price, false))
      {
         OpenSellTrade(level);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there's a recent breakout trade at this level           |
//+------------------------------------------------------------------+
bool HasRecentBreakoutTrade(double levelPrice, bool isBuy)
{
   HistorySelect(TimeCurrent() - 3600, TimeCurrent()); // Last hour

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
         {
            double dealPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
            if(MathAbs(dealPrice - levelPrice) < ClusterTolerance * g_PointValue)
               return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Open buy trade                                                    |
//+------------------------------------------------------------------+
void OpenBuyTrade(SRLevel &level)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = level.price - (StopLossBuffer * g_PointValue);
   double slDistance = ask - sl;
   double tp = ask + (slDistance * RewardRiskRatio);

   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);

   // Normalize prices
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   // Open trade
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, TradeComment))
   {
      Print("BUY order opened at ", ask, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);
   }
   else
   {
      Print("Failed to open BUY order. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open sell trade                                                   |
//+------------------------------------------------------------------+
void OpenSellTrade(SRLevel &level)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = level.price + (StopLossBuffer * g_PointValue);
   double slDistance = sl - bid;
   double tp = bid - (slDistance * RewardRiskRatio);

   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);

   // Normalize prices
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   // Open trade
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, TradeComment))
   {
      Print("SELL order opened at ", bid, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);
   }
   else
   {
      Print("Failed to open SELL order. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double lotSize = FixedLotSize;

   if(RiskPercent > 0)
   {
      double accountBalance = account.Balance();
      double riskAmount = accountBalance * RiskPercent / 100.0;

      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      double slInTicks = slDistance / tickSize;
      double riskPerLot = slInTicks * tickValue;

      if(riskPerLot > 0)
         lotSize = riskAmount / riskPerLot;
   }

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing stop, etc.)                      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UseTrailingStop)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         {
            double positionProfit = position.Profit();
            double openPrice = position.PriceOpen();
            double currentSL = position.StopLoss();

            if(position.Type() == POSITION_TYPE_BUY)
            {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double profitPips = (bid - openPrice) / g_PointValue;

               if(profitPips >= TrailingStopStart)
               {
                  double newSL = bid - (TrailingStopDistance * g_PointValue);
                  newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

                  if(newSL > currentSL)
                  {
                     trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  }
               }
            }
            else if(position.Type() == POSITION_TYPE_SELL)
            {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double profitPips = (openPrice - ask) / g_PointValue;

               if(profitPips >= TrailingStopStart)
               {
                  double newSL = ask + (TrailingStopDistance * g_PointValue);
                  newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

                  if(newSL < currentSL || currentSL == 0)
                  {
                     trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Draw S/R levels on chart                                         |
//+------------------------------------------------------------------+
void DrawSRLevels()
{
   // Delete old lines
   DeleteAllObjects();

   for(int i = 0; i < g_SRLevelCount; i++)
   {
      string objName = "SR_Level_" + IntegerToString(i);
      color lineColor = g_SRLevels[i].is_support ? SupportColor : ResistanceColor;

      // Draw line
      if(ObjectCreate(0, objName, OBJ_HLINE, 0, 0, g_SRLevels[i].price))
      {
         ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, LevelStyle);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, g_SRLevels[i].strength);
         ObjectSetInteger(0, objName, OBJPROP_BACK, true);
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);

         // Add text label
         string labelName = "SR_Label_" + IntegerToString(i);
         string levelType = g_SRLevels[i].is_support ? "S" : "R";
         string strengthText = "";
         if(g_SRLevels[i].strength == STRENGTH_STRONG) strengthText = "Strong";
         else if(g_SRLevels[i].strength == STRENGTH_MEDIUM) strengthText = "Medium";
         else strengthText = "Weak";

         string labelText = levelType + " (" + strengthText + " - " +
                           IntegerToString(g_SRLevels[i].touches) + " touches)";

         if(ObjectCreate(0, labelName, OBJ_TEXT, 0, TimeCurrent(), g_SRLevels[i].price))
         {
            ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
         }
      }
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete all objects created by EA                                 |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "SR_") == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| Update chart comment with info                                   |
//+------------------------------------------------------------------+
void UpdateComment()
{
   string comment = "\n=== AI Support & Resistance EA ===\n";
   comment += "Symbol: " + _Symbol + "\n";
   comment += "S/R Levels: " + IntegerToString(g_SRLevelCount) + "\n";
   comment += "Open Positions: " + IntegerToString(CountOpenPositions()) + "/" + IntegerToString(MaxOpenTrades) + "\n";
   comment += "Account Balance: $" + DoubleToString(account.Balance(), 2) + "\n";
   comment += "Account Equity: $" + DoubleToString(account.Equity(), 2) + "\n";

   // Show strongest levels
   comment += "\n=== Strongest Levels ===\n";
   int shownLevels = 0;
   for(int i = 0; i < g_SRLevelCount && shownLevels < 5; i++)
   {
      if(g_SRLevels[i].strength >= STRENGTH_MEDIUM)
      {
         string levelType = g_SRLevels[i].is_support ? "Support" : "Resistance";
         string strength = g_SRLevels[i].strength == STRENGTH_STRONG ? "Strong" : "Medium";
         comment += levelType + ": " + DoubleToString(g_SRLevels[i].price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                   " (" + strength + ", " + IntegerToString(g_SRLevels[i].touches) + " touches)\n";
         shownLevels++;
      }
   }

   Comment(comment);
}
//+------------------------------------------------------------------+
