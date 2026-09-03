// 对 Verilator DUT 的生命周期、时钟、波形和提交历史进行封装。
#include "simulator.h"

#include <verilated.h>
#include <verilated_vcd_c.h>

#include <iomanip>
#include <iostream>

#include "Vtop.h"
#include "disasm.h"

namespace npc {

// VerilatedContext 保存仿真时间；Vtop 是 Verilator 生成的 RTL 顶层对象。
Simulator::Simulator(const Options &options)
    : context_(std::make_unique<VerilatedContext>()),
      dut_(std::make_unique<Vtop>(context_.get())) {
  // 只有显式指定 --wave 时才创建 VCD，避免正常回归产生巨大波形文件。
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

// 顶层采用同步复位，因此复位有效时仍需提供时钟上升沿。
void Simulator::reset() {
  dut_->reset = 1;
  tick();
  tick();
  dut_->reset = 0;
}

void Simulator::tick() {
  half_cycle(0);
  half_cycle(1);
  record_commit();
}

// 每次电平变化后先求值，再记录波形，最后推进 Verilator 时间戳。
void Simulator::half_cycle(std::uint8_t clock) {
  dut_->clock = clock;
  dut_->eval();
  if (trace_) trace_->dump(context_->time());
  context_->timeInc(1);
}

// 固定深度环形历史只保留调试所需信息，不随长程序无限增长。
void Simulator::record_commit() {
  if (!dut_->commit_valid) return;
  constexpr std::size_t kTraceDepth = 16;
  recent_commits_.push_back({dut_->commit_pc, dut_->commit_inst});
  if (recent_commits_.size() > kTraceDepth) recent_commits_.pop_front();
}

void Simulator::print_commit() const {
  if (!dut_->commit_valid) return;
  std::cout << "0x" << std::hex << std::setw(8) << std::setfill('0')
            << dut_->commit_pc << ": 0x" << std::setw(8) << dut_->commit_inst
            << std::dec << "  "
            << disassemble(dut_->commit_pc, dut_->commit_inst) << '\n';
}

void Simulator::print_recent_commits(std::ostream &out) const {
  out << "recent commits:\n";
  for (const auto &commit : recent_commits_) {
    out << "  0x" << std::hex << std::setw(8) << std::setfill('0')
        << commit.pc << ": 0x" << std::setw(8) << commit.instruction
        << std::dec << "  " << disassemble(commit.pc, commit.instruction)
        << '\n';
  }
}

std::uint32_t Simulator::gpr(unsigned index) const {
  return index < 16 ? dut_->gpr_state[index] : 0;
}

std::uint32_t Simulator::pc() const { return dut_->pc; }
std::uint32_t Simulator::commit_pc() const { return dut_->commit_pc; }
std::uint64_t Simulator::instruction_count() const {
  return dut_->instruction_count;
}
bool Simulator::commit_valid() const { return dut_->commit_valid; }

}  // 命名空间 npc
