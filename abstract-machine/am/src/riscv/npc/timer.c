#include <am.h>

#define RTC_ADDR 0xa0000048u

void __am_timer_init() {
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  volatile uint32_t *rtc = (volatile uint32_t *)RTC_ADDR;
  uint32_t high_before;
  uint32_t low;
  uint32_t high_after;

  // Re-read the high word to avoid observing a torn 64-bit counter rollover.
  do {
    high_before = rtc[1];
    low = rtc[0];
    high_after = rtc[1];
  } while (high_before != high_after);

  uptime->us = ((uint64_t)high_after << 32) | low;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 0;
  rtc->month  = 0;
  rtc->year   = 1900;
}
