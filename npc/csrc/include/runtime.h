#pragma once

#include "device.h"
#include "memory.h"
#include "types.h"

namespace npc {

// 将 C++ 对象绑定到 DPI-C 回调。
// Verilog 只能调用 C 风格函数，因此通过这里保存仿真期内始终有效的对象地址。
void bind_runtime(Memory &memory, DeviceMap &devices, RunState &state);

}  // 命名空间 npc
