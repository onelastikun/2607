// ysyxSoC 仿真入口：装载 Flash 镜像、驱动双时钟并汇总 CPU 退出状态。
#include <verilated.h>

#include <csignal>
#include <cstdlib>
#include <iomanip>
#include <iostream>

#include "flash_image.h"
#include "options.h"
#include "runtime.h"
#include "simulator.h"
#include "types.h"

namespace {

// 信号处理函数只能设置简单标志，不能在异步上下文中操作 iostream、SDL 或 Verilator。
volatile std::sig_atomic_t g_stop_requested = 0;

void handle_sigint(int) {
  g_stop_requested = 1;
}

constexpr int kSigintExitCode = 128 + SIGINT;

}  // 匿名命名空间

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
    // SDL/NVBoard 初始化可能修改进程信号处理器，因此必须在构造完成后注册。
    if (std::signal(SIGINT, handle_sigint) == SIG_ERR) {
      std::cerr << "fatal: 无法注册 Ctrl-C 信号处理函数\n";
      return EXIT_FAILURE;
    }
    simulator.reset();

    while (!g_stop_requested && !state.halted && !state.aborted &&
           (options.max_cpu_cycles == 0 ||
            simulator.cpu_cycles() < options.max_cpu_cycles)) {
      simulator.step();
    }

    if (g_stop_requested) {
      std::cerr << "\n收到 Ctrl-C，正在关闭波形、NVBoard 和 Verilator。\n";
      return kSigintExitCode;
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
      std::cout << "程序已结束，关闭 NVBoard 窗口或按 Ctrl-C 退出。\n";
      while (!g_stop_requested) simulator.idle_nvboard();
      std::cerr << "\n收到 Ctrl-C，正在关闭波形、NVBoard 和 Verilator。\n";
      return kSigintExitCode;
    }
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
