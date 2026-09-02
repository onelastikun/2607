#include "difftest.h"

#include <dlfcn.h>

#include <iomanip>
#include <iostream>
#include <stdexcept>

#include "types.h"

namespace npc {
namespace {

constexpr bool kToDut = false;
constexpr bool kToRef = true;

}  // namespace

Difftest::Difftest(const std::string &path, const Memory &memory,
                   std::size_t image_size) {
  handle_ = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
  if (handle_ == nullptr) {
    throw std::runtime_error("cannot load DiffTest reference: " +
                             std::string(dlerror()));
  }
  memcpy_ = load_symbol<MemcpyFn>("difftest_memcpy");
  regcpy_ = load_symbol<RegcpyFn>("difftest_regcpy");
  exec_ = load_symbol<ExecFn>("difftest_exec");
  init_ = load_symbol<InitFn>("difftest_init");

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
  exec_(1);
  CpuState reference{};
  regcpy_(&reference, kToDut);

  bool matched = true;
  if (reference.pc != simulator.pc()) {
    report("pc", simulator.commit_pc(), reference.pc, simulator.pc());
    matched = false;
  }
  for (unsigned i = 0; i < 16; ++i) {
    const auto dut_value = simulator.gpr(i);
    if (reference.gpr[i] != dut_value) {
      const std::string name = "x" + std::to_string(i);
      report(name.c_str(), simulator.commit_pc(), reference.gpr[i], dut_value);
      matched = false;
    }
  }
  return matched;
}

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

}  // namespace npc
