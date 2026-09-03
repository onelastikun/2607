#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "memory.h"
#include "simulator.h"

namespace npc {

// NEMU DiffTest 客户端：每当 DUT 提交一条指令，就让参考模型执行一条并比较状态。
class Difftest {
 public:
  Difftest(const std::string &path, const Memory &memory,
           std::size_t image_size);
  ~Difftest();

  // 返回 false 表示当前提交后的 PC 或通用寄存器与参考模型不一致。
  bool step(const Simulator &simulator);

 private:
  // 布局必须与 NEMU 导出的 DiffTest 寄存器结构一致。
  struct CpuState {
    std::uint32_t gpr[16];
    std::uint32_t pc;
  };

  // 用函数指针隔离动态库接口，NPC 无需在链接阶段依赖 NEMU。
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

}  // 命名空间 npc
