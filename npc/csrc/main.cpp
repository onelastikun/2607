#include <verilated.h>

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <memory>

#include "device.h"
#include "difftest.h"
#include "memory.h"
#include "options.h"
#include "runtime.h"
#include "simulator.h"
#include "types.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const npc::Options options = npc::parse_options(argc, argv);

  try {
    npc::Memory memory;
    npc::DeviceMap devices;
    npc::RunState state;
    npc::bind_runtime(memory, devices, state);

    const auto image_size = memory.load_image(options.image_path);
    std::cout << "loaded " << image_size << " bytes at 0x" << std::hex
              << npc::kPmemBase << std::dec << '\n';

    npc::Simulator simulator(options);
    simulator.reset();
    memory.enable_checks();

    std::unique_ptr<npc::Difftest> difftest;
    if (!options.diff_path.empty()) {
      difftest =
          std::make_unique<npc::Difftest>(options.diff_path, memory, image_size);
    }

    std::uint64_t executed = 0;
    while (!state.halted && !state.aborted && !memory.faulted() &&
           executed < options.max_cycles) {
      simulator.tick();
      ++executed;
      if (simulator.commit_valid()) {
        if (options.itrace) simulator.print_commit();
        if (difftest && !difftest->step(simulator)) state.aborted = true;
      }
    }

    if (memory.faulted()) {
      std::cerr << memory.fault_message() << '\n';
      state.aborted = true;
    }
    if (state.aborted) {
      std::cerr << "ABORT after " << executed << " cycles\n";
      return EXIT_FAILURE;
    }
    if (!state.halted) {
      std::cerr << "TIMEOUT after " << executed << " cycles at pc=0x"
                << std::hex << simulator.pc() << std::dec << '\n';
      return EXIT_FAILURE;
    }
    if (options.image_path.empty() && simulator.gpr(2) != 3) {
      std::cerr << "FAIL: built-in program expected x2=3, got "
                << simulator.gpr(2) << '\n';
      return EXIT_FAILURE;
    }
    if (state.code != 0) {
      std::cerr << "BAD TRAP at pc=0x" << std::hex << state.pc << std::dec
                << ", code=" << state.code << '\n';
      return EXIT_FAILURE;
    }

    std::cout << "GOOD TRAP at pc=0x" << std::hex << state.pc << std::dec
              << " after " << executed << " cycles\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
