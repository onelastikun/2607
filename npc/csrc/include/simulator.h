#pragma once

#include <cstdint>
#include <deque>
#include <iosfwd>
#include <memory>

#include "types.h"

class Vtop;
class VerilatedContext;
class VerilatedVcdC;

namespace npc {

// 封装 Verilator 生成的 DUT、时钟推进、复位和波形资源。
// main.cpp 只负责运行流程，不直接操作 Vtop 的内部细节。
class Simulator {
 public:
  explicit Simulator(const Options &options);
  ~Simulator();

  void reset();  // 驱动两个完整时钟周期的同步复位
  void tick();   // 推进一个完整时钟周期（低电平半周期 + 高电平半周期）
  void print_commit() const;
  void print_recent_commits(std::ostream &out) const;

  // 以下访问器只暴露验证所需的架构状态，避免其他模块依赖 Vtop。
  std::uint32_t gpr(unsigned index) const;
  std::uint32_t pc() const;
  std::uint32_t commit_pc() const;
  std::uint64_t instruction_count() const;
  bool commit_valid() const;

 private:
  struct Commit {
    std::uint32_t pc;
    std::uint32_t instruction;
  };

  void half_cycle(std::uint8_t clock);
  void record_commit();

  // unique_ptr 明确表示这些资源由 Simulator 独占，并在析构时自动释放。
  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<Vtop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
  std::deque<Commit> recent_commits_;  // 出错时用于回看最近 16 条指令
};

}  // 命名空间 npc
