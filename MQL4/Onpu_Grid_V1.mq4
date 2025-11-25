#property version 1.0

// Input parameters
input bool Trade_Buy = true;
input bool Trade_Sell = true;
bool Full_Trade = true;  // New button for full auto-trade
bool Stop_Trade = false;  // New button to stop all trades
bool Start_Trade = true;  // New button to start trading
input double Start_Lot_Size = 0.01;
input double Lot_Continue = 0.02;
input double Lot_Add = 0.01;
input int Incase_Lot_Every_N = 10;
input int CAT = 40;
input int W = 10;
input int Take_Profit_Mode4 = 500;
input int Maximum_Grid = 10;
input int Spread_Limit = 30;         // Maximum allowed spread
input int Magic_Number = 9999;       // Magic number for orders
input int DD_Control = 40; //DD Control
input double Stop_Loss = 500;        // New: Stop Loss in points
input double Initial_Grid_Distance = 300;  // New: Grid distance in points (ใช้เป็นค่าเริ่มต้น)
double Grid_Distance;                      // เปลี่ยนเป็น double ปกติ

// Variables
int orders = 0;
double current_lot = Start_Lot_Size;
double initial_balance, max_balance, max_drawdown;
bool Hedging_Active = false;  // New: Hedging control
int Hedge_Ticket = -1;        // New: Store hedge order ticket

//+------------------------------------------------------------------+
//| Function to count orders for current symbol and magic number     |
//+------------------------------------------------------------------+
int GetOrderCount()
{
   int count = 0;
   for (int i = 0; i < OrdersTotal(); i++)
   {
      if (OrderSelect(i, SELECT_BY_POS))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("EA Initialized.");
   initial_balance = AccountBalance();
   max_balance = initial_balance;
   max_drawdown = 0;
   Grid_Distance = Initial_Grid_Distance;  // กำหนดค่าเริ่มต้น
   return(INIT_SUCCEEDED);
  }

void CloseAllTrades()
  {
   for (int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if (OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number)
        OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3);
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (Stop_Trade) { CloseAllTrades(); Full_Trade = false; return; }
   if (!Start_Trade) return;

   orders = GetOrderCount();
   double equity = AccountEquity();
   double balance = AccountBalance();
   double margin = AccountMargin();
   double free_margin = AccountFreeMargin();
   double margin_percent = 0;
   if (margin > 0)
      margin_percent = (equity / margin) * 100;

   double drawdown = (max_balance - equity) / max_balance * 100;
   if (equity > max_balance) max_balance = equity;
   max_drawdown = drawdown;

   Comment(
      "Balance: ", DoubleToString(balance, 2),
      " | Equity: ", DoubleToString(equity, 2),
      " | Margin: ", DoubleToString(margin, 2),
      " | Free Margin: ", DoubleToString(free_margin, 2),
      " | Free Margin %: ", DoubleToString(margin_percent, 2), "%",
      " | DD: ", DoubleToString(max_drawdown, 2), "%",
      " | Hedging: ", (Hedging_Active ? "Active" : "Inactive")
   );

   if (max_drawdown > 30 && !Hedging_Active)
   {
      Print("Activating hedging due to DD > 30%");
      if (OrderSend(Symbol(), OP_SELL, current_lot, Bid, 3, 0, 0, "Hedge", Magic_Number) > 0)
         Hedging_Active = true;
   }
   if (max_drawdown < 20 && Hedging_Active)
   {
      Print("Deactivating hedge due to DD < 20%");
      Hedging_Active = false;
   }

   if (drawdown > 20)
      Grid_Distance = Initial_Grid_Distance * 1.5;
   else
      Grid_Distance = Initial_Grid_Distance;

   if (Trade_Buy && orders < Maximum_Grid)
      OrderSend(Symbol(), OP_BUY, current_lot, Ask, 3, 0, Ask + Take_Profit_Mode4 * Point, "PG", Magic_Number);

   if (Trade_Sell && orders < Maximum_Grid)
      OrderSend(Symbol(), OP_SELL, current_lot, Bid, 3, 0, Bid - Take_Profit_Mode4 * Point, "PG", Magic_Number);
}
