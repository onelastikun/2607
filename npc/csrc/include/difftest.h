#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "memory.h"
#include "simulator.h"

namespace npc {

class Difftest {
 public:
  Difftest(const std::string &path, const Memory &memory,
           std::size_t image_size);
  ~Difftest();

  bool step(const Simulator &simulator);

 private:
  struct CpuState {
    std::uint32_t gpr[16];
    std::uint32_t pc;
  };
  using MemcpyFn = void (*)(std::uint32_t, void *, std::size_t, bool);
  using RegcpyFn = void (*)(void *, bool);
  using ExecFn = void (*)(std::uint64_t);
  using InitFn = void (*)(int);

  template <typename T>
  T load_symbol(const char *name);
  static void report(const char *name, std::uint32_t commit_pc,
                     std::uint32_t reference, std::uint32_t dut);

  void *handle_ = nullptr;
  MemcpyFn memcpy_ = nullptr;
  RegcpyFn regcpy_ = nullptr;
  ExecFn exec_ = nullptr;
  InitFn init_ = nullptr;
};

}  // namespace npc
