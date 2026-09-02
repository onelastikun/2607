#include "simulator.h"

#include <verilated.h>
#include <verilated_vcd_c.h>

#include <iomanip>
#include <iostream>

#include "Vtop.h"

namespace npc {

Simulator::Simulator(const Options &options)
    : context_(std::make_unique<VerilatedContext>()),
      dut_(std::make_unique<Vtop>(context_.get())) {
  if (!options.wave_path.empty()) {
    context_->traceEverOn(true);
    trace_ = std::make_unique<VerilatedVcdC>();
    dut_->trace(trace_.get(), 16);
    trace_->open(options.wave_path.c_str());
  }
}

Simulator::~Simulator() {
  dut_->final();
  if (trace_) trace_->close();
}

void Simulator::reset() {
  dut_->reset = 1;
  tick();
  tick();
  dut_->reset = 0;
}

void Simulator::tick() {
  half_cycle(0);
  half_cycle(1);
}

void Simulator::half_cycle(std::uint8_t clock) {
  dut_->clock = clock;
  dut_->eval();
  if (trace_) trace_->dump(context_->time());
  context_->timeInc(1);
}

void Simulator::print_commit() const {
  if (!dut_->commit_valid) return;
  std::cout << "0x" << std::hex << std::setw(8) << std::setfill('0')
            << dut_->commit_pc << ": 0x" << std::setw(8) << dut_->commit_inst
            << std::dec << '\n';
}

std::uint32_t Simulator::gpr(unsigned index) const {
  return index < 16 ? dut_->gpr_state[index] : 0;
}

std::uint32_t Simulator::pc() const { return dut_->pc; }
std::uint32_t Simulator::commit_pc() const { return dut_->commit_pc; }

}  // namespace npc
