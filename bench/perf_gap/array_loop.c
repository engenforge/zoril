/* array_loop.zrl in C. */
#ifndef SCALE
#define SCALE 500000
#endif
int main(void) {
    int a[4096] = {0};
    for (int iter = 0; iter < SCALE; iter++)
        for (unsigned long i = 0; i < 4096; i++) a[i] = a[i] + 1;
    return (a[0] + a[4095]) % 251;
}
