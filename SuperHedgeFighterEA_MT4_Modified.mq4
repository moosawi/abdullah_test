//+------------------------------------------------------------------+
//|Super Hedge Fighter EA MT4 - Converted from MT5                   |
//|AJB 2021 - MT4 Conversion 2025                                   |
//|https://www.mql5.com/en/users/1218858/seller#products             |
//+------------------------------------------------------------------+
#property copyright "Copyright AJB 2021"
#property link      "https://www.mql5.com/en/users/1218858/seller#products"
#property version   "1.5"
#property strict

//--- Input parameters
extern int            MagicNumber = 6711588;                      // Magic Number
extern bool           Method_A = true;                            // True: Up = Buy & Down = Sell, False: Up = Sell & Down = Buy
extern bool           AutoLot_WithPercentage = false;             // Auto Lot
extern double         LotSize_Manual = 0.1;                      // Manual Lot Size
extern double         LotSize_Percentage = 1;                     // Lot size Percentage
extern bool           Use_DifferentInitialHedgeLots = false;      // Use different lot size for initial hedge
extern double         InitialHedgeLotSize = 0.2;                 // Initial hedge lot size (when enabled)
extern bool           PercentageTP = false;                       // Use Percentage TP (true) or Manual TP (false)
extern double         TakeProfit_Manual = 10;                      // TP in $ when Manual
extern double         TakeProfit_Percentage = 1;                  // TP in % when Percentage
extern bool           EnableStopLoss = false;                     // Enable Stop Loss
extern bool           PercentageSL = false;                       // Use Percentage SL (true) or Manual SL (false)
extern double         StopLoss_Manual = 1000;                     // SL in $ when Manual
extern double         StopLoss_Percentage = 5;                    // SL in % when Percentage
extern double         GridDistance = 50;                          // Distance Between Orders
extern double         DistanceMultiplier = 2.0;                    // Multiplier for grid distance
extern double         Multiplier = 1.2;                           // Multiplier
extern int            MaxOrders = 0;                              // Max Orders, 0=Unlimited
extern double         MaxOrdersLotsPerChart = 0;                  // Max Lots Per Chart, 0=Unlimited
extern double         MaxLotsPerOrder = 1;                      // Max Lots Per Order, 0=Unlimited
extern bool           IsGoldTrading = false;                      // Enable for Gold trading (XAU, GOLD, etc.)
extern bool           EnableMarginSafetyBuffer = true;            // Enable margin safety buffer
extern double         MarginSafetyPercent = 10;                   // Margin safety buffer percentage
extern bool           EnableStopOutProtection = true;             // Enable stop out protection
extern double         StopOutProtectionLevel = 30;                // Margin level to trigger protection (percentage)
extern bool           EnableMaxLossProtection = false;            // Enable max loss protection
extern double         MaxLossAmount = 2000;                       // Max loss amount in $ to close all trades
extern int            WaitMinutesAfterLoss = 30;                  // Wait time in minutes before reopening trades

// Global variables
string limitationComment = "";
double g_StartBalance = 0;         // Starting balance for TP calculation
double g_StartLot = 0;             // Starting lot size
datetime g_StartTime = 0;          // Starting time
string g_TimeName = "";            // Global variable name for start time
string g_BalanceName = "";         // Global variable name for start balance

// Global variables for dynamic grid distance
double g_CurrentGridDistance = 0;   // Current grid distance (adjusted by multiplier)
int g_GridLevelBuy = 0;            // Current grid level for buys
int g_GridLevelSell = 0;           // Current grid level for sells

int g_BuyCount = 0;                // Count of buy orders
int g_SellCount = 0;               // Count of sell orders
double g_HighestBuyPrice = 0;      // Highest buy price
double g_LowestBuyPrice = 0;       // Lowest buy price
double g_HighestSellPrice = 0;     // Highest sell price
double g_LowestSellPrice = 0;      // Lowest sell price
double g_TotalLots = 0;            // Total lots in all orders
double g_TotalProfit = 0;          // Total profit of all orders
double g_HistoryProfit = 0;        // Historical profit since start time
double g_LastBuyLot = 0;           // Last buy order lot size
double g_LastSellLot = 0;          // Last sell order lot size

// Global variables for max loss protection
bool g_InWaitingPeriod = false;    // Flag to indicate if we're in waiting period
datetime g_WaitStartTime = 0;      // Time when waiting period started

