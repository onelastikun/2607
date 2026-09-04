#include <am.h>
#include <klib-macros.h>

void __am_timer_init(void);
void __am_timer_rtc(AM_TIMER_RTC_T *rtc);
void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime);
void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd);

static void timer_config(AM_TIMER_CONFIG_T *cfg) {
  cfg->present = true;
  cfg->has_rtc = false;
}

static void input_config(AM_INPUT_CONFIG_T *cfg) {
  cfg->present = true;
}

static void uart_config(AM_UART_CONFIG_T *cfg) {
  cfg->present = false;
}

static void audio_config(AM_AUDIO_CONFIG_T *cfg) {
  cfg->present = false;
}

typedef void (*handler_t)(void *buf);
static handler_t handlers[128] = {
  [AM_TIMER_CONFIG] = (handler_t)timer_config,
  [AM_TIMER_RTC] = (handler_t)__am_timer_rtc,
  [AM_TIMER_UPTIME] = (handler_t)__am_timer_uptime,
  [AM_INPUT_CONFIG] = (handler_t)input_config,
  [AM_INPUT_KEYBRD] = (handler_t)__am_input_keybrd,
  [AM_UART_CONFIG] = (handler_t)uart_config,
  [AM_AUDIO_CONFIG] = (handler_t)audio_config,
};

static void unsupported(void *buf) {
  (void)buf;
  panic("access nonexist register");
}

bool ioe_init(void) {
  for (int i = 0; i < LENGTH(handlers); ++i) {
    if (handlers[i] == NULL) handlers[i] = unsupported;
  }
  __am_timer_init();
  return true;
}

void ioe_read(int reg, void *buf) {
  handlers[reg](buf);
}

void ioe_write(int reg, void *buf) {
  handlers[reg](buf);
}
