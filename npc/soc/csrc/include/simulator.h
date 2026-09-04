#pragma once

#include <cstdint>
#include <memory>

#include "types.h"

class VSimTop;
class VerilatedContext;
class VerilatedVcdC;

namespace npc::soc {

// 同时驱动 CPU 时钟和较慢的 SoC 外设时钟，比例固定为 2:1。
class Simulator {
 public:
  explicit Simulator(const Options &options);
  ~Simulator();

  void reset();
  void step();
  std::uint64_t cpu_cycles() const { return cpu_cycles_; }
  std::uint16_t gpio_output() const;

 private:
  void evaluate();

  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<VSimTop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
  unsigned phase_ = 0;
  std::uint64_t cpu_cycles_ = 0;
};

}  // 命名空间 npc::soc
