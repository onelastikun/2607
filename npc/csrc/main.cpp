#include <verilated.h>
#include <verilated_vcd_c.h>

#include <dlfcn.h>

#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "Vtop.h"

namespace {

constexpr std::uint32_t kPmemBase = 0x80000000u;
constexpr std::size_t kPmemSize = 128u * 1024u * 1024u;

struct Options {
  std::string image_path;
  std::string wave_path;
  std::string diff_path;
  std::uint64_t max_cycles = 100;
  bool itrace = false;
};

struct RunState {
  bool halted = false;
  bool aborted = false;
  std::uint32_t code = 0;
  std::uint32_t pc = 0;
};

class Memory {
 public:
  Memory() : bytes_(kPmemSize, 0) {}

  std::size_t load_image(const std::string &path) {
    if (path.empty()) {
      const std::array<std::uint32_t, 4> program = {
          0x00100093u,  // addi x1, x0, 1
          0x00208113u,  // addi x2, x1, 2
          0x00000513u,  // addi a0, x0, 0
          0x00100073u,  // ebreak
      };
      for (std::size_t i = 0; i < program.size(); ++i) {
        store_word(kPmemBase + static_cast<std::uint32_t>(i * 4), program[i]);
      }
      return program.size() * sizeof(program[0]);
    }

    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) {
      throw std::runtime_error("cannot open image: " + path);
    }
    const auto end = input.tellg();
    if (end < 0 || static_cast<std::uint64_t>(end) > bytes_.size()) {
      throw std::runtime_error("invalid or oversized image: " + path);
    }
    const auto size = static_cast<std::size_t>(end);
    input.seekg(0, std::ios::beg);
    if (size != 0 && !input.read(reinterpret_cast<char *>(bytes_.data()), size)) {
      throw std::runtime_error("failed to read image: " + path);
    }
    return size;
  }

  std::uint32_t read(std::uint32_t address, std::uint8_t length) const {
    if (length == 0 || length > 4 || !contains(address, length)) {
      report_bad_access("read", address, length);
      return 0;
    }
    const auto offset = static_cast<std::size_t>(address - kPmemBase);
    std::uint32_t value = 0;
    for (std::uint8_t i = 0; i < length; ++i) {
      value |= static_cast<std::uint32_t>(bytes_[offset + i]) << (i * 8);
    }
    return value;
  }

  const std::uint8_t *data() const { return bytes_.data(); }

  void write(std::uint32_t address, std::uint32_t value, std::uint8_t mask) {
    for (std::uint8_t i = 0; i < 4; ++i) {
      if ((mask & (1u << i)) == 0) continue;
      const auto byte_address = address + i;
      if (!contains(byte_address, 1)) {
        report_bad_access("write", byte_address, 1);
        return;
      }
      const auto offset = static_cast<std::size_t>(byte_address - kPmemBase);
      bytes_[offset] = static_cast<std::uint8_t>(value >> (i * 8));
    }
  }

 private:
  bool contains(std::uint32_t address, std::uint8_t length) const {
    if (address < kPmemBase) {
      return false;
    }
    const auto offset = static_cast<std::uint64_t>(address) - kPmemBase;
    return offset + length <= bytes_.size();
  }

  void store_word(std::uint32_t address, std::uint32_t value) {
    const auto offset = static_cast<std::size_t>(address - kPmemBase);
    for (std::uint8_t i = 0; i < 4; ++i) {
      bytes_[offset + i] = static_cast<std::uint8_t>(value >> (i * 8));
    }
  }

  static void report_bad_access(const char *operation, std::uint32_t address,
                                std::uint8_t length);

  std::vector<std::uint8_t> bytes_;
};

Memory *g_memory = nullptr;
RunState g_run_state;
bool g_memory_checks_enabled = false;

void Memory::report_bad_access(const char *operation, std::uint32_t address,
                               std::uint8_t length) {
  if (!g_memory_checks_enabled) return;
  std::cerr << "memory " << operation << " out of range: addr=0x" << std::hex
            << std::setw(8) << std::setfill('0') << address << std::dec
            << " len=" << static_cast<unsigned>(length) << '\n';
  g_run_state.aborted = true;
}

