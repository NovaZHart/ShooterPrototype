#ifndef FASTPROFILIER_HPP
#define FASTPROFILIER_HPP

#define ENABLE_PROFILING

namespace godot {
  class FastProfiling {
    const char *function;
    int line;
    char *sig;
    uint64_t ticks;
  public:
    explicit FastProfiling(const char *p_function, const int p_line, char *sig):
      function(p_function),line(p_line),sig(sig)
    {
      //      signature = sign(p_function,p_line,sig);
      ticks = tick();
    }
    ~FastProfiling() {
      uint64_t t = tick() - ticks;
      if(t>10) {
        if(sig[0]!=':')
          snprintf(sig, 1024, "::%d::%s", line, function);
        Godot::gdnative_profiling_add_data(sig, t);
      }
    }
  private:
    static uint64_t tick() {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC_RAW,&ts);
      return ((uint64_t)ts.tv_nsec / 1000L) + (uint64_t)ts.tv_sec * 1000000L;
    }
  };

#ifdef ENABLE_PROFILING
#define FAST_PROFILING_FUNCTION static char __function_profiling_sig[1024] = {'\0'} ; FastProfiling __function_profiling_prof(__func__, __LINE__, __function_profiling_sig )
#else
#define FAST_PROFILING_FUNCTION
#endif

}

#endif
