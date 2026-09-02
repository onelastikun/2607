#pragma once

#include "device.h"
#include "memory.h"
#include "types.h"

namespace npc {

// Binds the objects used by the small set of DPI-C callbacks.
void bind_runtime(Memory &memory, DeviceMap &devices, RunState &state);

}  // namespace npc
