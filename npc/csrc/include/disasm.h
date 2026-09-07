#pragma once

#include <cstdint>
#include <string>

namespace npc {

// 把一条 MiniRV 指令格式化为便于阅读的汇编文本。
// 未识别的编码按 .word 原样显示，避免调试信息被静默丢失。
std::string disassemble(std::uint32_t pc, std::uint32_t instruction);

}  // 命名空间 npc
