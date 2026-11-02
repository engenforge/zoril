/* A C main for the Zoril exports: no libc, linked with rt/runtime.o, which supplies _start. */
#include <stdarg.h>

int zoril_add(int a, int b);
int zoril_twice(int a);
int zoril_index(unsigned long i);
int zoril_from_module(int a);
int zoril_helper_mul(int a, int b);
double zoril_variadic_double(float x);
long long zoril_variadic_int(signed char a, unsigned char b);

double c_sum_doubles(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, double);
    va_end(ap);
    return s;
}

long long c_sum_ints(int n, ...) {
    va_list ap;
    va_start(ap, n);
    long long s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, int);
    va_end(ap);
    return s;
}

int main(void) {
#ifdef TRAP
    return zoril_index(7);          /* out of bounds: the trap ends the process with 134 */
#else
    if (zoril_add(40, 2) != 42) return 1;
    if (zoril_twice(21) != 42) return 2;
    if (zoril_index(2) != 30) return 3;
    if (zoril_from_module(5) != 15) return 4;
    if (zoril_helper_mul(6, 7) != 42) return 5;
    /* f32 is promoted to double and i8/u8 to int for the `...` arguments. */
    if (zoril_variadic_double(1.5f) != 1.5) return 6;
    if (zoril_variadic_int(-1, 200) != 199) return 7;
    return 0;
#endif
}
