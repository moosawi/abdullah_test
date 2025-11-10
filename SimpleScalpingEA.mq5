//+------------------------------------------------------------------+
//|                                           SimpleScalpingEA.mq5    |
//|                                    Momentum-Based Scalping EA     |
//|                                    One Trade Per Candle Strategy  |
//+------------------------------------------------------------------+
#property copyright "Scalping EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// === Basic Settings ===
input int      MagicNumber = 12345;           // Unique identifier for this EA's trades
input ENUM_TIMEFRAMES Timeframe = PERIOD_M15; // Trading timeframe (M1, M5, M15, M30, H1)

// === Trading Settings ===
input double   LotSize = 0.1;                 // Fixed lot size
input int      TakeProfitPips = 20;           // Take profit in pips
input int      StopLossPips = 15;             // Stop loss in pips (0 = disabled)
input int      MinimumCandleSizePips = 5;     // Minimum candle body size to trade

// === Trade Direction ===
input bool     EnableBuyTrades = true;        // Enable BUY trades
input bool     EnableSellTrades = true;       // Enable SELL trades

// === Exit Settings ===
input bool     CloseAtCandleEnd = true;       // Close trade at end of candle if not TP/SL hit

// === Display Settings ===
input bool     ShowComments = true;           // Show info on chart

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

CTrade trade;                                 // Trade execution object
datetime lastCandleTime = 0;                  // Track last candle we traded
bool tradedThisCandle = false;                // Flag: did we trade this candle?
ulong currentTicket = 0;                      // Current open trade ticket
double pointValue;                            // Point value for current symbol

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION FUNCTION                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set magic number for the trade object
   trade.SetExpertMagicNumber(MagicNumber);

   // Calculate point value based on symbol digits
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(digits == 3 || digits == 5) pointValue *= 10;

   Print("=== Simple Scalping EA Initialized ===");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(Timeframe));
   Print("Lot Size: ", LotSize);
   Print("Take Profit: ", TakeProfitPips, " pips");
   Print("Stop Loss: ", StopLossPips, " pips");
   Print("Minimum Candle Size: ", MinimumCandleSizePips, " pips");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION FUNCTION                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== Simple Scalping EA Stopped ===");
   Comment("");
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have a new candle on our trading timeframe
   datetime currentCandleTime = iTime(_Symbol, Timeframe, 0);

   if(currentCandleTime != lastCandleTime)
   {
      // NEW CANDLE DETECTED!

      // If CloseAtCandleEnd is enabled and we have an open trade from previous candle
      if(CloseAtCandleEnd && currentTicket > 0)
      {
         CloseTradeAtCandleEnd();
      }

      // Reset flags for new candle
      lastCandleTime = currentCandleTime;
      tradedThisCandle = false;

      // Check for entry signal on the new candle
      CheckForEntrySignal();
   }

   // Update display
   if(ShowComments)
   {
      UpdateChartComment();
   }
}

//+------------------------------------------------------------------+
//| COUNT OPEN POSITIONS FOR THIS EA                                  |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| CHECK FOR ENTRY SIGNAL                                            |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
   // SAFETY CHECK #1: Don't trade if we already traded this candle
   if(tradedThisCandle)
   {
      Print("Safety: Already traded this candle");
      return;
   }

   // SAFETY CHECK #2: Count all open positions with our magic number
   int openPositions = CountOpenPositions();
   if(openPositions > 0)
   {
      Print("Safety: Already have ", openPositions, " open position(s)");
      return; // We already have a trade open
   }

   // SAFETY CHECK #3: Double-check our current ticket
   if(currentTicket > 0 && PositionSelectByTicket(currentTicket))
   {
      Print("Safety: Current ticket still open");
      return; // Trade still open
   }

   // Get previous candle data (the completed candle before current one)
   double prevOpen = iOpen(_Symbol, Timeframe, 1);
   double prevClose = iClose(_Symbol, Timeframe, 1);
   double prevHigh = iHigh(_Symbol, Timeframe, 1);
   double prevLow = iLow(_Symbol, Timeframe, 1);

   // Calculate previous candle body size in pips
   double candleBodySize = MathAbs(prevClose - prevOpen) / pointValue;

   // Filter: Only trade if candle is big enough
   if(candleBodySize < MinimumCandleSizePips)
   {
      if(ShowComments) Print("Signal rejected: Candle too small (", DoubleToString(candleBodySize, 1), " pips)");
      return;
   }

   // MOMENTUM DETECTION
   // Bullish candle: Close > Open
   // Bearish candle: Close < Open

   bool isBullishCandle = (prevClose > prevOpen);
   bool isBearishCandle = (prevClose < prevOpen);

   // ENTRY LOGIC
   if(isBullishCandle && EnableBuyTrades)
   {
      // Previous candle was bullish → Open BUY at start of new candle
      OpenBuyTrade();
   }
   else if(isBearishCandle && EnableSellTrades)
   {
      // Previous candle was bearish → Open SELL at start of new candle
      OpenSellTrade();
   }
}

