#include "options.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace npc {
namespace {

[[noreturn]] void usage(const char *program, const char *message = nullptr) {
  if (message != nullptr) std::cerr << "error: " << message << '\n';
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

}  // namespace

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

}  // namespace npc
