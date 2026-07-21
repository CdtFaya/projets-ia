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
input bool InpEnableTrailing = true;   // Activer trailing stop
input double InpTrailingATRMultiplier = 0.5; // Déclencheur trailing (x ATR)
input int InpBreakEvenBufferPoints = 2; // Buffer en points pour breakeven
input int InpTrailingStepPoints = 5;   // Pas minimal (points) avant déplacement SL
input double InpRiskPercent = 0.5;     // % du solde risqué par trade (0 = désactivé)
input double InpMinLot = 0.01;         // Lot min voulu
input double InpMaxLot = 1.0;          // Lot max voulu
input bool InpDebugLog = true;         // Logguer une raison de blocage à chaque nouvelle bougie

CTrade trade;
datetime lastDebugBarTime = 0;
int fastEmaHandle = INVALID_HANDLE;
int slowEmaHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int fastEmaHandleM5 = INVALID_HANDLE;
int slowEmaHandleM5 = INVALID_HANDLE;
int fastEmaHandleM15 = INVALID_HANDLE;
int slowEmaHandleM15 = INVALID_HANDLE;
double fastEmaBuffer[];
double slowEmaBuffer[];
double atrBuffer[];
double fastEmaBufferM5[];
double slowEmaBufferM5[];
double fastEmaBufferM15[];
double slowEmaBufferM15[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Scalpa_IA initialisé sur ", _Symbol, " - ", EnumToString(_Period));
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("Spread courant : ", currentSpread, " points  |  InpMaxSpreadPoints = ", InpMaxSpreadPoints,
         (currentSpread > InpMaxSpreadPoints ? "  /!\\ Spread courant DEJA supérieur au max autorisé - aucune entrée ne sera prise tant que ce n'est pas corrigé." : ""));

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetDeviationInPoints(10);

   fastEmaHandle = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   // multi-TF EMA handles
   fastEmaHandleM5 = iMA(_Symbol, PERIOD_M5, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandleM5 = iMA(_Symbol, PERIOD_M5, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   fastEmaHandleM15 = iMA(_Symbol, PERIOD_M15, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandleM15 = iMA(_Symbol, PERIOD_M15, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Erreur : initialisation des handles d'indicateurs impossible.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastEmaBuffer, true);
   ArraySetAsSeries(slowEmaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(fastEmaBufferM5, true);
   ArraySetAsSeries(slowEmaBufferM5, true);
   ArraySetAsSeries(fastEmaBufferM15, true);
   ArraySetAsSeries(slowEmaBufferM15, true);

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
   if(fastEmaHandleM5 != INVALID_HANDLE) IndicatorRelease(fastEmaHandleM5);
   if(slowEmaHandleM5 != INVALID_HANDLE) IndicatorRelease(slowEmaHandleM5);
   if(fastEmaHandleM15 != INVALID_HANDLE) IndicatorRelease(fastEmaHandleM15);
   if(slowEmaHandleM15 != INVALID_HANDLE) IndicatorRelease(slowEmaHandleM15);

   Print("Scalpa_IA arrêté. Raison : ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   bool isNewBar = (iTime(_Symbol, _Period, 0) != lastDebugBarTime);
   if(isNewBar)
      lastDebugBarTime = iTime(_Symbol, _Period, 0);

   if(!IsSessionAllowed())
   {
      if(InpDebugLog && isNewBar)
         Print("Bloqué : hors session (heure serveur=", TimeToString(TimeCurrent(), TIME_MINUTES), ")");
      return;
   }

   if(!RefreshIndicators())
   {
      if(InpDebugLog && isNewBar)
         Print("Bloqué : indicateurs du timeframe principal pas encore prêts (historique insuffisant).");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double spreadPoints = (tick.ask - tick.bid) / Point();
   if(spreadPoints > InpMaxSpreadPoints)
   {
      if(InpDebugLog && isNewBar)
         Print("Bloqué : spread=", DoubleToString(spreadPoints,1), " pts > max autorisé=", InpMaxSpreadPoints, " pts");
      return;
   }

   double fastNow = fastEmaBuffer[0];
   double fastPrev = fastEmaBuffer[1];
   double slowNow = slowEmaBuffer[0];
   double slowPrev = slowEmaBuffer[1];
   double atrValue = atrBuffer[0];

   // Display panel and manage trailing for existing positions
   DisplayInfoPanel(spreadPoints, atrValue);
   ManageTrailingStops();

   // avoid new entries if there's already a position
   if(PositionSelect(_Symbol) || PositionsTotal() > 0)
      return;

   bool longSignal = (fastNow > slowNow && fastPrev <= slowPrev && tick.ask > fastNow);
   bool shortSignal = (fastNow < slowNow && fastPrev >= slowPrev && tick.bid < fastNow);

   if(InpDebugLog && isNewBar)
      Print("Check : fastEMA=", DoubleToString(fastNow,_Digits), " (prev=", DoubleToString(fastPrev,_Digits),
            ") slowEMA=", DoubleToString(slowNow,_Digits), " (prev=", DoubleToString(slowPrev,_Digits),
            ") -> long=", longSignal, " short=", shortSignal);

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

      double lotToUse = (InpRiskPercent > 0.0) ? CalculateLotFromRisk(tick.ask, sl) : InpLotSize;
      bool result = trade.Buy(lotToUse, _Symbol, tick.ask, sl, tp, "Scalpa_IA");
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

      double lotToUse = (InpRiskPercent > 0.0) ? CalculateLotFromRisk(tick.bid, sl) : InpLotSize;
      bool result = trade.Sell(lotToUse, _Symbol, tick.bid, sl, tp, "Scalpa_IA");
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
   // multi-TF buffers : usage purement informatif (panneau) -> un échec ici ne doit
   // jamais bloquer les entrées sur le timeframe principal.
   if(fastEmaHandleM5 != INVALID_HANDLE)
      CopyBuffer(fastEmaHandleM5, 0, 0, 2, fastEmaBufferM5);
   if(slowEmaHandleM5 != INVALID_HANDLE)
      CopyBuffer(slowEmaHandleM5, 0, 0, 2, slowEmaBufferM5);
   if(fastEmaHandleM15 != INVALID_HANDLE)
      CopyBuffer(fastEmaHandleM15, 0, 0, 2, fastEmaBufferM15);
   if(slowEmaHandleM15 != INVALID_HANDLE)
      CopyBuffer(slowEmaHandleM15, 0, 0, 2, slowEmaBufferM15);

   return(true);
}

//+------------------------------------------------------------------+
//| Gère le trailing stop pour les positions ouvertes                |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   if(!InpEnableTrailing)
      return;

   if(PositionsTotal() == 0)
      return;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym != _Symbol)
         continue;

      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagic)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double atr = atrBuffer[0];

      double triggerPoints = (InpTrailingATRMultiplier * atr) / Point();

      double newSL = sl;

      if(type == POSITION_TYPE_BUY)
      {
         double profitPoints = (currentBid - openPrice) / Point();
         // move to breakeven
         if(profitPoints >= triggerPoints)
         {
            double be = openPrice + InpBreakEvenBufferPoints * Point();
            if(be > sl)
               newSL = NormalizeDouble(be, _Digits);
         }
         // trailing step
         double desiredSL = currentBid - InpTrailingStepPoints * Point();
         if(desiredSL > newSL + InpTrailingStepPoints * Point())
            newSL = NormalizeDouble(desiredSL, _Digits);
      }
      else // SELL
      {
         double profitPoints = (openPrice - currentBid) / Point();
         if(profitPoints >= triggerPoints)
         {
            double be = openPrice - InpBreakEvenBufferPoints * Point();
            if(be < sl || sl == 0.0)
               newSL = NormalizeDouble(be, _Digits);
         }
         double desiredSL = currentBid + InpTrailingStepPoints * Point();
         if(desiredSL < newSL - InpTrailingStepPoints * Point() || newSL==0.0)
            newSL = NormalizeDouble(desiredSL, _Digits);
      }

      if(newSL != sl)
      {
         bool modified = trade.PositionModify(_Symbol, newSL, tp);
         if(modified)
            Print("SL modifié (ticket): ", ticket, " -> ", DoubleToString(newSL,_Digits));
         else
            Print("Échec modification SL: ", trade.ResultRetcode(), " ", trade.ResultComment());
      }
   }
}

//+------------------------------------------------------------------+
//| Calcule la taille de lot selon le risque (%) et la distance SL   |
//+------------------------------------------------------------------+
double CalculateLotFromRisk(double entryPrice, double stopPrice)
{
   if(InpRiskPercent <= 0.0)
      return(InpLotSize);

   double stopDistance = MathAbs(entryPrice - stopPrice);
   if(stopDistance <= 0.0)
      return(InpLotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return(InpLotSize);

   double ticks = stopDistance / tickSize;
   double lossPerLot = ticks * tickValue;
   if(lossPerLot <= 0.0)
      return(InpLotSize);

   double rawLot = riskMoney / lossPerLot;

   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(volStep <= 0.0) volStep = 0.01;

   // clamp
   rawLot = MathMax(rawLot, MathMax(volMin, InpMinLot));
   rawLot = MathMin(rawLot, MathMin(volMax, InpMaxLot));

   // normalize to step
   int steps = (int)MathFloor(rawLot / volStep + 0.0000001);
   double lot = steps * volStep;
   if(lot < volMin) lot = volMin;

   return(NormalizeDouble(lot, 2));
}

//+------------------------------------------------------------------+
//| Affiche un panneau d'information basique multi-TF                |
//+------------------------------------------------------------------+
void DisplayInfoPanel(double spreadPoints, double atrValue)
{
   string line1 = "Spread:" + DoubleToString(spreadPoints,1) + " pts  ATR:" + DoubleToString(atrValue, _Digits);
   string m5trend = "M5:?";
   string m15trend = "M15:?";
   if(ArraySize(fastEmaBufferM5) >= 2 && ArraySize(slowEmaBufferM5) >= 2)
   {
      double f5 = fastEmaBufferM5[0], s5 = slowEmaBufferM5[0];
      m5trend = (f5 > s5) ? "M5:UP" : "M5:DN";
   }
   if(ArraySize(fastEmaBufferM15) >= 2 && ArraySize(slowEmaBufferM15) >= 2)
   {
      double f15 = fastEmaBufferM15[0], s15 = slowEmaBufferM15[0];
      m15trend = (f15 > s15) ? "M15:UP" : "M15:DN";
   }

   string comment = line1 + "  " + m5trend + "  " + m15trend;
   Comment(comment);
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
