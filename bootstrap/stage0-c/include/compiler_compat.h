#ifndef ZORIL_COMPILER_COMPAT_H
#define ZORIL_COMPILER_COMPAT_H

/**
 * Portability macro for printf-style format string validation.
 *
 * Supported on GCC and Clang. Silently expands to nothing on other
 * compilers (like cproc/mcpp).
 */
#if defined(__GNUC__) || defined(__clang__)
#  define PRINTF_FORMAT(fmt_idx, arg_idx) \
       __attribute__((format(printf, fmt_idx, arg_idx)))
#  define NORETURN __attribute__((noreturn))
#else
#  define PRINTF_FORMAT(fmt_idx, arg_idx)
#  define NORETURN
#endif

#endif /* ZORIL_COMPILER_COMPAT_H */