// Forward declarations of helper functions
int GetDigits(string sym = NULL);
double ByPoint(double x, string sym = NULL);
double GetPointValue(string sym = NULL);
bool CheckVolumeLimit(string symbol, double additionalVolume, string &errorMessage);
double GetSymbolTotalVolume(string symbol);
double GetMaxAllowedVolume(string symbol);
bool CheckMoneyForTrade(string symb, double lots, int type);
double AdjustLotSizeByMargin(string symbol, double requestedLot, int type);
double CalculateLotSize(double fixedLot, bool useMM, double risk, double balance, string symbol = "");
double CalculateNextLotSize(int orderCount, double lastLot);
double GetDynamicGridDistance(int level, bool isBuy);
bool CheckForMaxOrders();
void ReduceWorstPosition();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_TimeName = "GV-T" + (string)MagicNumber + Symbol();
   g_BalanceName = "GV-B" + (string)MagicNumber + Symbol();

   // Initialize starting values
   g_StartTime = TimeCurrent();
   GlobalVariableSet(g_TimeName, (double)(int)g_StartTime);
   g_StartBalance = AccountBalance();
   GlobalVariableSet(g_BalanceName, g_StartBalance);
   g_StartLot = CalculateLotSize(LotSize_Manual, AutoLot_WithPercentage, LotSize_Percentage, g_StartBalance);

   // Initialize grid distance
   g_CurrentGridDistance = GridDistance;
   g_GridLevelBuy = 0;
   g_GridLevelSell = 0;

   // Initialize max loss protection variables
   g_InWaitingPeriod = false;
   g_WaitStartTime = 0;

   // Only essential info for initialization
   Print("Init: MN=", MagicNumber, " Bal=", g_StartBalance);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we're in waiting period after max loss
   if(g_InWaitingPeriod)
   {
      datetime currentTime = TimeCurrent();
      int elapsedMinutes = (int)((currentTime - g_WaitStartTime) / 60);

      if(elapsedMinutes >= WaitMinutesAfterLoss)
      {
         // Waiting period is over
         g_InWaitingPeriod = false;
         g_WaitStartTime = 0;
         Print("Waiting period over. Resuming trading.");
      }
      else
      {
         // Still waiting, update comment
         Comment("Waiting period: ", elapsedMinutes, "/", WaitMinutesAfterLoss, " minutes elapsed");
         return; // Don't trade during waiting period
      }
   }

   // Make sure we're not hitting order limits before opening orders
   if(!CheckForMaxOrders())
   {
      return; // Skip trading if we can't manage order limits
   }

   // Check for stop out risk periodically to reduce processing
   static datetime lastStopOutCheck = 0;
   datetime currentTime = TimeCurrent();

   // Only check stop out risk every 10 seconds to reduce processing
   if(EnableStopOutProtection && currentTime - lastStopOutCheck >= 10)
   {
      lastStopOutCheck = currentTime;
      if(CheckStopOutRisk())
      {
         // Log only once per activation to reduce log size
         return; // Skip normal trading when in protection mode
      }
   }

   // Only update order info periodically to reduce processing load
   static datetime lastUpdate = 0;

   // Update only every 5 seconds to reduce processing
   if(currentTime - lastUpdate >= 5)
   {
      lastUpdate = currentTime;

      // Update current order information
      UpdateOrderInfo();

      // Check for max loss protection
      if(EnableMaxLossProtection && CheckMaxLoss())
      {
         Print("Max loss reached: $", g_TotalProfit, ". Closing all trades.");
         CloseAllOrders();
         ResetOrderInfo();

         // Start waiting period
         g_InWaitingPeriod = true;
         g_WaitStartTime = TimeCurrent();
         Print("Starting waiting period of ", WaitMinutesAfterLoss, " minutes.");
         return;
      }

      // Check for stop loss (NO waiting period - normal SL behavior)
      if(EnableStopLoss && CheckStopLoss())
      {
         Print("Stop loss reached: $", g_TotalProfit, ". Closing all trades.");
         CloseAllOrders();
         ResetOrderInfo();
         return;
      }

      // Check take profit
      if(CheckTakeProfit())
      {
         CloseAllOrders();
         ResetOrderInfo();
         return;
      }
   }

   // If no orders exist, open the initial hedge
   if(g_BuyCount == 0 && g_SellCount == 0)
   {
      OpenInitialHedge();
      UpdateOrderInfo();
      return;
   }

   // If we have only buy or only sell orders, complete the hedge
   if(g_BuyCount == 0 && g_SellCount > 0)
   {
      double lotSize = g_SellCount > 1 ? g_StartLot : (Use_DifferentInitialHedgeLots ? CalculateLotSize(InitialHedgeLotSize, false, 0, 0) : g_StartLot);
      // Check if we have enough margin for this trade
      if(CheckMoneyForTrade(Symbol(), lotSize, OP_BUY))
      {
         OpenBuyOrder(lotSize);
         UpdateOrderInfo();
      }
      return;
   }

   if(g_SellCount == 0 && g_BuyCount > 0)
   {
      double lotSize = g_BuyCount > 1 ? g_StartLot : (Use_DifferentInitialHedgeLots ? CalculateLotSize(InitialHedgeLotSize, false, 0, 0) : g_StartLot);
      // Check if we have enough margin for this trade
      if(CheckMoneyForTrade(Symbol(), lotSize, OP_SELL))
      {
         OpenSellOrder(lotSize);
         UpdateOrderInfo();
      }
      return;
   }

   // Open additional orders according to strategy
   double ask = MarketInfo(Symbol(), MODE_ASK);
   double bid = MarketInfo(Symbol(), MODE_BID);

   // Check for new buy signals
   if(g_BuyCount > 0)
   {
      if(Method_A) // Up = Buy
      {
         // Calculate current dynamic grid distance
         double currentDistance = GetDynamicGridDistance(g_GridLevelBuy, true);

         if(ask >= g_HighestBuyPrice + ByPoint(currentDistance) && g_HighestBuyPrice > 0)
         {
            double lot = CalculateNextLotSize(g_BuyCount, g_LastBuyLot);

            // Check if we have enough margin and adjust lot size if needed
            if(CheckMoneyForTrade(Symbol(), lot, OP_BUY))
            {
               if(OpenBuyOrder(lot))
               {
                  // Increment grid level for the next order
                  g_GridLevelBuy++;
               }
               UpdateOrderInfo();
            }
            else
            {
               // Try with a smaller lot size
               lot = AdjustLotSizeByMargin(Symbol(), lot, OP_BUY);
               if(lot > 0 && CheckMoneyForTrade(Symbol(), lot, OP_BUY))
               {
                  if(OpenBuyOrder(lot))
                  {
                     // Increment grid level for the next order
                     g_GridLevelBuy++;
                  }
                  UpdateOrderInfo();
               }
            }
         }
      }
      else // Down = Buy
      {
         // Calculate current dynamic grid distance
         double currentDistance = GetDynamicGridDistance(g_GridLevelBuy, true);

         if(ask <= g_LowestBuyPrice - ByPoint(currentDistance) && g_LowestBuyPrice > 0)
         {
            double lot = CalculateNextLotSize(g_BuyCount, g_LastBuyLot);

            // Check if we have enough margin and adjust lot size if needed
            if(CheckMoneyForTrade(Symbol(), lot, OP_BUY))
            {
               if(OpenBuyOrder(lot))
               {
                  // Increment grid level for the next order
                  g_GridLevelBuy++;
               }
               UpdateOrderInfo();
            }
            else
            {
               // Try with a smaller lot size
               lot = AdjustLotSizeByMargin(Symbol(), lot, OP_BUY);
               if(lot > 0 && CheckMoneyForTrade(Symbol(), lot, OP_BUY))
               {
                  if(OpenBuyOrder(lot))
                  {
                     // Increment grid level for the next order
                     g_GridLevelBuy++;
                  }
                  UpdateOrderInfo();
               }
            }
         }
      }
   }

   // Check for new sell signals
   if(g_SellCount > 0)
   {
      if(!Method_A) // Up = Sell
      {
         // Calculate current dynamic grid distance
         double currentDistance = GetDynamicGridDistance(g_GridLevelSell, false);

         if(bid >= g_HighestSellPrice + ByPoint(currentDistance) && g_HighestSellPrice > 0)
         {
            double lot = CalculateNextLotSize(g_SellCount, g_LastSellLot);

            // Check if we have enough margin and adjust lot size if needed
            if(CheckMoneyForTrade(Symbol(), lot, OP_SELL))
            {
               if(OpenSellOrder(lot))
               {
                  // Increment grid level for the next order
                  g_GridLevelSell++;
               }
               UpdateOrderInfo();
            }
            else
            {
               // Try with a smaller lot size
               lot = AdjustLotSizeByMargin(Symbol(), lot, OP_SELL);
               if(lot > 0 && CheckMoneyForTrade(Symbol(), lot, OP_SELL))
               {
                  if(OpenSellOrder(lot))
                  {
                     // Increment grid level for the next order
                     g_GridLevelSell++;
                  }
                  UpdateOrderInfo();
               }
            }
         }
      }
      else // Down = Sell
      {
         // Calculate current dynamic grid distance
         double currentDistance = GetDynamicGridDistance(g_GridLevelSell, false);

         if(bid <= g_LowestSellPrice - ByPoint(currentDistance) && g_LowestSellPrice > 0)
         {
            double lot = CalculateNextLotSize(g_SellCount, g_LastSellLot);

            // Check if we have enough margin and adjust lot size if needed
            if(CheckMoneyForTrade(Symbol(), lot, OP_SELL))
            {
               if(OpenSellOrder(lot))
               {
                  // Increment grid level for the next order
                  g_GridLevelSell++;
               }
               UpdateOrderInfo();
            }
            else
            {
               // Try with a smaller lot size
               lot = AdjustLotSizeByMargin(Symbol(), lot, OP_SELL);
               if(lot > 0 && CheckMoneyForTrade(Symbol(), lot, OP_SELL))
               {
                  if(OpenSellOrder(lot))
                  {
                     // Increment grid level for the next order
                     g_GridLevelSell++;
                  }
                  UpdateOrderInfo();
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate dynamic grid distance based on level                     |
//+------------------------------------------------------------------+
double GetDynamicGridDistance(int level, bool isBuy)
{
   double distance = GridDistance;

   // Apply multiplier based on level
   if(level > 0 && DistanceMultiplier > 1.0)
   {
      distance = GridDistance * MathPow(DistanceMultiplier, level);
   }

   return distance;
}

//+------------------------------------------------------------------+
//| Handle ERROR_TRADE_TOO_MANY_ORDERS (148)                         |
//+------------------------------------------------------------------+
bool CheckForMaxOrders()
{
   // Check if we're hitting broker's limit
   int totalOrders = OrdersTotal();

   // If we have many orders (approaching broker limits), close some of them
   if(totalOrders > 180)  // Most brokers have 200 order limit, so stay safely below
   {
      Print("Too many orders (", totalOrders, "), reducing to prevent error 148");

      // Close the least profitable orders first
      double worstProfit = 0;
      int worstTicket = 0;

      // Find the most unprofitable position
      for(int i = 0; i < OrdersTotal(); i++)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
            {
               double profit = OrderProfit() + OrderSwap() + OrderCommission();

               // Initialize worst position with the first one or find the worse one
               if(worstTicket == 0 || profit < worstProfit)
               {
                  worstProfit = profit;
                  worstTicket = OrderTicket();
               }
            }
         }
      }

      // Close the worst position if found
      if(worstTicket > 0)
      {
         if(OrderSelect(worstTicket, SELECT_BY_TICKET))
         {
            bool result = false;
            if(OrderType() == OP_BUY)
            {
               result = OrderClose(worstTicket, OrderLots(), MarketInfo(Symbol(), MODE_BID), 30, clrRed);
            }
            else if(OrderType() == OP_SELL)
            {
               result = OrderClose(worstTicket, OrderLots(), MarketInfo(Symbol(), MODE_ASK), 30, clrRed);
            }

            if(!result)
            {
               Print("Error closing worst position: ", GetLastError());
               return false;
            }

            return true; // Successfully reduced order count
         }
      }
      return false; // Could not reduce order count
   }

   return true; // No need to reduce orders
}

//+------------------------------------------------------------------+
//| Get digit count for the symbol                                   |
//+------------------------------------------------------------------+
int GetDigits(string sym = NULL)
{
   if(sym == NULL)
      sym = Symbol();

   return (int)MarketInfo(sym, MODE_DIGITS);
}

//+------------------------------------------------------------------+
//| Calculate grid distance with proper normalization                |
//+------------------------------------------------------------------+
double ByPoint(double x, string sym = NULL)
{
   if(sym == NULL)
      sym = Symbol();

   return NormalizeDouble(x * GetPointValue(sym), GetDigits(sym));
}

//+------------------------------------------------------------------+
//| Get point value adjusted for digits and instrument type          |
//+------------------------------------------------------------------+
double GetPointValue(string sym = NULL)
{
   if(sym == NULL)
      sym = Symbol();

   double point = MarketInfo(sym, MODE_POINT);

   if(point == 0.00001 || point == 0.001)
      point *= 10;

   // Check for gold trading
   if(IsGoldTrading ||
      StringFind(sym, "XAU") == 0 ||
      StringFind(sym, "GOLD") == 0)
   {
      point = 0.1;
   }

   // Check for silver
   if(StringFind(sym, "XAG") == 0 ||
      StringFind(sym, "SILVER") == 0)
   {
      point = 0.1;
   }

   // For instruments with price above 1000
   if(MarketInfo(sym, MODE_BID) > 1000)
      return 1;

   return point;
}

//+------------------------------------------------------------------+
//| Check for symbol volume limits                                    |
//+------------------------------------------------------------------+
bool CheckVolumeLimit(string symbol, double additionalVolume, string &errorMessage)
{
   // Calculate current total volume for the symbol
   double currentVolume = GetSymbolTotalVolume(symbol);

   // Get max volume
   double maxVolume = MarketInfo(symbol, MODE_MAXLOT);

   // Check if adding the new volume would exceed the limit
   if(currentVolume + additionalVolume > maxVolume)
   {
      // Simplified error message to reduce log size
      errorMessage = "Vol limit";
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate total volume for a symbol (all positions and orders)    |
//+------------------------------------------------------------------+
double GetSymbolTotalVolume(string symbol)
{
   double totalVolume = 0;

   // Calculate volume from open positions
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == symbol && OrderMagicNumber() == MagicNumber)
         {
            totalVolume += OrderLots();
         }
      }
   }

   return totalVolume;
}

//+------------------------------------------------------------------+
//| Get maximum allowed volume to add for a symbol                     |
//+------------------------------------------------------------------+
double GetMaxAllowedVolume(string symbol)
{
   // Get current total volume for the symbol
   double currentVolume = GetSymbolTotalVolume(symbol);

   // Calculate remaining available volume
   double remainingVolume = MarketInfo(symbol, MODE_MAXLOT) - currentVolume;

   // Apply minimum volume and lot step constraints
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);

   if(remainingVolume < minLot)
      return 0; // Can't open any position

   // Round down to the nearest lot step
   double allowedLot = MathFloor(remainingVolume / lotStep) * lotStep;

   // Ensure we don't exceed maximum lot size per trade
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   allowedLot = MathMin(allowedLot, maxLot);

   return allowedLot;
}

//+------------------------------------------------------------------+
//| Check for stop out risk and take preventive action               |
//+------------------------------------------------------------------+
bool CheckStopOutRisk()
{
   // Get current margin level
   double equity = AccountEquity();
   double margin = AccountMargin();

   // Avoid division by zero
   if(margin <= 0)
      return false;

   double marginLevel = (equity / margin) * 100;

   // Get broker's stop out level
   double stopOutLevel = AccountStopoutLevel();

   // If not available, use a conservative default of 20%
   if(stopOutLevel <= 0)
      stopOutLevel = 20;

   // Only log when critical - reduce log file size
   if(marginLevel < StopOutProtectionLevel)
   {
      Print("WARNING: Low margin level: ", marginLevel, "%, StopOut: ", stopOutLevel, "%, Protection: ", StopOutProtectionLevel, "%");

      // Find the most unprofitable position and reduce it
      ReduceWorstPosition();
      return true;
   }

   // No immediate risk
   return false;
}

//+------------------------------------------------------------------+
//| Reduce the worst performing position to prevent stop out         |
//+------------------------------------------------------------------+
void ReduceWorstPosition()
{
   int worstTicket = 0;
   double worstProfit = 0;
   double worstVolume = 0;
   int worstType = -1;

   // Find the most unprofitable position
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();

            // Initialize worst position with the first one
            if(worstTicket == 0 || profit < worstProfit)
            {
               worstProfit = profit;
               worstTicket = OrderTicket();
               worstVolume = OrderLots();
               worstType = OrderType();
            }
         }
      }
   }

   // If we found a position to reduce
   if(worstTicket > 0)
   {
      // Calculate how much to reduce
      double closeVolume = worstVolume * 0.5; // Close half of the position

      // Ensure minimum lot size
      if(closeVolume < MarketInfo(Symbol(), MODE_MINLOT))
         closeVolume = MarketInfo(Symbol(), MODE_MINLOT);

      // If closing would leave less than min lot, close the entire position
      if(worstVolume - closeVolume < MarketInfo(Symbol(), MODE_MINLOT))
         closeVolume = worstVolume;

      // Close part of the position
      if(OrderSelect(worstTicket, SELECT_BY_TICKET))
      {
         // Determine closing order type
         int closeType = (worstType == OP_BUY) ? OP_SELL : OP_BUY;
         double closePrice = (worstType == OP_BUY) ?
                           MarketInfo(Symbol(), MODE_BID) :
                           MarketInfo(Symbol(), MODE_ASK);

         // Close the position
         bool result = OrderClose(worstTicket, closeVolume, closePrice, 30, clrRed);

         if(!result)
         {
            Print("Error closing partial position for stop out protection: ", GetLastError());
         }
         else
         {
            // Only log essential information for stop out protection
            Print("SO-Prot: #", worstTicket, " ", closeVolume);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there's enough money for the trade operation            |
//+------------------------------------------------------------------+
bool CheckMoneyForTrade(string symb, double lots, int type)
{
   // Skip check if margin safety buffer is disabled
   if(!EnableMarginSafetyBuffer)
      return true;

   // Get price based on order type
   double price = (type == OP_BUY) ? MarketInfo(symb, MODE_ASK) : MarketInfo(symb, MODE_BID);

   // Calculate required margin using built-in MT4 function
   double margin = MarketInfo(symb, MODE_MARGINREQUIRED) * lots;

   // Add safety buffer
   margin *= (1 + MarginSafetyPercent / 100);

   // Get account info
   double equity = AccountEquity();
   double free_margin = AccountFreeMargin();

   // If there are insufficient funds to perform the operation
   if(margin > free_margin)
   {
      // Report the error in a condensed format to reduce log size
      Print("Not enough money for ", (type == OP_BUY ? "BUY" : "SELL"), " ", lots, " ", symb,
            " (Free: ", free_margin, ", Need: ", margin, ")");
      return false;
   }

   // Checking successful
   return true;
}

//+------------------------------------------------------------------+
//| Adjust lot size based on available margin                        |
//+------------------------------------------------------------------+
double AdjustLotSizeByMargin(string symbol, double requestedLot, int type)
{
   // Skip adjustment if margin safety buffer is disabled
   if(!EnableMarginSafetyBuffer)
      return requestedLot;

   // Get price based on order type
   double price = (type == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);

   // Get free margin
   double freeMargin = AccountFreeMargin();

   // Apply safety factor
   freeMargin *= (1 - MarginSafetyPercent / 100);

   // Calculate maximum lot size we can open
   double marginPerLot = MarketInfo(symbol, MODE_MARGINREQUIRED);

   if(marginPerLot <= 0)
   {
      Print("Failed to calculate margin per lot");
      return 0;
   }

   // Maximum lot based on margin
   double maxLot = freeMargin / marginPerLot;

   // Get symbol lot restrictions
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLotAllowed = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);

   // Adjust lot to symbol restrictions
   maxLot = MathMin(maxLot, maxLotAllowed);

   // Normalize the requested lot to the symbol's lot step
   double adjustedLot = MathFloor(requestedLot / lotStep) * lotStep;

   // Ensure lot is within bounds
   adjustedLot = MathMax(minLot, MathMin(adjustedLot, maxLot));

   // Don't log routine adjustments to reduce log file size

   return adjustedLot;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on parameters                           |
//+------------------------------------------------------------------+
double CalculateLotSize(double fixedLot, bool useMM, double risk, double balance, string symbol = "")
{
   if(symbol == "")
      symbol = Symbol();

   double lot;

   if(useMM)
   {
      if(balance == 0)
         balance = AccountFreeMargin();

      lot = MathMin(MathMax((MathRound((balance * risk / 1000 / 100)
                                     / MarketInfo(symbol, MODE_LOTSTEP)) * MarketInfo(symbol, MODE_LOTSTEP)),
                          MarketInfo(symbol, MODE_MINLOT)), MarketInfo(symbol, MODE_MAXLOT));
   }
   else
   {
      lot = MathMin(MathMax((MathRound(fixedLot / MarketInfo(symbol, MODE_LOTSTEP)) * MarketInfo(symbol, MODE_LOTSTEP)),
                          MarketInfo(symbol, MODE_MINLOT)), MarketInfo(symbol, MODE_MAXLOT));
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Calculate next lot size based on multiplier                      |
//+------------------------------------------------------------------+
double CalculateNextLotSize(int orderCount, double lastLot)
{
   // Always base the calculations on g_StartLot (manual lot size)
   // instead of propagating the initial hedge lot size
   double lot = MathPow(Multiplier, orderCount) * g_StartLot;

   // Enforce max lot limit if set
   if(MaxLotsPerOrder > 0 && lot > MaxLotsPerOrder)
   {
      lot = MaxLotsPerOrder;
   }

   // Normalize to symbol lot step
   lot = MathFloor(lot / MarketInfo(Symbol(), MODE_LOTSTEP)) * MarketInfo(Symbol(), MODE_LOTSTEP);

   // Ensure minimum lot size
   if(lot < MarketInfo(Symbol(), MODE_MINLOT))
      lot = MarketInfo(Symbol(), MODE_MINLOT);

   return lot;
}

//+------------------------------------------------------------------+
//| Check if max loss has been reached                               |
//+------------------------------------------------------------------+
bool CheckMaxLoss()
{
   if(g_BuyCount + g_SellCount == 0)
      return false;

   if(MaxLossAmount <= 0)
      return false;

   // Check if total profit is negative and exceeds max loss
   if(g_TotalProfit < 0 && MathAbs(g_TotalProfit) >= MaxLossAmount)
   {
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if stop loss has been reached                              |
//+------------------------------------------------------------------+
bool CheckStopLoss()
{
   if(g_BuyCount + g_SellCount == 0)
      return false;

   double sl = 0;

   if(PercentageSL)
   {
      if(StopLoss_Percentage <= 0)
         return false;

      sl = g_StartBalance * StopLoss_Percentage / 100;
   }
   else
   {
      if(StopLoss_Manual <= 0)
         return false;

      sl = StopLoss_Manual;
   }

   // Check if total profit is negative and exceeds stop loss
   if(g_TotalProfit < 0 && MathAbs(g_TotalProfit) >= sl)
   {
      Print("SL: $", g_TotalProfit);
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Open a buy order                                                 |
//+------------------------------------------------------------------+
bool OpenBuyOrder(double lot)
{
   // Check max lots per chart limit
   if(MaxOrdersLotsPerChart > 0 && (g_TotalLots + lot) > MaxOrdersLotsPerChart)
   {
      // Don't log routine limitations to reduce log file size
      return false;
   }

   // Check max orders limit
   if(MaxOrders > 0 && (g_BuyCount + g_SellCount + 1) > MaxOrders)
   {
      // Don't log routine limitations to reduce log file size
      return false;
   }

   // Check symbol volume limit
   string errorMsg;
   if(!CheckVolumeLimit(Symbol(), lot, errorMsg))
   {
      // Simplify volume limit error logging

      // Try with a smaller lot size
      double maxAllowedLot = GetMaxAllowedVolume(Symbol());
      if(maxAllowedLot > 0)
      {
         // No need to log routine lot adjustments
         lot = maxAllowedLot;
      }
      else
      {
         return false;
      }
   }

   // Place the order
   int ticket = OrderSend(Symbol(), OP_BUY, lot, MarketInfo(Symbol(), MODE_ASK), 30, 0, 0,
                        "Super Hedge Fighter MT4", MagicNumber, 0, clrBlue);

   if(ticket < 0)
   {
      // Only log non-trivial errors
      int error = GetLastError();
      if(error != ERR_NO_RESULT && error != ERR_COMMON_ERROR)
      {
         // If we get error 148, try to reduce order count
         if(error == 148) // ERR_TRADE_TOO_MANY_ORDERS
         {
            Print("Buy err 148 - too many orders");
            CheckForMaxOrders(); // Try to reduce order count
         }
         else
         {
            Print("Buy err: ", error);
         }
      }
      return false;
   }

   // Log only essential information
   if(ticket > 0)
      Print("Buy #", ticket, " ", lot);

   return (ticket > 0);
}

//+------------------------------------------------------------------+
//| Open a sell order                                                |
//+------------------------------------------------------------------+
bool OpenSellOrder(double lot)
{
   // Check max lots per chart limit
   if(MaxOrdersLotsPerChart > 0 && (g_TotalLots + lot) > MaxOrdersLotsPerChart)
   {
      // Don't log routine limitations to reduce log file size
      return false;
   }

   // Check max orders limit
   if(MaxOrders > 0 && (g_BuyCount + g_SellCount + 1) > MaxOrders)
   {
      // Don't log routine limitations to reduce log file size
      return false;
   }

   // Check symbol volume limit
   string errorMsg;
   if(!CheckVolumeLimit(Symbol(), lot, errorMsg))
   {
      // Simplify volume limit error logging

      // Try with a smaller lot size
      double maxAllowedLot = GetMaxAllowedVolume(Symbol());
      if(maxAllowedLot > 0)
      {
         // No need to log routine lot adjustments
         lot = maxAllowedLot;
      }
      else
      {
         return false;
      }
   }

   // Place the order
   int ticket = OrderSend(Symbol(), OP_SELL, lot, MarketInfo(Symbol(), MODE_BID), 30, 0, 0,
                        "Super Hedge Fighter MT4", MagicNumber, 0, clrRed);

   if(ticket < 0)
   {
      // Only log non-trivial errors
      int error = GetLastError();
      if(error != ERR_NO_RESULT && error != ERR_COMMON_ERROR)
      {
         // If we get error 148, try to reduce order count
         if(error == 148) // ERR_TRADE_TOO_MANY_ORDERS
         {
            Print("Sell err 148 - too many orders");
            CheckForMaxOrders(); // Try to reduce order count
         }
         else
         {
            Print("Sell err: ", error);
         }
      }
      return false;
   }

   // Log only essential information
   if(ticket > 0)
      Print("Sell #", ticket, " ", lot);

   return (ticket > 0);
}

//+------------------------------------------------------------------+
//| Open initial hedge (both buy and sell)                           |
//+------------------------------------------------------------------+
void OpenInitialHedge()
{
   // Calculate the initial lot size (may be different from standard lots)
   double initialLot = Use_DifferentInitialHedgeLots ?
                       CalculateLotSize(InitialHedgeLotSize, false, 0, 0) :
                       g_StartLot;

   if(Method_A) // Start with sell first in Method A
   {
      // Check if we have enough margin for both trades
      if(CheckMoneyForTrade(Symbol(), initialLot * 2, OP_SELL))
      {
         OpenSellOrder(initialLot);
         OpenBuyOrder(initialLot);
      }
      else
      {
         // Try with a smaller lot size
         double adjustedLot = AdjustLotSizeByMargin(Symbol(), initialLot, OP_SELL);
         if(adjustedLot > 0 && CheckMoneyForTrade(Symbol(), adjustedLot * 2, OP_SELL))
         {
            OpenSellOrder(adjustedLot);
            OpenBuyOrder(adjustedLot);
         }
      }
   }
   else // Start with buy first in Method B
   {
      // Check if we have enough margin for both trades
      if(CheckMoneyForTrade(Symbol(), initialLot * 2, OP_BUY))
      {
         OpenBuyOrder(initialLot);
         OpenSellOrder(initialLot);
      }
      else
      {
         // Try with a smaller lot size
         double adjustedLot = AdjustLotSizeByMargin(Symbol(), initialLot, OP_BUY);
         if(adjustedLot > 0 && CheckMoneyForTrade(Symbol(), adjustedLot * 2, OP_BUY))
         {
            OpenBuyOrder(adjustedLot);
            OpenSellOrder(adjustedLot);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update current order information                                 |
//+------------------------------------------------------------------+
void UpdateOrderInfo()
{
   // Reset values
   g_BuyCount = 0;
   g_SellCount = 0;
   g_HighestBuyPrice = 0;
   g_LowestBuyPrice = 0;
   g_HighestSellPrice = 0;
   g_LowestSellPrice = 0;
   g_TotalLots = 0;
   g_TotalProfit = 0;
   g_HistoryProfit = 0;
   g_LastBuyLot = 0;
   g_LastSellLot = 0;

   // Get history profit
   int totalDeals = OrdersHistoryTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderMagicNumber() == MagicNumber &&
            OrderSymbol() == Symbol() &&
            OrderCloseTime() >= g_StartTime)
         {
            g_HistoryProfit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }

   // Process open positions
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber &&
            OrderSymbol() == Symbol())
         {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            double lot = OrderLots();
            double openPrice = OrderOpenPrice();

            g_TotalProfit += profit;
            g_TotalLots += lot;

            if(OrderType() == OP_BUY)
            {
               g_BuyCount++;
               g_LastBuyLot = lot;

               if(openPrice > g_HighestBuyPrice || g_HighestBuyPrice == 0)
                  g_HighestBuyPrice = openPrice;

               if(openPrice < g_LowestBuyPrice || g_LowestBuyPrice == 0)
                  g_LowestBuyPrice = openPrice;
            }
            else if(OrderType() == OP_SELL)
            {
               g_SellCount++;
               g_LastSellLot = lot;

               if(openPrice > g_HighestSellPrice || g_HighestSellPrice == 0)
                  g_HighestSellPrice = openPrice;

               if(openPrice < g_LowestSellPrice || g_LowestSellPrice == 0)
                  g_LowestSellPrice = openPrice;
            }
         }
      }
   }

   Comment("Orders: ", g_BuyCount + g_SellCount,
           " (Buy: ", g_BuyCount, ", Sell: ", g_SellCount, ")",
           "\nTotal profit: $", DoubleToString(g_TotalProfit, 2),
           "\nTotal lots: ", DoubleToString(g_TotalLots, 2));
}

//+------------------------------------------------------------------+
//| Check if take profit has been reached                            |
//+------------------------------------------------------------------+
bool CheckTakeProfit()
{
   if(g_BuyCount + g_SellCount == 0)
      return false;

   double tp = 0;

   if(PercentageTP)
   {
      if(TakeProfit_Percentage <= 0)
         return false;

      tp = g_StartBalance * TakeProfit_Percentage / 100;
   }
   else
   {
      if(TakeProfit_Manual <= 0)
         return false;

      tp = TakeProfit_Manual;
   }

   if(g_TotalProfit > tp)
   {
      // Minimal logging for take profit
      Print("TP: $", g_TotalProfit);
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Close all open orders with the magic number                      |
//+------------------------------------------------------------------+
void CloseAllOrders()
{
   for(int attempt = 0; attempt < 3; attempt++) // Try multiple times
   {
      bool allClosed = true;

      // First pass - close positions
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderMagicNumber() == MagicNumber &&
               OrderSymbol() == Symbol())
            {
               // Close the position
               bool result = false;

               if(OrderType() == OP_BUY)
               {
                  result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(Symbol(), MODE_BID), 30, clrRed);
                  if(!result) {
                     Print("Error closing BUY order: ", GetLastError());
                  }
               }
               else if(OrderType() == OP_SELL)
               {
                  result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(Symbol(), MODE_ASK), 30, clrRed);
                  if(!result) {
                     Print("Error closing SELL order: ", GetLastError());
                  }
               }
               else
               {
                  // Handle pending orders
                  result = OrderDelete(OrderTicket());
                  if(!result) {
                     Print("Error deleting pending order: ", GetLastError());
                  }
               }

               if(!result)
               {
                  // Log only if truly critical
                  if(GetLastError() != ERR_NO_RESULT)
                     Print("Err close #", OrderTicket());
                  allClosed = false;
               }
            }
         }
      }

      if(allClosed)
         break;

      Sleep(200); // Small delay before next attempt
   }

   // Minimal logging when orders are closed
   int closed = g_BuyCount + g_SellCount;
   if(closed > 0)
      Print("Closed ", closed, " orders");
}

//+------------------------------------------------------------------+
//| Reset order information after closing all orders                 |
//+------------------------------------------------------------------+
void ResetOrderInfo()
{
   // Set new start time and save it
   g_StartTime = TimeCurrent();
   GlobalVariableSet(g_TimeName, (double)(int)g_StartTime);

   // Update balance and save it
   g_StartBalance = AccountBalance();
   GlobalVariableSet(g_BalanceName, g_StartBalance);

   // Update starting lot size
   g_StartLot = CalculateLotSize(LotSize_Manual, AutoLot_WithPercentage, LotSize_Percentage, g_StartBalance);

   // Reset all counters and variables
   g_BuyCount = 0;
   g_SellCount = 0;
   g_HighestBuyPrice = 0;
   g_LowestBuyPrice = 0;
   g_HighestSellPrice = 0;
   g_LowestSellPrice = 0;
   g_TotalLots = 0;
   g_TotalProfit = 0;
   g_HistoryProfit = 0;
   g_LastBuyLot = 0;
   g_LastSellLot = 0;
   g_GridLevelBuy = 0;
   g_GridLevelSell = 0;
   g_CurrentGridDistance = GridDistance;

   // Minimal logging for reset
   Print("Reset: Bal=", g_StartBalance);
}
