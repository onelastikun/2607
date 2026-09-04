#pragma once

#include "flash_image.h"
#include "types.h"

namespace npc::soc {

void bind_runtime(const FlashImage &flash, RunState &state);

}  // 命名空间 npc::soc
