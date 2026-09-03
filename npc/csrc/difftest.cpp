// 使用 NEMU 作为参考模型的逐指令差分测试客户端。
#include "difftest.h"

#include <dlfcn.h>

#include <iomanip>
#include <iostream>
#include <stdexcept>

#include "types.h"

namespace npc {
namespace {

// NEMU 接口沿用 PA 课程约定：false 表示参考模型复制到 DUT，true 表示反向。
constexpr bool kToDut = false;
constexpr bool kToRef = true;

}  // 匿名命名空间

Difftest::Difftest(const std::string &path, const Memory &memory,
                   std::size_t image_size) {
  // 运行时加载参考模型，使普通 NPC 仿真不必链接 NEMU。
  handle_ = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
  if (handle_ == nullptr) {
    throw std::runtime_error("cannot load DiffTest reference: " +
                             std::string(dlerror()));
  }
  memcpy_ = load_symbol<MemcpyFn>("difftest_memcpy");
  regcpy_ = load_symbol<RegcpyFn>("difftest_regcpy");
  exec_ = load_symbol<ExecFn>("difftest_exec");
  init_ = load_symbol<InitFn>("difftest_init");

  // DiffTest 开始前必须让两边拥有相同镜像、PC 和寄存器初值。
  init_(0);
  memcpy_(kPmemBase, const_cast<std::uint8_t *>(memory.data()), image_size,
          kToRef);
  CpuState initial{};
  initial.pc = kPmemBase;
  regcpy_(&initial, kToRef);
  std::cout << "DiffTest reference: " << path << '\n';
}

Difftest::~Difftest() {
  if (handle_ != nullptr) dlclose(handle_);
}

bool Difftest::step(const Simulator &simulator) {
  // DUT 已提交一条指令，此处让 NEMU 也前进一条，再比较提交后的架构状态。
  exec_(1);
  CpuState reference{};
  regcpy_(&reference, kToDut);

  // PC 优先比较；寄存器只报告第一个差异，减少失败日志噪声。
  bool matched = true;
  if (reference.pc != simulator.pc()) {
    report("pc", simulator.commit_pc(), reference.pc, simulator.pc());
    matched = false;
  }
  for (unsigned i = 0; i < 16; ++i) {
    const auto dut_value = simulator.gpr(i);
    if (matched && reference.gpr[i] != dut_value) {
      const std::string name = "x" + std::to_string(i);
      report(name.c_str(), simulator.commit_pc(), reference.gpr[i], dut_value);
      matched = false;
    }
  }
  if (!matched) simulator.print_recent_commits(std::cerr);
  return matched;
}

// 每个必需符号都显式检查，避免空函数指针在稍后位置崩溃。
template <typename T>
T Difftest::load_symbol(const char *name) {
  dlerror();
  void *symbol = dlsym(handle_, name);
  if (const char *error = dlerror(); error != nullptr) {
    throw std::runtime_error("missing DiffTest symbol " + std::string(name) +
                             ": " + error);
  }
  return reinterpret_cast<T>(symbol);
}

void Difftest::report(const char *name, std::uint32_t commit_pc,
                      std::uint32_t reference, std::uint32_t dut) {
  std::cerr << "DiffTest mismatch after pc=0x" << std::hex << std::setw(8)
            << std::setfill('0') << commit_pc << ": " << name << " ref=0x"
            << std::setw(8) << reference << " dut=0x" << std::setw(8) << dut
            << std::dec << '\n';
}

}  // 命名空间 npc
