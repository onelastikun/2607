// MiniRV 的 NVBoard 仿真入口，负责窗口更新和时钟推进。
#include <nvboard.h>

#include <cstdint>
#include <cstdlib>
#include <string>

#include "Vnvboard_top.h"

void nvboard_bind_all_pins(Vnvboard_top *top);

namespace {

// NVBoard 和普通仿真器一样，以一次低电平和一次高电平构成完整周期。
void tick(Vnvboard_top &dut) {
  dut.clock = 0;
  dut.eval();
  dut.clock = 1;
  dut.eval();
}

}  // 匿名命名空间

int main(int argc, char **argv) {
  // 0 表示交互窗口持续运行；smoke 测试通过 --cycles 设置有限周期数。
  std::uint64_t max_cycles = 0;
  if (argc == 3 && std::string(argv[1]) == "--cycles") {
    max_cycles = std::strtoull(argv[2], nullptr, 0);
  }

  Vnvboard_top dut;
  // auto_pin_bind.py 生成该函数，将顶层端口连接到 NVBoard 虚拟器件。
  nvboard_bind_all_pins(&dut);
  nvboard_init();

  // 保持多个周期的同步复位，使寄存器和 PC 获得确定初值。
  dut.reset = 1;
  for (int i = 0; i < 10; ++i) tick(dut);
  dut.reset = 0;

  for (std::uint64_t cycles = 0;
       max_cycles == 0 || cycles < max_cycles; ++cycles) {
    // 先读取开关/按键并刷新显示，再让电路前进一步。
    nvboard_update();
    tick(dut);
  }

  dut.final();
  nvboard_quit();
  return 0;
}
