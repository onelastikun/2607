#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

static inline uint32_t read_mvendorid(void) {
  uint32_t value;
  asm volatile("csrr %0, mvendorid" : "=r"(value));
  return value;
}

static inline uint32_t read_marchid(void) {
  uint32_t value;
  asm volatile("csrr %0, marchid" : "=r"(value));
  return value;
}

int main(void) {
  // 讲义规定厂商 ID 为 ASCII "ysyx"，架构 ID 为一生一芯申请编号。
  if (read_mvendorid() != 0x79737978u) return 1;
  if (read_marchid() != 25100265u) return 2;

  ioe_init();
  uint64_t previous = io_read(AM_TIMER_UPTIME).us;
  uint64_t now = previous;

  // 只等待 100 微秒，验证 mcycle 换算后的 AM uptime 单调前进，不做耗时评测。
  while (now - previous < 100u) {
    const uint64_t next = io_read(AM_TIMER_UPTIME).us;
    if (next < now) return 3;
    now = next;
  }

  putstr("SoC CSR/timer smoke passed\n");
  return 0;
}
