#ifndef COUNTDOWNS_HPP
#define COUNTDOWNS_HPP

#include "Constants.hpp"

namespace godot {
  namespace CE {
    class AbstractCountdown {
      // Timer that counts down to zero.
      // A negative value means the timer is not running nor ringing.
      // Zero means the timer is ringing.
      ticks_t now;
    public:
      inline bool advance(ticks_t how_much) {
        if(active())
          return 0 == (now=std::max(zero_ticks,now-how_much));
        return false;
      }
      inline bool ticking() const { return now>0; }
      inline bool alarmed() const { return not now; }
      inline bool active() const { return now>=0; }
      inline void clear_alarm() { if(alarmed()) stop(); }
      inline void stop() { now=inactive_ticks; }
      inline ticks_t ticks_left() const { return now; }
    protected:
      inline ticks_t set_ticks(ticks_t what) { now=what; return now; }
      AbstractCountdown(const AbstractCountdown &o): now(o.now) {}
      AbstractCountdown(ticks_t now): now(now) {}
      AbstractCountdown(): now(inactive_ticks) {}
      AbstractCountdown & operator = (const AbstractCountdown &o) {
        now=o.now;
        return *this;
      }
      bool operator == (const AbstractCountdown &o) const {
        return now==o.now;
      }
    };

    template<ticks_t DURATION>
    class PresetCountdown: public AbstractCountdown {
      // A countdown timer whose duration is fixed.
    public:
      static const ticks_t duration = DURATION;
      PresetCountdown(): AbstractCountdown(inactive_ticks) {}
      PresetCountdown(ticks_t duration):
        AbstractCountdown(std::clamp(duration,inactive_ticks,DURATION))
      {}
      PresetCountdown(const PresetCountdown<DURATION> &o):
        AbstractCountdown(o)
      {}
      PresetCountdown<DURATION> &operator = (const PresetCountdown<DURATION> &o) {
        set_ticks(o.ticks_left());
        return *this;
      }
      bool operator == (const PresetCountdown<DURATION> &o) const {
        return o.ticks_left()==ticks_left();
      }
      inline ticks_t reset() { return set_ticks(DURATION); }
    };

    class Countdown: public AbstractCountdown {
      // A countdown timer whose duration is set in the constructor or
      // reset() method.
    public:
      Countdown(ticks_t duration=inactive_ticks): AbstractCountdown(duration) {}
      Countdown(const Countdown &o): AbstractCountdown(o) {}
      Countdown &operator = (const Countdown &o) {
        set_ticks(o.ticks_left());
        return *this;
      }
      bool operator == (const Countdown &o) const {
        return o.ticks_left()==ticks_left();
      }
      inline ticks_t reset(ticks_t duration) { return set_ticks(duration); }
    };
  }
}

#endif
