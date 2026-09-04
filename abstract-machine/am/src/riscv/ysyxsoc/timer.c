#include <am.h>
#include <stdint.h>

#ifndef YSYXSOC_CPU_FREQ
#error "YSYXSOC_CPU_FREQ must be provided by the platform Makefile"
#endif

static inline uint32_t read_mcycle(void) {
  uint32_t value;
  asm volatile("csrr %0, mcycle" : "=r"(value));
  return value;
}

static inline uint32_t read_mcycleh(void) {
  uint32_t value;
  asm volatile("csrr %0, mcycleh" : "=r"(value));
  return value;
}

static uint64_t read_cycle64(void) {
  uint32_t high_before;
  uint32_t low;
  uint32_t high_after;

  // RV32 需要在高 32 位未变化时接受低 32 位，避免回绕瞬间读到撕裂值。
  do {
    high_before = read_mcycleh();
    low = read_mcycle();
    high_after = read_mcycleh();
  } while (high_before != high_after);

  return ((uint64_t)high_after << 32) | low;
}

void __am_timer_init(void) {
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  const uint64_t cycles = read_cycle64();
  const uint64_t seconds = cycles / YSYXSOC_CPU_FREQ;
  const uint64_t remainder = cycles % YSYXSOC_CPU_FREQ;

  // 先做商和余数分解，避免长时间运行后 cycles * 1000000 溢出。
  uptime->us = seconds * 1000000ull
             + remainder * 1000000ull / YSYXSOC_CPU_FREQ;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour = 0;
  rtc->day = 0;
  rtc->month = 0;
  rtc->year = 1900;
}
