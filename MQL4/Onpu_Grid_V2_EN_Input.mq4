//+------------------------------------------------------------------+
//|                                         Onpu_Grid_V2.3.2.mq4 |
//|                                     Copyright 2025, Onpu Dev Team |
//|                                     Version 2.3.2 (Max Lot Safe)  |
//+------------------------------------------------------------------+
#property copyright "Onpu Grid V2.3.1 (Stable & Safe)"
#property version   "2.31"
#property strict

// ==========================================================================
// [SECTION 1] : USER INPUTS (SETTINGS)
// ==========================================================================
// --- 1.1 Trading Mode ---
input bool   Trade_Buy           = true;       // Enable Buy Trades
input bool   Trade_Sell          = true;       // Enable Sell Trades
input int    Magic_Number        = 9999;       // EA Magic Number (Unique ID)
input int    Slippage            = 30;         // Max Slippage (Points)

// --- 1.2 Grid & Lot Settings ---
input double Start_Lot_Size      = 0.01;       // Starting Lot Size
input double Lot_Add             = 0.01;       // Lot Adder (e.g., 0.01 for +0.01)
input double Max_Lot_Limit       = 0.10;       // [NEW] Maximum Lot Size Limit
input int    Maximum_Grid        = 10;         // Max Orders Per Side
input int    Grid_Distance       = 1000;       // Grid Distance (Points)

// --- 1.3 Risk Management ---
input double Target_Money        = 10.0;       // Target Profit ($) to Close Side
input double Grand_Target_Equity = 600.0;      // Equity Goal ($) to Stop EA
input int    DD_Percentage_Cut   = 40;         // Max Drawdown % (Hard Stop)
input int    Safety_TP           = 2000;       // Safety TP (Points) sent to broker
input double Stop_Loss           = 0;          // Stop Loss per trade (0 = Disabled)

// --- 1.4 Visual Settings ---
input int    Dashboard_X         = 150;        // Dashboard X Offset
input int    Dashboard_Y         = 20;         // Dashboard Y Offset
input color  Color_Text          = clrGold;    // Text Color
input bool   Auto_Color          = true;       // Auto Dark Mode

// ==========================================================================
// [SECTION 2] : SYSTEM VARIABLES
// ==========================================================================
double max_balance;
bool   System_Enabled = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Onpu V2.3.2 (Max Lot Safety) Loaded.");
   max_balance = AccountBalance();
   
   if(Auto_Color) SetupChart();
   CreateGUI();
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "Onpu_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Event Handler: On-Chart Buttons                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      // Button Start/Stop
      if(sparam == "Onpu_Btn_Switch")
        {
         System_Enabled = !System_Enabled;
         UpdateButtonState();
         PlaySound("tick.wav");
         ChartRedraw();
        }
      // Button Close All
      if(sparam == "Onpu_Btn_CloseAll")
        {
         if(MessageBox("CONFIRM CLOSE ALL TRADES?", "Emergency", MB_YESNO|MB_ICONWARNING) == IDYES)
           {
            CloseAllTrades();
            PlaySound("alert.wav");
            ChartRedraw();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function (Main Logic)                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDashboard(); 
   RefreshRates();

   if(!System_Enabled) return;

   // 1. Check Profit Targets
   CheckProfitAndTargets();

   // 2. Check Drawdown Safety
   double equity = AccountEquity();
   double balance = AccountBalance();
   if(equity > max_balance) max_balance = equity;
   
   double drawdown_percent = 0;
   if(balance > 0) drawdown_percent = ((balance - equity) / balance) * 100;

   // 3. SAFETY CUT
   if(drawdown_percent >= DD_Percentage_Cut)
     {
      string msg = "⚠️ DANGER: Drawdown " + DoubleToString(drawdown_percent,2) + "% Limit Reached! Closing ALL.";
      Print(msg);
      Alert(msg);
      
      CloseAllTrades();
      System_Enabled = false; 
      UpdateButtonState();
      return;
     }

   // 4. BUY LOGIC
   if(Trade_Buy)
     {
      int buy_count = CountOrders(OP_BUY);
      double last_buy_price = FindLastOpenPrice(OP_BUY);
      
      // [LOGIC UPDATE] Calculate Lot with Max Limit
      double raw_lot = Start_Lot_Size + (buy_count * Lot_Add); 
      double next_buy_lot = (raw_lot > Max_Lot_Limit) ? Max_Lot_Limit : raw_lot;
      
      double price_tp = NormalizeDouble(Ask + Safety_TP * Point, Digits);
      double price_sl = (Stop_Loss == 0) ? 0 : NormalizeDouble(Ask - Stop_Loss * Point, Digits);
      
      string comment = "Onpu_" + IntegerToString(Magic_Number) + "_B" + IntegerToString(buy_count+1);

      if(buy_count == 0)
        {
         if(CheckMoney(next_buy_lot)) OpenOrder(OP_BUY, next_buy_lot, Ask, price_sl, price_tp, comment);
        }
      else if(buy_count < Maximum_Grid && Ask <= (last_buy_price - (Grid_Distance * Point)))
        {
         if(CheckMoney(next_buy_lot)) OpenOrder(OP_BUY, next_buy_lot, Ask, price_sl, price_tp, comment);
        }
     }

   // 5. SELL LOGIC
   if(Trade_Sell)
     {
      int sell_count = CountOrders(OP_SELL);
      double last_sell_price = FindLastOpenPrice(OP_SELL);
      
      // [LOGIC UPDATE] Calculate Lot with Max Limit
      double raw_lot = Start_Lot_Size + (sell_count * Lot_Add);
      double next_sell_lot = (raw_lot > Max_Lot_Limit) ? Max_Lot_Limit : raw_lot;

      double price_tp = NormalizeDouble(Bid - Safety_TP * Point, Digits);
      double price_sl = (Stop_Loss == 0) ? 0 : NormalizeDouble(Bid + Stop_Loss * Point, Digits);

      string comment = "Onpu_" + IntegerToString(Magic_Number) + "_S" + IntegerToString(sell_count+1);

      if(sell_count == 0)
        {
         if(CheckMoney(next_sell_lot)) OpenOrder(OP_SELL, next_sell_lot, Bid, price_sl, price_tp, comment);
        }
      else if(sell_count < Maximum_Grid && Bid >= (last_sell_price + (Grid_Distance * Point)))
        {
         if(CheckMoney(next_sell_lot)) OpenOrder(OP_SELL, next_sell_lot, Bid, price_sl, price_tp, comment);
        }
     }
  }

// ==========================================================================
// [SECTION 3] : HELPER FUNCTIONS
// ==========================================================================

void OpenOrder(int type, double lot, double price, double sl, double tp, string cmt)
{
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lot, price, Slippage, sl, tp, cmt, Magic_Number, 0, (type==OP_BUY)?clrBlue:clrRed);
   
   if(ticket > 0) {
      if(cmt == "Onpu_"+IntegerToString(Magic_Number)+"_B1" || cmt == "Onpu_"+IntegerToString(Magic_Number)+"_S1") {
         Alert("📢 EA STARTED: New Position Opened [" + Symbol() + "]");
      }
   } else {
      Print("OrderSend Failed: Error ", GetLastError());
   }
}

