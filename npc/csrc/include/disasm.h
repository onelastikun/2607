#pragma once

#include <cstdint>
#include <string>

namespace npc {

// Formats one instruction from the RV32E integer subset used by MiniRV.
std::string disassemble(std::uint32_t pc, std::uint32_t instruction);

}  // namespace npc
