//+------------------------------------------------------------------+
//|                                         Onpu_Grid_V1.2_MT5.mq5 |
//|                                     Copyright 2025, Onpu Dev Team |
//|                                        Converted to MQL5 Native   |
//+------------------------------------------------------------------+
#property copyright "Onpu Grid V1.2 News Scan"
#property version   "1.2"
#property strict

// เรียกใช้ Library มาตรฐานของ MT5
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade         m_trade;       // ตัวจัดการออเดอร์
CPositionInfo  m_position;    // ตัวจัดการ Position
CSymbolInfo    m_symbol;      // ตัวจัดการคู่เงิน

// ==========================================================================
// [ส่วนที่ 1] : การตั้งค่า (USER INPUTS)
// ==========================================================================
input group  "=== Trading Modes ==="
input bool   Trade_Buy           = true;       // Enable Buy Trades
input bool   Trade_Sell          = true;       // Enable Sell Trades
input int    Magic_Number        = 9999;       // EA Magic Number
input int    Slippage            = 30;         // Max Slippage (Points)

input group  "=== Grid Settings ==="
input double Start_Lot_Size      = 0.01;       // Starting Lot Size
input double Lot_Add             = 0.00;       // Lot Adder
input int    Maximum_Grid        = 10;         // Max Orders Per Side
input int    Grid_Distance       = 1000;       // Distance (Points)

input group  "=== Risk & Targets ==="
input double Target_Money        = 10.0;       // Target Profit ($)
input double Grand_Target_Equity = 600.0;      // Equity Goal ($)
input int    DD_Percentage_Cut   = 40;         // Max Drawdown %
input int    Safety_TP           = 2000;       // Safety TP (Points)
input double Stop_Loss           = 0;          // Stop Loss (0 = Off)

input group  "=== Dashboard ==="
input int    Dashboard_X         = 170;        // X Offset
input int    Dashboard_Y         = 20;         // Y Offset
input color  Color_Text          = clrGold;    // Text Color
input bool   Auto_Color          = true;       // Auto Dark Mode

// ==========================================================================
// [ส่วนที่ 2] : ตัวแปรระบบ และ Forward Declarations (สารบัญฟังก์ชัน)
// ==========================================================================
double max_balance;
bool   System_Enabled = true;

// *** ประกาศชื่อฟังก์ชันไว้ก่อน (Forward Declaration) เพื่อแก้ Error undeclared identifier ***
void SetupChart();
void CreateGUI();
void UpdateDashboard();
void UpdateButtonState();
void CreateLabel(string name, string text, int x, int y, color c, int size);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg);
void PrintDailyNews(); // <--- เพิ่มตรงนี้แล้ว
void CheckProfitAndTargets();
void CloseAllTrades();
void CloseSpecificSide(ENUM_POSITION_TYPE type);
double FindLastOpenPrice(ENUM_POSITION_TYPE type);
int CountPositions(ENUM_POSITION_TYPE type);
bool CheckMoney(double lot, ENUM_ORDER_TYPE type);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Onpu V1.2 (MT5 Converted) Loaded.");
   
   // ตั้งค่า CTrade
   m_trade.SetExpertMagicNumber(Magic_Number);
   m_trade.SetDeviationInPoints(Slippage);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC); 
   
   // ดึงข้อมูลบัญชีเริ่มต้น
   max_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(Auto_Color) SetupChart();
   CreateGUI();
   
   // สั่งให้ Print ข่าว USD ของวันนี้ทันทีเมื่อเริ่มทำงาน
   PrintDailyNews();
   
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
//| Event Handler                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      // ปุ่ม Start/Stop
      if(sparam == "Onpu_Btn_Switch")
        {
         System_Enabled = !System_Enabled;
         UpdateButtonState();
         PlaySound("tick.wav");
         ChartRedraw();
        }
      // ปุ่ม Close All
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // อัปเดตราคาล่าสุดเสมอใน MT5
   if(!m_symbol.Name(Symbol())) return;
   m_symbol.RefreshRates();

   UpdateDashboard(); 

   if(!System_Enabled) return;

   // 1. เช็คเป้าหมายกำไร
   CheckProfitAndTargets();

   // 2. คำนวณ Drawdown
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity > max_balance) max_balance = equity;
   
   double drawdown_percent = 0;
   if(balance > 0) drawdown_percent = ((balance - equity) / balance) * 100.0;

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

   // 4. ระบบเทรด BUY
   if(Trade_Buy)
     {
      int buy_count = CountPositions(POSITION_TYPE_BUY);
      double last_buy_price = FindLastOpenPrice(POSITION_TYPE_BUY);
      double next_buy_lot = Start_Lot_Size + (buy_count * Lot_Add); 
      
      double price_tp = m_symbol.Ask() + Safety_TP * Point();
      double price_sl = (Stop_Loss == 0) ? 0 : m_symbol.Ask() - Stop_Loss * Point();
      
      string comment = "Onpu_" + IntegerToString(Magic_Number) + "_B" + IntegerToString(buy_count+1);

      if(buy_count == 0)
        {
         if(CheckMoney(next_buy_lot, ORDER_TYPE_BUY)) 
            m_trade.Buy(next_buy_lot, Symbol(), m_symbol.Ask(), price_sl, price_tp, comment);
        }
      else if(buy_count < Maximum_Grid && m_symbol.Ask() <= (last_buy_price - (Grid_Distance * Point())))
        {
         if(CheckMoney(next_buy_lot, ORDER_TYPE_BUY))
            m_trade.Buy(next_buy_lot, Symbol(), m_symbol.Ask(), price_sl, price_tp, comment);
        }
     }

   // 5. ระบบเทรด SELL
   if(Trade_Sell)
     {
      int sell_count = CountPositions(POSITION_TYPE_SELL);
      double last_sell_price = FindLastOpenPrice(POSITION_TYPE_SELL);
      double next_sell_lot = Start_Lot_Size + (sell_count * Lot_Add);

      double price_tp = m_symbol.Bid() - Safety_TP * Point();
      double price_sl = (Stop_Loss == 0) ? 0 : m_symbol.Bid() + Stop_Loss * Point();

      string comment = "Onpu_" + IntegerToString(Magic_Number) + "_S" + IntegerToString(sell_count+1);

      if(sell_count == 0)
        {
         if(CheckMoney(next_sell_lot, ORDER_TYPE_SELL)) 
            m_trade.Sell(next_sell_lot, Symbol(), m_symbol.Bid(), price_sl, price_tp, comment);
        }
      else if(sell_count < Maximum_Grid && m_symbol.Bid() >= (last_sell_price + (Grid_Distance * Point())))
        {
         if(CheckMoney(next_sell_lot, ORDER_TYPE_SELL))
            m_trade.Sell(next_sell_lot, Symbol(), m_symbol.Bid(), price_sl, price_tp, comment);
        }
     }
  }