bool CheckMoney(double lot) {
   double free_margin = AccountFreeMargin();
   double required_margin = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lot;
   if(free_margin < required_margin) {
      Print("Not enough money for Lot ", lot);
      return false;
   }
   return true;
}

int CountOrders(int type) {
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type) count++;
      }
   }
   return count;
}

double FindLastOpenPrice(int type) {
   double last_price = 0;
   int last_ticket = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type) {
            if(OrderTicket() > last_ticket) {
               last_ticket = OrderTicket();
               last_price = OrderOpenPrice();
            }
         }
      }
   }
   return last_price;
}

void CloseSpecificSide(int type) {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type) {
            RefreshRates(); 
            double close_price = (type == OP_BUY) ? Bid : Ask;
            bool res = OrderClose(OrderTicket(), OrderLots(), close_price, Slippage, clrGreen);
            if(!res) Print("Close Side Error: ", GetLastError());
         }
      }
   }
}

void CloseAllTrades() {
   int total = OrdersTotal();
   if(total == 0) return;
   
   Print("--- CLOSING ALL TRADES ---");
   for(int i = total - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number) {
            RefreshRates(); 
            bool res = false;
            int type = OrderType();
            
            if(type == OP_BUY) res = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrRed);
            else if(type == OP_SELL) res = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrRed);
            else res = OrderDelete(OrderTicket());
            
            if(!res) Alert("ERROR Closing Ticket ", OrderTicket(), ": ", GetLastError());
         }
      }
   }
}

void CheckProfitAndTargets() {
   double sum_buy_profit = 0;
   double sum_sell_profit = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number) {
            if(OrderType() == OP_BUY) sum_buy_profit += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_SELL) sum_sell_profit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   
   // Close by Target Money
   if(sum_buy_profit >= Target_Money) {
      CloseSpecificSide(OP_BUY);
      Print("Closed Buy Side. Profit: ", sum_buy_profit);
   }
   if(sum_sell_profit >= Target_Money) {
      CloseSpecificSide(OP_SELL);
      Print("Closed Sell Side. Profit: ", sum_sell_profit);
   }
   
   // Close by Grand Target
   if(AccountEquity() >= Grand_Target_Equity) {
      string msg = "🏆 CONGRATULATIONS! Grand Target ($" + DoubleToString(Grand_Target_Equity, 2) + ") Reached. Stopping EA.";
      Print(msg);
      Alert(msg);
      
      CloseAllTrades();
      System_Enabled = false;
      UpdateButtonState();
   }
}