//+------------------------------------------------------------------+
//| OPEN BUY TRADE                                                    |
//+------------------------------------------------------------------+
void OpenBuyTrade()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0;
   double tp = 0;

   // Calculate Stop Loss
   if(StopLossPips > 0)
   {
      sl = ask - (StopLossPips * pointValue);
   }

   // Calculate Take Profit
   if(TakeProfitPips > 0)
   {
      tp = ask + (TakeProfitPips * pointValue);
   }

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Open the trade
   bool success = trade.Buy(LotSize, _Symbol, ask, sl, tp, "Scalping BUY");

   if(success)
   {
      currentTicket = trade.ResultOrder();
      tradedThisCandle = true;
      Print("✓ BUY opened: Ticket #", currentTicket, " @ ", DoubleToString(ask, digits),
            " | SL: ", DoubleToString(sl, digits), " | TP: ", DoubleToString(tp, digits));
   }
   else
   {
      Print("✗ Failed to open BUY trade. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| OPEN SELL TRADE                                                   |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;
   double tp = 0;

   // Calculate Stop Loss
   if(StopLossPips > 0)
   {
      sl = bid + (StopLossPips * pointValue);
   }

   // Calculate Take Profit
   if(TakeProfitPips > 0)
   {
      tp = bid - (TakeProfitPips * pointValue);
   }

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Open the trade
   bool success = trade.Sell(LotSize, _Symbol, bid, sl, tp, "Scalping SELL");

   if(success)
   {
      currentTicket = trade.ResultOrder();
      tradedThisCandle = true;
      Print("✓ SELL opened: Ticket #", currentTicket, " @ ", DoubleToString(bid, digits),
            " | SL: ", DoubleToString(sl, digits), " | TP: ", DoubleToString(tp, digits));
   }
   else
   {
      Print("✗ Failed to open SELL trade. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| CLOSE TRADE AT CANDLE END                                         |
//+------------------------------------------------------------------+
void CloseTradeAtCandleEnd()
{
   if(currentTicket <= 0) return;

   if(PositionSelectByTicket(currentTicket))
   {
      ulong posTicket = PositionGetInteger(POSITION_TICKET);
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Close the position
      bool closed = trade.PositionClose(posTicket);

      if(closed)
      {
         Print("→ Trade closed at candle end | Ticket #", posTicket,
               " | Profit: $", DoubleToString(profit, 2));
         currentTicket = 0;
      }
      else
      {
         Print("✗ Failed to close trade at candle end. Error: ", trade.ResultRetcode());
      }
   }
   else
   {
      // Trade already closed (TP/SL hit)
      currentTicket = 0;
   }
}

//+------------------------------------------------------------------+
//| UPDATE CHART COMMENT                                              |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   int openPositions = CountOpenPositions();

   string info = "\n";
   info += "===== SIMPLE SCALPING EA =====\n";
   info += "Symbol: " + _Symbol + "\n";
   info += "Timeframe: " + EnumToString(Timeframe) + "\n";
   info += "Lot Size: " + DoubleToString(LotSize, 2) + "\n";
   info += "TP: " + IntegerToString(TakeProfitPips) + " pips | ";
   info += "SL: " + IntegerToString(StopLossPips) + " pips\n";
   info += "Min Candle: " + IntegerToString(MinimumCandleSizePips) + " pips\n";
   info += "Open Positions: " + IntegerToString(openPositions) + "\n";
   info += "----------------------------\n";

   // Current trade status
   if(currentTicket > 0 && PositionSelectByTicket(currentTicket))
   {
      string posType = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double profit = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      info += "Status: TRADE OPEN\n";
      info += "Type: " + posType + "\n";
      info += "Ticket: #" + IntegerToString(currentTicket) + "\n";
      info += "Open Price: " + DoubleToString(openPrice, digits) + "\n";
      info += "Current P/L: $" + DoubleToString(profit, 2) + "\n";
   }
   else
   {
      info += "Status: WAITING FOR SIGNAL\n";
   }

   // Previous candle info
   double prevOpen = iOpen(_Symbol, Timeframe, 1);
   double prevClose = iClose(_Symbol, Timeframe, 1);
   double candleSize = MathAbs(prevClose - prevOpen) / pointValue;
   string candleType = (prevClose > prevOpen) ? "BULLISH ↑" : "BEARISH ↓";

   info += "----------------------------\n";
   info += "Previous Candle: " + candleType + "\n";
   info += "Size: " + DoubleToString(candleSize, 1) + " pips\n";

   Comment(info);
}

//+------------------------------------------------------------------+
