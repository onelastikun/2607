#include <klib.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

// A single formatter backs both console and bounded string output.
typedef struct {
  char *buffer;
  size_t size;
  size_t count;
  bool console;
} Output;

static void emit(Output *out, char ch) {
  if (out->console) {
    putch(ch);
  } else if (out->size > 0 && out->count + 1 < out->size) {
    out->buffer[out->count] = ch;
  }
  out->count++;
}

static void emit_repeat(Output *out, char ch, int count) {
  while (count-- > 0) emit(out, ch);
}

static void emit_unsigned(Output *out, uint64_t value, unsigned base,
                          bool upper, int width, char padding,
                          bool left_align, const char *prefix) {
  char reversed[32];
  int length = 0;
  const char *alphabet = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  do {
    reversed[length++] = alphabet[value % base];
    value /= base;
  } while (value != 0);

  const int prefix_len = prefix == NULL ? 0 : (int)strlen(prefix);
  const int pad = width > length + prefix_len ? width - length - prefix_len : 0;
  if (!left_align && padding == ' ') emit_repeat(out, ' ', pad);
  if (prefix != NULL) while (*prefix) emit(out, *prefix++);
  if (!left_align && padding == '0') emit_repeat(out, '0', pad);
  while (length > 0) emit(out, reversed[--length]);
  if (left_align) emit_repeat(out, ' ', pad);
}

static int format(Output *out, const char *fmt, va_list ap) {
  while (*fmt != '\0') {
    if (*fmt != '%') {
      emit(out, *fmt++);
      continue;
    }
    fmt++;
    if (*fmt == '%') {
      emit(out, *fmt++);
      continue;
    }

    bool left_align = false;
    char padding = ' ';
    while (*fmt == '-' || *fmt == '0') {
      if (*fmt == '-') left_align = true;
      if (*fmt == '0') padding = '0';
      fmt++;
    }

    int width = 0;
    while (isdigit(*fmt)) width = width * 10 + (*fmt++ - '0');

    int length = 0;
    if (*fmt == 'l') {
      length = 1;
      fmt++;
      if (*fmt == 'l') { length = 2; fmt++; }
    } else if (*fmt == 'z') {
      length = 1;
      fmt++;
    }

    const char spec = *fmt == '\0' ? '\0' : *fmt++;
    if (spec == 's') {
      const char *str = va_arg(ap, const char *);
      if (str == NULL) str = "(null)";
      const int len = (int)strlen(str);
      if (!left_align) emit_repeat(out, ' ', width > len ? width - len : 0);
      while (*str) emit(out, *str++);
      if (left_align) emit_repeat(out, ' ', width > len ? width - len : 0);
    } else if (spec == 'c') {
      emit(out, (char)va_arg(ap, int));
    } else if (spec == 'd' || spec == 'i') {
      int64_t value = length == 2 ? va_arg(ap, long long)
                    : length == 1 ? va_arg(ap, long)
                                  : va_arg(ap, int);
      const bool negative = value < 0;
      const uint64_t magnitude = negative
          ? (uint64_t)(-(value + 1)) + 1
          : (uint64_t)value;
      char sign[2] = {'-', '\0'};
      emit_unsigned(out, magnitude, 10, false, width, padding, left_align,
                    negative ? sign : NULL);
    } else if (spec == 'u' || spec == 'x' || spec == 'X') {
      uint64_t value = length == 2 ? va_arg(ap, unsigned long long)
                     : length == 1 ? va_arg(ap, unsigned long)
                                   : va_arg(ap, unsigned int);
      emit_unsigned(out, value, spec == 'u' ? 10 : 16, spec == 'X', width,
                    padding, left_align, NULL);
    } else if (spec == 'p') {
      const uintptr_t value = (uintptr_t)va_arg(ap, void *);
      const int pointer_width = width == 0 ? (int)(sizeof(uintptr_t) * 2 + 2) : width;
      emit_unsigned(out, value, 16, false, pointer_width, '0', false, "0x");
    } else if (spec == '\0') {
      break;
    } else {
      // Unsupported conversions stay visible instead of silently corrupting output.
      emit(out, '%');
      emit(out, spec);
    }
  }

  if (!out->console && out->size > 0) {
    const size_t end = out->count < out->size ? out->count : out->size - 1;
    out->buffer[end] = '\0';
  }
  return (int)out->count;
}

int vprintf(const char *fmt, va_list ap) {
  Output out = {.buffer = NULL, .size = 0, .count = 0, .console = true};
  return format(&out, fmt, ap);
}

int printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int result = vprintf(fmt, ap);
  va_end(ap);
  return result;
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  Output output = {.buffer = out, .size = n, .count = 0, .console = false};
  return format(&output, fmt, ap);
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int result = vsnprintf(out, n, fmt, ap);
  va_end(ap);
  return result;
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  return vsnprintf(out, (size_t)-1, fmt, ap);
}

int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int result = vsprintf(out, fmt, ap);
  va_end(ap);
  return result;
}

int __am_vsscanf_internal(const char *str, const char **end_pstr, const char *fmt, va_list ap) {
  const char *pstr = str;
  const char *pfmt = fmt;
  int item = -1;
  while (*pfmt) {
    char ch = *pfmt ++;
    if (isspace(ch)) {
      for (ch = *pfmt; isspace(ch); ch = *(++ pfmt));
      for (ch = *pstr; isspace(ch); ch = *(++ pstr));
      item ++;
      continue;
    }
    switch (ch) {
      case '%': break;
      default:
        if (*pstr == ch) { // match
          pstr ++;
          item ++;
          continue;
        }
        goto end; // fail
    }

    char *p;
    ch = *pfmt ++;
    switch (ch) {
      // conversion specifier
      case 'd':
        *(va_arg(ap, int *)) = strtol(pstr, &p, 10);
        if (p == pstr) goto end; // fail
        pstr = p;
        item ++;
        break;

      case 'c':
        *(va_arg(ap, char *)) = *pstr ++;
        item ++;
        break;

      default:
        printf("Unsupported conversion specifier '%c'\n", ch);
        assert(0);
    }
  }

end:
  if (end_pstr) {
    *end_pstr = pstr;
  }
  return item;
}

int vsscanf(const char *str, const char *fmt, va_list ap) {
  return __am_vsscanf_internal(str, NULL, fmt, ap);
}

int sscanf(const char *str, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int r = vsscanf(str, fmt, ap);
  va_end(ap);
  return r;
}

int __isoc99_sscanf(const char *str, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int r = vsscanf(str, fmt, ap);
  va_end(ap);
  return r;
}

#endif
