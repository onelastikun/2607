#include <verilated.h>
#include <verilated_vcd_c.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

#include "Vtop.h"

namespace {

struct Options {
  std::uint64_t cycles = 10;
  std::string wave_path;
};

[[noreturn]] void usage(const char *program, const char *message = nullptr) {
  if (message != nullptr) {
    std::cerr << "error: " << message << '\n';
  }
  std::cerr << "usage: " << program
            << " [--cycles N] [--wave FILE] [Verilator options]\n";
  std::exit(EXIT_FAILURE);
}

std::uint64_t parse_u64(const char *text, const char *program) {
  char *end = nullptr;
  const auto value = std::strtoull(text, &end, 0);
  if (text[0] == '\0' || end == nullptr || *end != '\0') {
    usage(program, "--cycles expects an integer");
  }
  return value;
}

Options parse_options(int argc, char **argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--cycles") {
      if (++i >= argc) {
        usage(argv[0], "missing value after --cycles");
      }
      options.cycles = parse_u64(argv[i], argv[0]);
    } else if (arg == "--wave") {
      if (++i >= argc) {
        usage(argv[0], "missing value after --wave");
      }
      options.wave_path = argv[i];
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
      dut_->trace(trace_.get(), 8);
      trace_->open(options.wave_path.c_str());
    }
  }

  ~Simulator() {
    dut_->final();
    if (trace_) {
      trace_->close();
    }
  }

  void reset() {
    dut_->reset = 1;
    tick();
    tick();
    dut_->reset = 0;
  }

  void tick() {
    drive_half_cycle(0);
    drive_half_cycle(1);
  }

  std::uint64_t cycle_count() const { return dut_->cycle_count; }

 private:
  void drive_half_cycle(std::uint8_t clock) {
    dut_->clock = clock;
    dut_->eval();
    if (trace_) {
      trace_->dump(context_->time());
    }
    context_->timeInc(1);
  }

  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<Vtop> dut_;
  std::unique_ptr<VerilatedVcdC> trace_;
};

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const Options options = parse_options(argc, argv);

  Simulator simulator(options);
  simulator.reset();

  if (simulator.cycle_count() != 0) {
    std::cerr << "FAIL: reset did not clear cycle_count\n";
    return EXIT_FAILURE;
  }

  for (std::uint64_t i = 0; i < options.cycles; ++i) {
    simulator.tick();
  }

  if (simulator.cycle_count() != options.cycles) {
    std::cerr << "FAIL: expected cycle_count=" << options.cycles
              << ", got " << simulator.cycle_count() << '\n';
    return EXIT_FAILURE;
  }

  std::cout << "PASS: reset, clock and simulation loop verified for "
            << options.cycles << " cycles\n";
  return EXIT_SUCCESS;
}