// ==========================================================================
// [SECTION 4] : DASHBOARD GUI
// ==========================================================================

void SetupChart() {
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrLime);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrLime); 
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrRed);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);
}

void CreateGUI() {
   // BG (Resized for vertical buttons)
   ObjectCreate(0, "Onpu_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_XDISTANCE, Dashboard_X);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_YDISTANCE, Dashboard_Y);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_YSIZE, 280); 
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Labels
   CreateLabel("Onpu_Lbl_Title", ":: ONPU GRID V2.3.2 ::", 20, 15, clrGold, 12);
   CreateLabel("Onpu_Lbl_Magic", "Magic No : " + IntegerToString(Magic_Number), 20, 40, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Status", "Status: RUNNING", 20, 60, clrLime, 10);
   CreateLabel("Onpu_Lbl_Bal", "Balance: 0.00", 20, 80, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Eq", "Equity: 0.00", 20, 100, clrWhite, 9);
   CreateLabel("Onpu_Lbl_DD", "DD: 0.00% / Limit " + IntegerToString(DD_Percentage_Cut) + "%", 20, 120, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Profit", "Profit: 0.00 / Target " + DoubleToString(Target_Money, 2), 20, 140, clrYellow, 9);
   CreateLabel("Onpu_Lbl_Orders", "B: 0 | S: 0", 20, 160, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Goal", "GOAL: " + DoubleToString(Grand_Target_Equity, 2), 20, 180, clrAqua, 9);

   // Buttons (Vertical Layout)
   CreateButton("Onpu_Btn_Switch", "STOP EA", 20, 205, 190, 30, clrRed);
   CreateButton("Onpu_Btn_CloseAll", "CLOSE ALL", 20, 240, 190, 30, clrOrangeRed);
   ChartRedraw();
}

void UpdateDashboard() {
   double bal = AccountBalance();
   double eq = AccountEquity();
   double dd = 0;
   if(bal > 0) dd = ((bal - eq) / bal) * 100;

   ObjectSetString(0, "Onpu_Lbl_Bal", OBJPROP_TEXT, "Balance: " + DoubleToString(bal, 2));
   ObjectSetString(0, "Onpu_Lbl_Eq", OBJPROP_TEXT, "Equity: " + DoubleToString(eq, 2));
   
   string dd_text = "DD: " + DoubleToString(dd, 2) + "% / Limit " + IntegerToString(DD_Percentage_Cut) + "%";
   ObjectSetString(0, "Onpu_Lbl_DD", OBJPROP_TEXT, dd_text);
   
   if(dd > 20) ObjectSetInteger(0, "Onpu_Lbl_DD", OBJPROP_COLOR, clrRed);
   else ObjectSetInteger(0, "Onpu_Lbl_DD", OBJPROP_COLOR, clrWhite);

   int b_cnt = CountOrders(OP_BUY);
   int s_cnt = CountOrders(OP_SELL);
   ObjectSetString(0, "Onpu_Lbl_Orders", OBJPROP_TEXT, "Buy: " + IntegerToString(b_cnt) + " | Sell: " + IntegerToString(s_cnt));
   
   double sum_profit = 0;
   for(int i=0; i<OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderMagicNumber()==Magic_Number && OrderSymbol()==Symbol())
            sum_profit += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }
   string profit_text = "Profit: " + DoubleToString(sum_profit, 2) + " / Target " + DoubleToString(Target_Money, 2);
   ObjectSetString(0, "Onpu_Lbl_Profit", OBJPROP_TEXT, profit_text);
}

void UpdateButtonState() {
   if(System_Enabled) {
      ObjectSetString(0, "Onpu_Btn_Switch", OBJPROP_TEXT, "STOP EA");
      ObjectSetInteger(0, "Onpu_Btn_Switch", OBJPROP_BGCOLOR, clrRed);
      ObjectSetString(0, "Onpu_Lbl_Status", OBJPROP_TEXT, "Status: RUNNING");
      ObjectSetInteger(0, "Onpu_Lbl_Status", OBJPROP_COLOR, clrLime);
   } else {
      ObjectSetString(0, "Onpu_Btn_Switch", OBJPROP_TEXT, "START EA");
      ObjectSetInteger(0, "Onpu_Btn_Switch", OBJPROP_BGCOLOR, clrGreen);
      ObjectSetString(0, "Onpu_Lbl_Status", OBJPROP_TEXT, "Status: STOPPED");
      ObjectSetInteger(0, "Onpu_Lbl_Status", OBJPROP_COLOR, clrRed);
   }
   ChartRedraw();
}

void CreateLabel(string name, string text, int x, int y, color c, int size) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Dashboard_X + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Dashboard_Y + y);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
}

void CreateButton(string name, string text, int x, int y, int w, int h, color bg) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Dashboard_X + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Dashboard_Y + y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}