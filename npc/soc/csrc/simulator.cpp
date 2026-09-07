#include "simulator.h"

#include <nvboard.h>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include <array>
#include <chrono>
#include <thread>

#include "VSimTop.h"

void nvboard_bind_all_pins(VSimTop *top);

namespace npc::soc {

Simulator::Simulator(const Options &options)
    : context_(std::make_unique<VerilatedContext>()),
      dut_(std::make_unique<VSimTop>(context_.get())) {
  dut_->clock = 0;
  dut_->cpuClock = 0;
  dut_->reset = 1;
  dut_->coreSel = 0;
  dut_->externalPins_mygpio_in = options.gpio_input;
  dut_->externalPins_uart0_rx = 1;

  // minirv-ysyxsoc 默认直接连接 NVBoard；自动测试使用 --headless 跳过 SDL。
  if (!options.headless) {
    nvboard_bind_all_pins(dut_.get());
    nvboard_init();
    nvboard_enabled_ = true;
  }

  if (!options.wave_path.empty()) {
    context_->traceEverOn(true);
    trace_ = std::make_unique<VerilatedVcdC>();
    dut_->trace(trace_.get(), 12);
    trace_->open(options.wave_path.c_str());
  }
  evaluate();
  previous_gpio_output_ = gpio_output();
}

Simulator::~Simulator() {
  dut_->final();
  if (trace_) trace_->close();
  if (nvboard_enabled_) nvboard_quit();
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
  bool soc_rising = false;
  if ((phase_ & 1u) != 0) {
    dut_->clock = !dut_->clock;
    soc_rising = dut_->clock != 0;
  }
  phase_ = (phase_ + 1u) & 3u;
  if (dut_->cpuClock) ++cpu_cycles_;
  evaluate();
  observe_gpio();

  // NVBoard 每个 SoC 上升沿更新一次，保持 UART 采样和外设时钟一致。
  if (nvboard_enabled_ && soc_rising) nvboard_update();
}

void Simulator::evaluate() {
  dut_->eval();
  if (trace_) trace_->dump(context_->time());
  context_->timeInc(1);
}

std::uint16_t Simulator::gpio_output() const {
  return dut_->externalPins_mygpio_out;
}

void Simulator::observe_gpio() {
  const auto current = gpio_output();
  if (current != previous_gpio_output_) {
    ++gpio_change_count_;
    previous_gpio_output_ = current;
  }
}

std::uint32_t Simulator::gpio_digits() const {
  // 与 RTL 使用同一组十六进制段码，反向解码便于自动回归检查最终显示值。
  static constexpr std::array<std::uint8_t, 16> kSegments = {
      0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07,
      0x7f, 0x6f, 0x77, 0x7c, 0x39, 0x5e, 0x79, 0x71};
  const std::array<std::uint8_t, 8> actual = {
      dut_->externalPins_mygpio_seg_0, dut_->externalPins_mygpio_seg_1,
      dut_->externalPins_mygpio_seg_2, dut_->externalPins_mygpio_seg_3,
      dut_->externalPins_mygpio_seg_4, dut_->externalPins_mygpio_seg_5,
      dut_->externalPins_mygpio_seg_6, dut_->externalPins_mygpio_seg_7};

  std::uint32_t result = 0;
  for (std::size_t position = 0; position < actual.size(); ++position) {
    std::uint32_t digit = 0xf;
    for (std::size_t candidate = 0; candidate < kSegments.size(); ++candidate) {
      if (actual[position] == kSegments[candidate]) {
        digit = static_cast<std::uint32_t>(candidate);
        break;
      }
    }
    result |= digit << (position * 4u);
  }
  return result;
}

[[noreturn]] void Simulator::wait_for_nvboard_close() {
  // 程序结束后保留最后的 LED/数码管状态，用户关闭窗口时 NVBoard 会结束进程。
  while (true) {
    nvboard_update();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}

}  // 命名空间 npc::soc
