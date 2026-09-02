#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace npc {

constexpr std::uint32_t kPmemBase = 0x80000000u;
constexpr std::size_t kPmemSize = 128u * 1024u * 1024u;

struct Options {
  std::string image_path;
  std::string wave_path;
  std::string diff_path;
  std::uint64_t max_cycles = 100;
  bool itrace = false;
};

struct RunState {
  bool halted = false;
  bool aborted = false;
  std::uint32_t code = 0;
  std::uint32_t pc = 0;
};

}  // namespace npc
