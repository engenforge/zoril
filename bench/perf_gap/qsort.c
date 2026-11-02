/* qsort.zrl in C. */
#include <stdint.h>
#include <stddef.h>
#ifndef SCALE
#define SCALE 1000000
#endif
static void sort(uint32_t *a, size_t lo, size_t hi) {
    if (lo + 1 >= hi) return;
    uint32_t pivot = a[(lo + hi) / 2];
    size_t i = lo, j = hi - 1;
    while (i <= j) {
        while (a[i] < pivot) i++;
        while (a[j] > pivot) j--;
        if (i <= j) {
            uint32_t t = a[i]; a[i] = a[j]; a[j] = t;
            i++;
            if (j == 0) break;
            j--;
        }
    }
    sort(a, lo, j + 1);
    sort(a, i, hi);
}
static uint32_t data[SCALE];
int main(void) {
    uint32_t acc = 0, seed = 12345;
    for (int r = 0; r < 5; r++) {
        for (size_t i = 0; i < SCALE; i++) { seed = seed * 1103515245u + 12345u; data[i] = seed >> 8; }
        sort(data, 0, SCALE);
        acc += data[0] + data[SCALE / 2] + data[SCALE - 1];
    }
    return (int)(acc % 251);
}
