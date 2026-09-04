// ysyxSoC 的 NVBoard 入口：加载 Flash、驱动双时钟并连接开关、LED、数码管和 UART。
#include <nvboard.h>
#include <verilated.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

#include "VSimTop.h"
#include "flash_image.h"
#include "runtime.h"
#include "types.h"

void nvboard_bind_all_pins(VSimTop *top);

namespace {

struct Options {
  std::string image_path;
  std::uint64_t max_cpu_cycles = 0;
};

[[noreturn]] void usage(const char *program, const char *message = nullptr) {
  if (message != nullptr) std::cerr << "error: " << message << '\n';
  std::cerr << "usage: " << program << " --image FILE [--cycles N]\n";
  std::exit(EXIT_FAILURE);
}

Options parse_options(int argc, char **argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--image") {
      if (++index >= argc) usage(argv[0], "--image 缺少路径");
      options.image_path = argv[index];
    } else if (argument == "--cycles") {
      if (++index >= argc) usage(argv[0], "--cycles 缺少数值");
      char *end = nullptr;
      options.max_cpu_cycles = std::strtoull(argv[index], &end, 0);
      if (end == argv[index] || *end != '\0') usage(argv[0], "周期数格式错误");
    } else if (argument == "--help" || argument == "-h") {
      usage(argv[0]);
    } else {
      usage(argv[0], "未知参数");
    }
  }
  if (options.image_path.empty()) usage(argv[0], "必须指定 --image");
  return options;
}

class BoardDriver {
 public:
  explicit BoardDriver(VSimTop &dut) : dut_(dut) {}

  void reset() {
    dut_.clock = 0;
    dut_.cpuClock = 0;
    dut_.reset = 1;
    dut_.coreSel = 0;
    dut_.eval();
    while (cpu_cycles_ < 40) step();
    dut_.reset = 0;
  }

  void step() {
    dut_.cpuClock = !dut_.cpuClock;
    bool soc_rising = false;
    if ((phase_ & 1u) != 0u) {
      dut_.clock = !dut_.clock;
      soc_rising = dut_.clock != 0;
    }
    phase_ = (phase_ + 1u) & 3u;
    if (dut_.cpuClock) ++cpu_cycles_;
    dut_.eval();

    // 每个 SoC 上升沿更新一次板级器件，与 UART 的 16 倍过采样节拍保持一致。
    if (soc_rising) nvboard_update();
  }

  std::uint64_t cpu_cycles() const { return cpu_cycles_; }

 private:
  VSimTop &dut_;
  unsigned phase_ = 0;
  std::uint64_t cpu_cycles_ = 0;
};

}  // 匿名命名空间

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const Options options = parse_options(argc, argv);

  try {
    npc::soc::FlashImage flash;
    flash.load(options.image_path);
    npc::soc::RunState state;
    npc::soc::bind_runtime(flash, state);

    VSimTop dut;
    nvboard_bind_all_pins(&dut);
    nvboard_init();

    BoardDriver board(dut);
    board.reset();
    while (!state.halted && !state.aborted &&
           (options.max_cpu_cycles == 0 ||
            board.cpu_cycles() < options.max_cpu_cycles)) {
      board.step();
    }

    int result = EXIT_SUCCESS;
    if (state.aborted) {
      std::cerr << "NVBoard SoC aborted at pc=0x" << std::hex << state.pc
                << std::dec << '\n';
      result = EXIT_FAILURE;
    } else if (state.halted) {
      std::cout << "NVBoard SoC halted, code=" << state.code
                << ", CPU cycles=" << board.cpu_cycles() << '\n';
      result = state.code == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
    } else {
      std::cout << "NVBoard smoke stopped after " << board.cpu_cycles()
                << " CPU cycles\n";
    }

    dut.final();
    nvboard_quit();
    return result;
  } catch (const std::exception &error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
