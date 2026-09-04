#include <am.h>
#include <klib.h>
#include <stdint.h>

#define GPIO_BASE 0x20001000u
#define GPIO_OUT  (*(volatile uint32_t *)(GPIO_BASE + 0x0u))
#define GPIO_IN   (*(volatile uint32_t *)(GPIO_BASE + 0x4u))
#define GPIO_SEG  (*(volatile uint32_t *)(GPIO_BASE + 0x8u))
#define PASSWORD  0x0265u

static void short_delay(void) {
  // 只用于让仿真器观察到相邻 LED 图案，不代表真实板上的可见延时。
  for (volatile unsigned i = 0; i < 8u; ++i) {}
}

int main(void) {
  // 流水灯：逐位点亮 16 个 LED，验证输出寄存器可连续更新。
  for (unsigned bit = 0; bit < 16u; ++bit) {
    GPIO_OUT = 1u << bit;
    short_delay();
  }

  // 密码锁：拨码输入完全等于密码时显示 0x600d，否则显示 0xdead。
  GPIO_OUT = ((GPIO_IN & 0xffffu) == PASSWORD) ? 0x600du : 0xdeadu;

  // 8 个半字节按“高位在左、低位在右”显示申请编号 25100265。
  GPIO_SEG = 0x25100265u;
  putstr("SoC GPIO smoke passed\n");
  return 0;
}
