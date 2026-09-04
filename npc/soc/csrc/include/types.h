#pragma once

#include <cstdint>
#include <string>

namespace npc::soc {

struct Options {
  std::string image_path;
  std::string wave_path;
  std::uint64_t max_cpu_cycles = 100000000;
  std::uint16_t gpio_input = 0;
};

struct RunState {
  bool halted = false;
  bool aborted = false;
  std::uint32_t code = 0;
  std::uint32_t pc = 0;
  std::uint32_t last_pc = 0;
  std::uint32_t last_instruction = 0;
  std::uint64_t instruction_count = 0;
  std::string uart_output;
};

}  // 命名空间 npc::soc
