#include <sys/time.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>

#include <algorithm>

#include "OSTools.hpp"
#include "CombatEngineUtils.hpp"

using namespace godot;
using namespace std;

OSTools::OSTools() {}
OSTools::~OSTools() {}
void OSTools::_register_methods() {
  register_method("make_process_high_priority", &OSTools::make_process_high_priority);
}

void OSTools::_init() {}
int OSTools::make_process_high_priority() {
  for(int i=0;i<10;i++) {
    errno=0;
    nice(-1);
    if(errno!=0) {
      Godot::print("Only succeeded in "+str(i)+" improvements in process priority");
      return errno;
    }
  }
  return 0;
}
