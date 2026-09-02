#pragma once

#include "memory.h"
#include "types.h"

namespace npc {

// Binds the C++ objects used by the small set of DPI-C callbacks.
void bind_runtime(Memory &memory, RunState &state);

}  // namespace npc