// ==========================================================================
// [ส่วนที่ 3] : HELPER FUNCTIONS (MT5 Specific)
// ==========================================================================

bool CheckMoney(double lot, ENUM_ORDER_TYPE type) {
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double req_margin = 0;
   if(!OrderCalcMargin(type, Symbol(), lot, m_symbol.Ask(), req_margin)) {
      Print("Error Calculating Margin");
      return false;
   }
   if(free_margin < req_margin) {
      Print("Not enough money for Lot ", lot);
      return false;
   }
   return true;
}

int CountPositions(ENUM_POSITION_TYPE type) {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == Magic_Number && m_position.PositionType() == type) count++;
      }
   }
   return count;
}

double FindLastOpenPrice(ENUM_POSITION_TYPE type) {
   double last_price = 0;
   ulong last_ticket = 0; // ulong เพื่อแก้ warning loss of data
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == Magic_Number && m_position.PositionType() == type) {
            if(m_position.Ticket() > last_ticket) {
               last_ticket = m_position.Ticket();
               last_price = m_position.PriceOpen();
            }
         }
      }
   }
   return last_price;
}

void CloseSpecificSide(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == Magic_Number && m_position.PositionType() == type) {
            m_trade.PositionClose(m_position.Ticket());
         }
      }
   }
}

void CloseAllTrades() {
   Print("--- CLOSING ALL POSITIONS ---");
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == Magic_Number) {
            m_trade.PositionClose(m_position.Ticket());
         }
      }
   }
}

void CheckProfitAndTargets() {
   double sum_buy_profit = 0;
   double sum_sell_profit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Symbol() == Symbol() && m_position.Magic() == Magic_Number) {
            double profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            if(m_position.PositionType() == POSITION_TYPE_BUY) sum_buy_profit += profit;
            if(m_position.PositionType() == POSITION_TYPE_SELL) sum_sell_profit += profit;
         }
      }
   }
   
   if(sum_buy_profit >= Target_Money) {
      CloseSpecificSide(POSITION_TYPE_BUY);
      Print("Closed Buy Side. Profit: ", sum_buy_profit);
   }
   if(sum_sell_profit >= Target_Money) {
      CloseSpecificSide(POSITION_TYPE_SELL);
      Print("Closed Sell Side. Profit: ", sum_sell_profit);
   }
   
   if(AccountInfoDouble(ACCOUNT_EQUITY) >= Grand_Target_Equity) {
      CloseAllTrades();
      System_Enabled = false;
      UpdateButtonState();
      Alert("🏆 Grand Target Reached!");
   }
}

// ==========================================================================
// [ส่วนที่ 4] : หน้าจอแสดงผล (GUI) - Vertical Layout Fixed
// ==========================================================================

void SetupChart() {
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
}

