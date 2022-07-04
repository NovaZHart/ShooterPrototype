#ifndef SPECIALIZEDSHIPAI_HPP
#define SPECIALIZEDSHIPAI_HPP

#include "CE/BaseShipAI.hpp"

namespace godot {
  namespace CE {
    class Ship;
    struct Planet;
    class CombatEngine;

    class PatrolShipAI: public BaseShipAI {
    public:
      virtual ~PatrolShipAI();
      PatrolShipAI();
    protected:
      void run_ai(CombatEngine &ce,Ship &ship) override;
    };

    class ArrivingMerchantAI: public BaseShipAI {
    public:
      virtual ~ArrivingMerchantAI();
      ArrivingMerchantAI();
    protected:
      void run_ai(CombatEngine &ce,Ship &ship) override;
    private:
      Planet *choose_arriving_merchant_goal_target(CombatEngine &ce,Ship &ship);
      Planet *choose_arriving_merchant_action(CombatEngine &ce,Ship &ship);
    };

    class DepartingMerchantAI: public BaseShipAI {
    public:
      virtual ~DepartingMerchantAI();
      DepartingMerchantAI();
    protected:
      void run_ai(CombatEngine &ce,Ship &ship) override;
    private:
      void decide_departing_merchant_ai_action(CombatEngine &ce,Ship &ship);
    };

    class RaiderAI: public BaseShipAI {
    public:
      virtual ~RaiderAI();
      RaiderAI();
    protected:
      void run_ai(CombatEngine &ce,Ship &ship) override;
    private:
      void decide_raider_ai_action(CombatEngine &ce,Ship &ship);
    };
  }
}
#endif
