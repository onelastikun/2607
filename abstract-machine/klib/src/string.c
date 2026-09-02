#include <klib.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  const char *end = s;
  while (*end != '\0') end++;
  return (size_t)(end - s);
}

char *strcpy(char *dst, const char *src) {
  char *result = dst;
  while ((*dst++ = *src++) != '\0') {}
  return result;
}

char *strncpy(char *dst, const char *src, size_t n) {
  char *result = dst;
  size_t i = 0;
  for (; i < n && src[i] != '\0'; i++) dst[i] = src[i];
  for (; i < n; i++) dst[i] = '\0';
  return result;
}

char *strcat(char *dst, const char *src) {
  strcpy(dst + strlen(dst), src);
  return dst;
}

int strcmp(const char *s1, const char *s2) {
  while (*s1 != '\0' && *s1 == *s2) {
    s1++;
    s2++;
  }
  return (unsigned char)*s1 - (unsigned char)*s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  for (size_t i = 0; i < n; i++) {
    const unsigned char a = (unsigned char)s1[i];
    const unsigned char b = (unsigned char)s2[i];
    if (a != b) return a - b;
    if (a == '\0') return 0;
  }
  return 0;
}

void *memset(void *s, int c, size_t n) {
  unsigned char *dst = s;
  for (size_t i = 0; i < n; i++) dst[i] = (unsigned char)c;
  return s;
}

void *memmove(void *dst, const void *src, size_t n) {
  unsigned char *out = dst;
  const unsigned char *in = src;
  if (out <= in || out >= in + n) {
    for (size_t i = 0; i < n; i++) out[i] = in[i];
  } else {
    for (size_t i = n; i > 0; i--) out[i - 1] = in[i - 1];
  }
  return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
  unsigned char *out = dst;
  const unsigned char *in = src;
  for (size_t i = 0; i < n; i++) out[i] = in[i];
  return dst;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  const unsigned char *a = s1;
  const unsigned char *b = s2;
  for (size_t i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

char *strchr(const char *s, int c) {
  do {
    if (*s == c) return (char *)s;
  } while (*s++ != '\0');
  return NULL;
}

char *strrchr(const char *s, int c) {
  const char *last = NULL;
  do {
    if (*s == c) last = s;
  } while (*s++ != '\0');
  return (char *)last;
}

#endif
