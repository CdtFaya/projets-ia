//+------------------------------------------------------------------+
//|                                              EA_Basic.mq5 |
//|                             Projet IA - Expert Advisor base |
//+------------------------------------------------------------------+
#property copyright "Projet IA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input int InpFastMA = 9;              // Période moyenne mobile rapide
input int InpSlowMA = 21;             // Période moyenne mobile lente
input double InpLotSize = 0.01;       // Taille de position
input int InpStopLossPoints = 100;    // Stop Loss en points
input int InpTakeProfitPoints = 200;  // Take Profit en points

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA initialisé sur ", _Symbol, " - ", EnumToString(_Period));
   trade.SetExpertMagicNumber(100001);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA arrêté. Raison : ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   double fastMA = iMA(_Symbol, _Period, InpFastMA, 0, MODE_SMA, PRICE_CLOSE, 1);
   double slowMA = iMA(_Symbol, _Period, InpSlowMA, 0, MODE_SMA, PRICE_CLOSE, 1);
   double prevFastMA = iMA(_Symbol, _Period, InpFastMA, 0, MODE_SMA, PRICE_CLOSE, 2);
   double prevSlowMA = iMA(_Symbol, _Period, InpSlowMA, 0, MODE_SMA, PRICE_CLOSE, 2);

   if(!isNewBar())
      return;

   if(prevFastMA <= prevSlowMA && fastMA > slowMA)
   {
      if(PositionSelect(_Symbol))
         return;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - InpStopLossPoints * Point();
      double tp = ask + InpTakeProfitPoints * Point();

      trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "EA_Basic");
   }
   else if(prevFastMA >= prevSlowMA && fastMA < slowMA)
   {
      if(PositionSelect(_Symbol))
         return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + InpStopLossPoints * Point();
      double tp = bid - InpTakeProfitPoints * Point();

      trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "EA_Basic");
   }
}

//+------------------------------------------------------------------+
//| Vérifie si une nouvelle barre est apparue                         |
//+------------------------------------------------------------------+
bool isNewBar()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, _Period, 0);

   if(lastTime == currentTime)
      return false;

   lastTime = currentTime;
   return true;
}
//+------------------------------------------------------------------+
