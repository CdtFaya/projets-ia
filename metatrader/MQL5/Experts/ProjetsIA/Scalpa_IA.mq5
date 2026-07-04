//+------------------------------------------------------------------+
//|                                            Scalpa_IA.mq5 |
//|                 Expert Advisor de scalping IA - source principale |
//+------------------------------------------------------------------+
#property copyright "Projet IA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input int InpFastEMA = 8;              // Période EMA rapide
input int InpSlowEMA = 21;             // Période EMA lente
input int InpATRPeriod = 14;           // Période ATR
input double InpATRMultiplier = 1.2;   // Multiplicateur ATR pour SL/TP
input double InpLotSize = 0.01;        // Taille de position
input int InpStopLossPoints = 25;      // Stop Loss en points si ATR désactivé
input int InpTakeProfitPoints = 40;    // Take Profit en points si ATR désactivé
input int InpMaxSpreadPoints = 8;      // Spread maximal autorisé
input int InpMagic = 100201;           // Magic number
input bool InpUseATRStops = true;      // Utiliser ATR pour les stops
input bool InpUseSessionFilter = true; // Filtrer les heures de trading
input int InpStartHour = 8;            // Heure de début de session
input int InpEndHour = 20;             // Heure de fin de session

CTrade trade;
int fastEmaHandle = INVALID_HANDLE;
int slowEmaHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
double fastEmaBuffer[];
double slowEmaBuffer[];
double atrBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Scalpa_IA initialisé sur ", _Symbol, " - ", EnumToString(_Period));

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(10);

   fastEmaHandle = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);

   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Erreur : initialisation des handles d'indicateurs impossible.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastEmaBuffer, true);
   ArraySetAsSeries(slowEmaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(fastEmaHandle);
   if(slowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(slowEmaHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   Print("Scalpa_IA arrêté. Raison : ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsSessionAllowed())
      return;

   if(PositionSelect(_Symbol) || PositionsTotal() > 0)
      return;

   if(!RefreshIndicators())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double spreadPoints = (tick.ask - tick.bid) / Point();
   if(spreadPoints > InpMaxSpreadPoints)
      return;

   double fastNow = fastEmaBuffer[0];
   double fastPrev = fastEmaBuffer[1];
   double slowNow = slowEmaBuffer[0];
   double slowPrev = slowEmaBuffer[1];
   double atrValue = atrBuffer[0];

   bool longSignal = (fastNow > slowNow && fastPrev <= slowPrev && tick.ask > fastNow);
   bool shortSignal = (fastNow < slowNow && fastPrev >= slowPrev && tick.bid < fastNow);

   if(!longSignal && !shortSignal)
      return;

   double sl = 0.0;
   double tp = 0.0;

   if(longSignal)
   {
      if(InpUseATRStops && atrValue > 0.0)
      {
         sl = tick.ask - InpATRMultiplier * atrValue;
         tp = tick.ask + InpATRMultiplier * atrValue * 2.0;
      }
      else
      {
         sl = tick.ask - InpStopLossPoints * Point();
         tp = tick.ask + InpTakeProfitPoints * Point();
      }

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      bool result = trade.Buy(InpLotSize, _Symbol, tick.ask, sl, tp, "Scalpa_IA");
      if(result && trade.ResultRetcode() == TRADE_RETCODE_DONE)
         Print("Achat ouvert : ", tick.ask);
      else
         Print("Erreur ordre BUY : ", trade.ResultRetcode(), " - ", trade.ResultComment());
   }
   else if(shortSignal)
   {
      if(InpUseATRStops && atrValue > 0.0)
      {
         sl = tick.bid + InpATRMultiplier * atrValue;
         tp = tick.bid - InpATRMultiplier * atrValue * 2.0;
      }
      else
      {
         sl = tick.bid + InpStopLossPoints * Point();
         tp = tick.bid - InpTakeProfitPoints * Point();
      }

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      bool result = trade.Sell(InpLotSize, _Symbol, tick.bid, sl, tp, "Scalpa_IA");
      if(result && trade.ResultRetcode() == TRADE_RETCODE_DONE)
         Print("Vente ouverte : ", tick.bid);
      else
         Print("Erreur ordre SELL : ", trade.ResultRetcode(), " - ", trade.ResultComment());
   }
}

//+------------------------------------------------------------------+
//| Rafraîchit les buffers des indicateurs                          |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(fastEmaHandle, 0, 0, 2, fastEmaBuffer) < 2)
      return(false);
   if(CopyBuffer(slowEmaHandle, 0, 0, 2, slowEmaBuffer) < 2)
      return(false);
   if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) < 2)
      return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Vérifie si la session de trading est autorisée                   |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
{
   if(!InpUseSessionFilter)
      return(true);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}
//+------------------------------------------------------------------+