[[noreturn]] void usage(const char *program, const char *message = nullptr) {
  if (message != nullptr) {
    std::cerr << "error: " << message << '\n';
  }
  std::cerr << "usage: " << program
            << " [--image FILE] [--max-cycles N] [--wave FILE] [--itrace]"
               " [--diff REF_SO]\n";
  std::exit(EXIT_FAILURE);
}

std::uint64_t parse_u64(const char *text, const char *program) {
  char *end = nullptr;
  const auto value = std::strtoull(text, &end, 0);
  if (text[0] == '\0' || end == nullptr || *end != '\0') {
    usage(program, "expected an integer argument");
  }
  return value;
}

Options parse_options(int argc, char **argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--image") {
      if (++i >= argc) usage(argv[0], "missing value after --image");
      options.image_path = argv[i];
    } else if (arg == "--max-cycles") {
      if (++i >= argc) usage(argv[0], "missing value after --max-cycles");
      options.max_cycles = parse_u64(argv[i], argv[0]);
    } else if (arg == "--wave") {
      if (++i >= argc) usage(argv[0], "missing value after --wave");
      options.wave_path = argv[i];
    } else if (arg == "--itrace") {
      options.itrace = true;
    } else if (arg == "--diff") {
      if (++i >= argc) usage(argv[0], "missing value after --diff");
      options.diff_path = argv[i];
    } else if (arg == "--help" || arg == "-h") {
      usage(argv[0]);
    }
  }
  return options;
}

class Simulator {
 public:
  explicit Simulator(const Options &options)
      : context_(std::make_unique<VerilatedContext>()),
        dut_(std::make_unique<Vtop>(context_.get())) {
    if (!options.wave_path.empty()) {
      context_->traceEverOn(true);
      trace_ = std::make_unique<VerilatedVcdC>();
      dut_->trace(trace_.get(), 16);
      trace_->open(options.wave_path.c_str());
    }
  }

  ~Simulator() {
    dut_->final();
    if (trace_) trace_->close();
  }

  void reset() {
    dut_->reset = 1;
    tick();
    tick();
    dut_->reset = 0;
  }

  void tick() {
    half_cycle(0);
    half_cycle(1);
  }

  std::uint32_t gpr(unsigned index) const {
    return index < 16 ? dut_->gpr_state[index] : 0;
  }

  const Vtop &dut() const { return *dut_; }

 private:
  void half_cycle(std::uint8_t clock) {
    dut_->clock = clock;
    dut_->eval();
    if (trace_) trace_->dump(context_->time());
    context_->timeInc(1);
  }

  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<Vtop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
};

void print_itrace(const Vtop &dut) {
  if (!dut.commit_valid) return;
  std::cout << "0x" << std::hex << std::setw(8) << std::setfill('0')
            << dut.commit_pc << ": 0x" << std::setw(8) << dut.commit_inst
            << std::dec << '\n';
}

