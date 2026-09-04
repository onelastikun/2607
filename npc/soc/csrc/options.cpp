// SoC 仿真命令行解析，保持与 NPC 主仿真器相似的参数风格。
#include "options.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace npc::soc {
namespace {

[[noreturn]] void usage(const char *program, const char *message = nullptr) {
  if (message != nullptr) std::cerr << "error: " << message << '\n';
  std::cerr << "usage: " << program
            << " --image FILE [--max-cycles N] [--wave FILE] [--gpio N]\n";
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

}  // 匿名命名空间

Options parse_options(int argc, char **argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--image") {
      if (++i >= argc) usage(argv[0], "missing value after --image");
      options.image_path = argv[i];
    } else if (arg == "--max-cycles") {
      if (++i >= argc) usage(argv[0], "missing value after --max-cycles");
      options.max_cpu_cycles = parse_u64(argv[i], argv[0]);
    } else if (arg == "--wave") {
      if (++i >= argc) usage(argv[0], "missing value after --wave");
      options.wave_path = argv[i];
    } else if (arg == "--gpio") {
      if (++i >= argc) usage(argv[0], "missing value after --gpio");
      const auto value = parse_u64(argv[i], argv[0]);
      if (value > 0xffffu) usage(argv[0], "GPIO input exceeds 16 bits");
      options.gpio_input = static_cast<std::uint16_t>(value);
    } else if (arg == "--help" || arg == "-h") {
      usage(argv[0]);
    } else {
      usage(argv[0], "unknown argument");
    }
  }
  if (options.image_path.empty()) usage(argv[0], "--image is required");
  return options;
}

}  // 命名空间 npc::soc
