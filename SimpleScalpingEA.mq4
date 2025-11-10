//+------------------------------------------------------------------+
//|                                           SimpleScalpingEA.mq4    |
//|                                    Momentum-Based Scalping EA     |
//|                                    One Trade Per Candle Strategy  |
//+------------------------------------------------------------------+
#property copyright "Scalping EA"
#property link      ""
#property version   "1.00"
#property strict

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

datetime lastCandleTime = 0;                  // Track last candle we traded
bool tradedThisCandle = false;                // Flag: did we trade this candle?
int currentTicket = 0;                        // Current open trade ticket
double pointValue;                            // Point value for current symbol

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION FUNCTION                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate point value based on symbol digits
   pointValue = Point;
   if(Digits == 3 || Digits == 5) pointValue *= 10;

   Print("=== Simple Scalping EA Initialized ===");
   Print("Symbol: ", Symbol());
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
   datetime currentCandleTime = iTime(Symbol(), Timeframe, 0);

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
//| COUNT OPEN ORDERS FOR THIS EA                                     |
//+------------------------------------------------------------------+
int CountOpenOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
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

   // SAFETY CHECK #2: Count all open orders with our magic number
   int openOrders = CountOpenOrders();
   if(openOrders > 0)
   {
      Print("Safety: Already have ", openOrders, " open order(s)");
      return; // We already have a trade open
   }

   // SAFETY CHECK #3: Double-check our current ticket
   if(currentTicket > 0 && OrderSelect(currentTicket, SELECT_BY_TICKET))
   {
      if(OrderCloseTime() == 0)
      {
         Print("Safety: Current ticket still open");
         return; // Trade still open
      }
   }

   // Get previous candle data (the completed candle before current one)
   double prevOpen = iOpen(Symbol(), Timeframe, 1);
   double prevClose = iClose(Symbol(), Timeframe, 1);
   double prevHigh = iHigh(Symbol(), Timeframe, 1);
   double prevLow = iLow(Symbol(), Timeframe, 1);

   // Calculate previous candle body size in pips
   double candleBodySize = MathAbs(prevClose - prevOpen) / pointValue;

   // Filter: Only trade if candle is big enough
   if(candleBodySize < MinimumCandleSizePips)
   {
      if(ShowComments) Print("Signal rejected: Candle too small (", DoubleToStr(candleBodySize, 1), " pips)");
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
   double ask = MarketInfo(Symbol(), MODE_ASK);
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

   // Open the trade
   int ticket = OrderSend(Symbol(), OP_BUY, LotSize, ask, 3, sl, tp,
                          "Scalping BUY", MagicNumber, 0, clrGreen);

   if(ticket > 0)
   {
      currentTicket = ticket;
      tradedThisCandle = true;
      Print("✓ BUY opened: Ticket #", ticket, " @ ", DoubleToStr(ask, Digits),
            " | SL: ", DoubleToStr(sl, Digits), " | TP: ", DoubleToStr(tp, Digits));
   }
   else
   {
      Print("✗ Failed to open BUY trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| OPEN SELL TRADE                                                   |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   double bid = MarketInfo(Symbol(), MODE_BID);
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

   // Open the trade
   int ticket = OrderSend(Symbol(), OP_SELL, LotSize, bid, 3, sl, tp,
                          "Scalping SELL", MagicNumber, 0, clrRed);

   if(ticket > 0)
   {
      currentTicket = ticket;
      tradedThisCandle = true;
      Print("✓ SELL opened: Ticket #", ticket, " @ ", DoubleToStr(bid, Digits),
            " | SL: ", DoubleToStr(sl, Digits), " | TP: ", DoubleToStr(tp, Digits));
   }
   else
   {
      Print("✗ Failed to open SELL trade. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| CLOSE TRADE AT CANDLE END                                         |
//+------------------------------------------------------------------+
void CloseTradeAtCandleEnd()
{
   if(currentTicket <= 0) return;

   if(OrderSelect(currentTicket, SELECT_BY_TICKET))
   {
      // Check if order is still open
      if(OrderCloseTime() == 0)
      {
         double closePrice;
         color arrowColor;

         if(OrderType() == OP_BUY)
         {
            closePrice = MarketInfo(Symbol(), MODE_BID);
            arrowColor = clrBlue;
         }
         else if(OrderType() == OP_SELL)
         {
            closePrice = MarketInfo(Symbol(), MODE_ASK);
            arrowColor = clrOrange;
         }
         else
         {
            return; // Not a market order
         }

         // Close the order
         bool closed = OrderClose(currentTicket, OrderLots(), closePrice, 3, arrowColor);

         if(closed)
         {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            Print("→ Trade closed at candle end | Ticket #", currentTicket,
                  " | Profit: $", DoubleToStr(profit, 2));
            currentTicket = 0;
         }
         else
         {
            Print("✗ Failed to close trade at candle end. Error: ", GetLastError());
         }
      }
      else
      {
         // Trade already closed (TP/SL hit)
         currentTicket = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATE CHART COMMENT                                              |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   int openOrders = CountOpenOrders();

   string info = "\n";
   info += "===== SIMPLE SCALPING EA =====\n";
   info += "Symbol: " + Symbol() + "\n";
   info += "Timeframe: " + EnumToString(Timeframe) + "\n";
   info += "Lot Size: " + DoubleToStr(LotSize, 2) + "\n";
   info += "TP: " + IntegerToString(TakeProfitPips) + " pips | ";
   info += "SL: " + IntegerToString(StopLossPips) + " pips\n";
   info += "Min Candle: " + IntegerToString(MinimumCandleSizePips) + " pips\n";
   info += "Open Orders: " + IntegerToString(openOrders) + "\n";
   info += "----------------------------\n";

   // Current trade status
   if(currentTicket > 0 && OrderSelect(currentTicket, SELECT_BY_TICKET))
   {
      if(OrderCloseTime() == 0)
      {
         string orderTypeStr = (OrderType() == OP_BUY) ? "BUY" : "SELL";
         double profit = OrderProfit() + OrderSwap() + OrderCommission();

         info += "Status: TRADE OPEN\n";
         info += "Type: " + orderTypeStr + "\n";
         info += "Ticket: #" + IntegerToString(currentTicket) + "\n";
         info += "Open Price: " + DoubleToStr(OrderOpenPrice(), Digits) + "\n";
         info += "Current P/L: $" + DoubleToStr(profit, 2) + "\n";
      }
      else
      {
         info += "Status: WAITING FOR SIGNAL\n";
      }
   }
   else
   {
      info += "Status: WAITING FOR SIGNAL\n";
   }

   // Previous candle info
   double prevOpen = iOpen(Symbol(), Timeframe, 1);
   double prevClose = iClose(Symbol(), Timeframe, 1);
   double candleSize = MathAbs(prevClose - prevOpen) / pointValue;
   string candleType = (prevClose > prevOpen) ? "BULLISH ↑" : "BEARISH ↓";

   info += "----------------------------\n";
   info += "Previous Candle: " + candleType + "\n";
   info += "Size: " + DoubleToStr(candleSize, 1) + " pips\n";

   Comment(info);
}

//+------------------------------------------------------------------+
