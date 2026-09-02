#pragma once

#include <cstdint>
#include <memory>

#include "types.h"

class Vtop;
class VerilatedContext;
class VerilatedVcdC;

namespace npc {

class Simulator {
 public:
  explicit Simulator(const Options &options);
  ~Simulator();

  void reset();
  void tick();
  void print_commit() const;
  std::uint32_t gpr(unsigned index) const;
  std::uint32_t pc() const;
  std::uint32_t commit_pc() const;
  bool commit_valid() const;

 private:
  void half_cycle(std::uint8_t clock);

  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<Vtop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
};

}  // namespace npc
