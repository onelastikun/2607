#pragma once

#include "types.h"

namespace npc {

// 解析 NPC 命令行参数；参数缺失或格式错误时打印用法并结束进程。
Options parse_options(int argc, char **argv);

}  // 命名空间 npc
