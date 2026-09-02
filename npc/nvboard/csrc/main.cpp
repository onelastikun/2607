#include <nvboard.h>

#include <cstdint>
#include <cstdlib>
#include <string>

#include "Vnvboard_top.h"

void nvboard_bind_all_pins(Vnvboard_top *top);

namespace {

void tick(Vnvboard_top &dut) {
  dut.clock = 0;
  dut.eval();
  dut.clock = 1;
  dut.eval();
}

}  // namespace

int main(int argc, char **argv) {
  std::uint64_t max_cycles = 0;  // Zero keeps the interactive window running.
  if (argc == 3 && std::string(argv[1]) == "--cycles") {
    max_cycles = std::strtoull(argv[2], nullptr, 0);
  }

  Vnvboard_top dut;
  nvboard_bind_all_pins(&dut);
  nvboard_init();

  dut.reset = 1;
  for (int i = 0; i < 10; ++i) tick(dut);
  dut.reset = 0;

  for (std::uint64_t cycles = 0;
       max_cycles == 0 || cycles < max_cycles; ++cycles) {
    nvboard_update();
    tick(dut);
  }

  dut.final();
  nvboard_quit();
  return 0;
}