class Difftest {
 public:
  Difftest(const std::string &path, const Memory &memory, std::size_t image_size) {
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

  ~Difftest() {
    if (handle_ != nullptr) dlclose(handle_);
  }

  bool step(const Simulator &simulator) {
    exec_(1);
    CpuState reference{};
    regcpy_(&reference, kToDut);
    const auto &dut = simulator.dut();
    bool matched = true;
    if (reference.pc != dut.pc) {
      report("pc", dut.commit_pc, reference.pc, dut.pc);
      matched = false;
    }
    for (unsigned i = 0; i < 16; ++i) {
      const auto dut_value = simulator.gpr(i);
      if (reference.gpr[i] != dut_value) {
        report(("x" + std::to_string(i)).c_str(), dut.commit_pc,
               reference.gpr[i], dut_value);
        matched = false;
      }
    }
    return matched;
  }

 private:
  struct CpuState {
    std::uint32_t gpr[16];
    std::uint32_t pc;
  };
  using MemcpyFn = void (*)(std::uint32_t, void *, std::size_t, bool);
  using RegcpyFn = void (*)(void *, bool);
  using ExecFn = void (*)(std::uint64_t);
  using InitFn = void (*)(int);
  static constexpr bool kToDut = false;
  static constexpr bool kToRef = true;

  template <typename T>
  T load_symbol(const char *name) {
    dlerror();
    void *symbol = dlsym(handle_, name);
    if (const char *error = dlerror(); error != nullptr) {
      throw std::runtime_error("missing DiffTest symbol " + std::string(name) +
                               ": " + error);
    }
    return reinterpret_cast<T>(symbol);
  }

  static void report(const char *name, std::uint32_t commit_pc,
                     std::uint32_t reference, std::uint32_t dut) {
    std::cerr << "DiffTest mismatch after pc=0x" << std::hex << std::setw(8)
              << std::setfill('0') << commit_pc << ": " << name
              << " ref=0x" << std::setw(8) << reference << " dut=0x"
              << std::setw(8) << dut << std::dec << '\n';
  }

  void *handle_ = nullptr;
  MemcpyFn memcpy_ = nullptr;
  RegcpyFn regcpy_ = nullptr;
  ExecFn exec_ = nullptr;
  InitFn init_ = nullptr;
};

}  // namespace

extern "C" std::uint32_t pmem_read(std::uint32_t address,
                                    std::uint8_t length) {
  return g_memory == nullptr ? 0 : g_memory->read(address, length);
}

extern "C" void pmem_write(std::uint32_t address, std::uint32_t data,
                             std::uint8_t mask) {
  if (g_memory != nullptr) g_memory->write(address, data, mask);
}

extern "C" void npc_ebreak(std::uint32_t pc, std::uint32_t code) {
  g_run_state.halted = true;
  g_run_state.pc = pc;
  g_run_state.code = code;
}

extern "C" void npc_abort(std::uint32_t pc, std::uint32_t inst) {
  g_run_state.aborted = true;
  g_run_state.pc = pc;
  std::cerr << "illegal instruction at pc=0x" << std::hex << std::setw(8)
            << std::setfill('0') << pc << ": 0x" << std::setw(8) << inst
            << std::dec << '\n';
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const Options options = parse_options(argc, argv);

  try {
    Memory memory;
    g_memory = &memory;
    const auto image_size = memory.load_image(options.image_path);
    std::cout << "loaded " << image_size << " bytes at 0x" << std::hex
              << kPmemBase << std::dec << '\n';

    Simulator simulator(options);
    simulator.reset();
    g_memory_checks_enabled = true;
    std::unique_ptr<Difftest> difftest;
    if (!options.diff_path.empty()) {
      difftest = std::make_unique<Difftest>(options.diff_path, memory, image_size);
    }

    std::uint64_t executed = 0;
    while (!g_run_state.halted && !g_run_state.aborted &&
           executed < options.max_cycles) {
      simulator.tick();
      ++executed;
      if (options.itrace) print_itrace(simulator.dut());
      if (difftest && !difftest->step(simulator)) {
        g_run_state.aborted = true;
      }
    }

    if (g_run_state.aborted) {
      std::cerr << "ABORT after " << executed << " cycles\n";
      return EXIT_FAILURE;
    }
    if (!g_run_state.halted) {
      std::cerr << "TIMEOUT after " << executed << " cycles at pc=0x"
                << std::hex << simulator.dut().pc << std::dec << '\n';
      return EXIT_FAILURE;
    }
    if (options.image_path.empty() && simulator.gpr(2) != 3) {
      std::cerr << "FAIL: built-in program expected x2=3, got "
                << simulator.gpr(2) << '\n';
      return EXIT_FAILURE;
    }
    if (g_run_state.code != 0) {
      std::cerr << "BAD TRAP at pc=0x" << std::hex << g_run_state.pc
                << std::dec << ", code=" << g_run_state.code << '\n';
      return EXIT_FAILURE;
    }

    std::cout << "GOOD TRAP at pc=0x" << std::hex << g_run_state.pc
              << std::dec << " after " << executed << " cycles\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
