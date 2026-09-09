#include <am.h>
#include <klib-macros.h>
#include <stdint.h>

extern char _heap_start;
extern char _pmem_start;
int main(const char *args);

#define PMEM_SIZE (128u * 1024u * 1024u)
#define PMEM_END  ((uintptr_t)&_pmem_start + PMEM_SIZE)

// 16550 寄存器按字节编址；这里只使用轮询发送所需的寄存器。
#define UART_BASE 0x10000000u
#define UART_THR  (*(volatile uint8_t *)(UART_BASE + 0u))
#define UART_IER  (*(volatile uint8_t *)(UART_BASE + 1u))
#define UART_FCR  (*(volatile uint8_t *)(UART_BASE + 2u))
#define UART_LCR  (*(volatile uint8_t *)(UART_BASE + 3u))
#define UART_LSR  (*(volatile uint8_t *)(UART_BASE + 5u))

Area heap = RANGE(&_heap_start, PMEM_END);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER);

static void uart_init(void) {
  UART_LCR = 0x80u;
  UART_THR = 0x0Du;  // DLL
  UART_IER = 0x00u;  // DLM
  UART_LCR = 0x03u;  
  UART_FCR = 0x07u;  
}

void putch(char ch) {
  // LSR[5]=1 表示发送保持寄存器为空，此时才能写入下一个字符。
  while ((UART_LSR & 0x20u) == 0u) {}
  UART_THR = (uint8_t)ch;
}

void halt(int code) {
  // 仿真环境从 a0 取得退出码：0 为 good trap，非 0 为 bad trap。
  asm volatile("mv a0, %0; ebreak" : : "r"(code));
  while (1) {}
}

void _trm_init(void) {
  uart_init();
  halt(main(mainargs));
}
