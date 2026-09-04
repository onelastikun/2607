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
  std::uint32_t gpio_digits() const;
  std::uint64_t gpio_change_count() const { return gpio_change_count_; }

 private:
  void evaluate();
  void observe_gpio();

  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<VSimTop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
  unsigned phase_ = 0;
  std::uint64_t cpu_cycles_ = 0;
  std::uint16_t previous_gpio_output_ = 0;
  std::uint64_t gpio_change_count_ = 0;
};

}  // 命名空间 npc::soc
