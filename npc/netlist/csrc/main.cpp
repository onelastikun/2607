// E8 Verilator 门级仿真入口：加载裸镜像、驱动综合网表并检查测试魔数。
#include <verilated.h>
#include <verilated_vcd_c.h>

#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

#include "Vnetlist_top.h"
#include "device.h"
#include "memory.h"
#include "runtime.h"
#include "types.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  if (argc < 2) {
    std::cerr << "usage: " << argv[0] << " IMAGE [WAVE]\n";
    return EXIT_FAILURE;
  }

  try {
    npc::Memory memory;
    npc::DeviceMap devices;
    npc::RunState state;
    const auto image_size = memory.load_image(argv[1]);
    memory.enable_checks();
    npc::bind_runtime(memory, devices, state);

    auto context = std::make_unique<VerilatedContext>();
    auto dut = std::make_unique<Vnetlist_top>(context.get());
    std::unique_ptr<VerilatedVcdC> trace;
    if (argc >= 3) {
      context->traceEverOn(true);
      trace = std::make_unique<VerilatedVcdC>();
      dut->trace(trace.get(), 8);
      trace->open(argv[2]);
    }

    dut->clock = 0;
    dut->reset = 1;
    auto half_cycle = [&](int clock) {
      dut->clock = clock;
      dut->eval();
      if (trace) trace->dump(context->time());
      context->timeInc(1);
    };
    for (int i = 0; i < 8; ++i) {
      half_cycle(0);
      half_cycle(1);
    }
    dut->reset = 0;

    constexpr std::uint64_t kMaxCycles = 10000;
    std::uint64_t cycles = 0;
    while (!dut->test_passed && !dut->test_failed && cycles < kMaxCycles) {
      half_cycle(0);
      half_cycle(1);
      ++cycles;
    }

    dut->final();
    if (trace) trace->close();
    if (memory.faulted()) {
      std::cerr << memory.fault_message() << '\n';
      return EXIT_FAILURE;
    }
    if (!dut->test_passed || dut->test_failed) {
      std::cerr << "NETLIST BAD TRAP after " << cycles << " cycles\n";
      return EXIT_FAILURE;
    }

    std::cout << "loaded " << image_size << " bytes at 0x" << std::hex
              << npc::kPmemBase << std::dec << '\n';
    std::cout << "NETLIST GOOD TRAP after " << cycles << " cycles\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
