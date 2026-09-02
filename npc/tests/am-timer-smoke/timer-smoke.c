#include <am.h>
#include <klib-macros.h>

int main() {
  ioe_init();
  uint64_t begin = io_read(AM_TIMER_UPTIME).us;
  uint64_t now = begin;
  while (now - begin < 1000) {
    uint64_t next = io_read(AM_TIMER_UPTIME).us;
    if (next < now) return 1;
    now = next;
  }
  return 0;
}
