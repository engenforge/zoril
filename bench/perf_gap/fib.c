/* fib.zrl in C. */
#ifndef SCALE
#define SCALE 38
#endif
static int fib(int n) { if (n <= 1) return n; return fib(n - 1) + fib(n - 2); }
int main(void) { int sum = 0; for (int i = 0; i < 3; i++) sum += fib(SCALE); return sum % 251; }
