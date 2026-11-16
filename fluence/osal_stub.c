#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
int ar_log_lvl = 0;
void ar_log(uint32_t level, const char *tag, const char *file, const char *fn, int32_t ln, const char *fmt, ...) {}
int32_t ar_log_init(void) { return 0; }
int32_t ar_log_deinit(void) { return 0; }
