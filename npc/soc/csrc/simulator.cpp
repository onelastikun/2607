#include "simulator.h"

#include <verilated.h>
#include <verilated_vcd_c.h>

#include "VSimTop.h"

namespace npc::soc {

Simulator::Simulator(const Options &options)
    : context_(std::make_unique<VerilatedContext>()),
      dut_(std::make_unique<VSimTop>(context_.get())) {
  dut_->clock = 0;
  dut_->cpuClock = 0;
  dut_->reset = 1;
  dut_->coreSel = 0;
  dut_->externalPins_mygpio_in = options.gpio_input;
  dut_->externalPins_uart0_rx = 1;  // UART 空闲电平为高。
  if (!options.wave_path.empty()) {
    context_->traceEverOn(true);
    trace_ = std::make_unique<VerilatedVcdC>();
    dut_->trace(trace_.get(), 12);
    trace_->open(options.wave_path.c_str());
  }
  evaluate();
}

Simulator::~Simulator() {
  dut_->final();
  if (trace_) trace_->close();
}

void Simulator::reset() {
  // 至少保持 20 个 SoC 时钟周期，覆盖 SoC 和 CPU 两个时钟域的复位同步器。
  const auto target = cpu_cycles_ + 40;
  while (cpu_cycles_ < target) step();
  dut_->reset = 0;
}

void Simulator::step() {
  // CPU 每个时间量翻转，SoC 时钟每两个时间量翻转，因此 CPU 频率是 SoC 的两倍。
  dut_->cpuClock = !dut_->cpuClock;
  if ((phase_ & 1u) != 0) dut_->clock = !dut_->clock;
  phase_ = (phase_ + 1u) & 3u;
  if (dut_->cpuClock) ++cpu_cycles_;
  evaluate();
}

void Simulator::evaluate() {
  dut_->eval();
  if (trace_) trace_->dump(context_->time());
  context_->timeInc(1);
}

std::uint16_t Simulator::gpio_output() const {
  return dut_->externalPins_mygpio_out;
}

}  // 命名空间 npc::soc
