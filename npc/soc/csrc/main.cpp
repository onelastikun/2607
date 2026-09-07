// ysyxSoC 仿真入口：装载 Flash 镜像、驱动双时钟并汇总 CPU 退出状态。
#include <verilated.h>

#include <cstdlib>
#include <iomanip>
#include <iostream>

#include "flash_image.h"
#include "options.h"
#include "runtime.h"
#include "simulator.h"
#include "types.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const auto options = npc::soc::parse_options(argc, argv);

  try {
    npc::soc::FlashImage flash;
    flash.load(options.image_path);
    npc::soc::RunState state;
    npc::soc::bind_runtime(flash, state);

    std::cout << "loaded SoC flash image: " << flash.size() << " bytes\n";
    npc::soc::Simulator simulator(options);
    simulator.reset();

    while (!state.halted && !state.aborted &&
           (options.max_cpu_cycles == 0 ||
            simulator.cpu_cycles() < options.max_cpu_cycles)) {
      simulator.step();
    }

    if (state.aborted) {
      std::cerr << "SoC ABORT after " << simulator.cpu_cycles()
                << " CPU cycles\n";
      return EXIT_FAILURE;
    }
    if (!state.halted) {
      std::cerr << "SoC TIMEOUT after " << simulator.cpu_cycles()
                << " CPU cycles and " << state.instruction_count
                << " instructions, last pc=0x" << std::hex << state.last_pc
                << " inst=0x" << state.last_instruction
                << ", gpio_out=0x" << simulator.gpio_output()
                << ", gpio_digits=0x" << simulator.gpio_digits()
                << ", gpio_changes=" << std::dec << simulator.gpio_change_count()
                << '\n';
      return EXIT_FAILURE;
    }
    if (state.code != 0) {
      std::cerr << "SoC BAD TRAP at pc=0x" << std::hex << state.pc << std::dec
                << ", code=" << state.code << '\n';
      return EXIT_FAILURE;
    }

    std::cout << "SoC GOOD TRAP at pc=0x" << std::hex << state.pc << std::dec
              << " after " << simulator.cpu_cycles() << " CPU cycles and "
              << state.instruction_count << " instructions"
              << ", gpio_out=0x" << std::hex << simulator.gpio_output()
              << ", gpio_digits=0x" << simulator.gpio_digits()
              << ", gpio_changes=" << std::dec << simulator.gpio_change_count()
              << '\n';
    if (simulator.nvboard_enabled()) {
      std::cout << "程序已结束，关闭 NVBoard 窗口退出。\n";
      simulator.wait_for_nvboard_close();
    }
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