void CreateGUI() {
   
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_XDISTANCE, Dashboard_X);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_YDISTANCE, Dashboard_Y);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_YSIZE, 280); 
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, "Onpu_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   CreateLabel("Onpu_Lbl_Title", ":: ONPU V1.2 (MT5) ::", 20, 15, clrGold, 12);
   CreateLabel("Onpu_Lbl_Magic", "Magic No : " + IntegerToString(Magic_Number), 20, 40, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Status", "Status: RUNNING", 20, 60, clrLime, 10);
   CreateLabel("Onpu_Lbl_Bal", "Balance: 0.00", 20, 80, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Eq", "Equity: 0.00", 20, 100, clrWhite, 9);
   CreateLabel("Onpu_Lbl_DD", "DD: 0.00%", 20, 120, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Profit", "Profit: 0.00", 20, 140, clrYellow, 9);
   CreateLabel("Onpu_Lbl_Orders", "B: 0 | S: 0", 20, 160, clrWhite, 9);
   CreateLabel("Onpu_Lbl_Goal", "GOAL: " + DoubleToString(Grand_Target_Equity, 2), 20, 180, clrAqua, 9);

   CreateButton("Onpu_Btn_Switch", "STOP EA", 20, 205, 190, 30, clrRed);
   CreateButton("Onpu_Btn_CloseAll", "CLOSE ALL", 20, 240, 190, 30, clrOrangeRed);
   
   ChartRedraw();
}

void UpdateDashboard() {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = 0;
   if(bal > 0) dd = ((bal - eq) / bal) * 100.0;

   ObjectSetString(0, "Onpu_Lbl_Bal", OBJPROP_TEXT, "Balance: " + DoubleToString(bal, 2));
   ObjectSetString(0, "Onpu_Lbl_Eq", OBJPROP_TEXT, "Equity: " + DoubleToString(eq, 2));
   
   string dd_text = "DD: " + DoubleToString(dd, 2) + "%";
   ObjectSetString(0, "Onpu_Lbl_DD", OBJPROP_TEXT, dd_text);
   ObjectSetInteger(0, "Onpu_Lbl_DD", OBJPROP_COLOR, (dd>20)?clrRed:clrWhite);

   int b_cnt = CountPositions(POSITION_TYPE_BUY);
   int s_cnt = CountPositions(POSITION_TYPE_SELL);
   ObjectSetString(0, "Onpu_Lbl_Orders", OBJPROP_TEXT, "Buy: " + IntegerToString(b_cnt) + " | Sell: " + IntegerToString(s_cnt));
   
   double sum_profit = 0;
   for(int i=0; i<PositionsTotal(); i++) {
      if(m_position.SelectByIndex(i)) {
         if(m_position.Magic() == Magic_Number && m_position.Symbol() == Symbol())
            sum_profit += m_position.Profit() + m_position.Swap() + m_position.Commission();
      }
   }
   string profit_text = "Profit: " + DoubleToString(sum_profit, 2);
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
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, Dashboard_X + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, Dashboard_Y + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}

// ==========================================================================
// [ส่วนที่ 5] : NEWS SCANNER FUNCTION (RED ONLY & SORTED)
// ==========================================================================
void PrintDailyNews()
{
   MqlCalendarValue values[];
   MqlCalendarEvent event;
   MqlCalendarCountry country;
   
   // กำหนดช่วงเวลา "ทั้งวันของวันนี้" (00:00 - 23:59)
   datetime time_start = iTime(Symbol(), PERIOD_D1, 0); 
   datetime time_end   = time_start + 86400; 
   
   Print("======= 🔴 TODAY'S HIGH IMPACT USD NEWS (" + TimeToString(time_start, TIME_DATE) + ") =======");
   
   // ดึงค่าข่าว (ฟังก์ชันนี้คืนค่าเรียงตามเวลามาให้อยู่แล้วครับ)
   if(CalendarValueHistory(values, time_start, time_end))
     {
      int count = 0;
      for(int i=0; i<ArraySize(values); i++)
        {
         if(CalendarEventById(values[i].event_id, event))
           {
            // 1. เช็คสกุลเงิน USD
            if(CalendarCountryById(event.country_id, country))
              {
               if(country.currency != "USD") continue;
              }
            else continue;
            
            // 2. *** กรองเฉพาะข่าวแดง (High Impact Only) ***
            if(event.importance != CALENDAR_IMPORTANCE_HIGH) continue; 
            
            // 3. แสดงผล: เวลาข่าว : ชื่อข่าว
            string news_time = TimeToString(values[i].time, TIME_MINUTES); // ดึงเวลาจาก values[i] จะตรงกับเวลาข่าวจริง
            
            Print("⏰ " + news_time + "  |  🔴 " + event.event_code);
            count++;
           }
        }
        
        if(count == 0) Print("✅ No Red News Today. (Safe to Trade)");
     }
   else
     {
      Print("Error accessing Calendar data! (Check Options > Allowed WebRequest)");
     }
   Print("============================================================");
}