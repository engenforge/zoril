#include <stdio.h>

int main(void) {
    int a[4096] = {0};
    for (int iter = 0; iter < 500000; iter++) {
        for (int i = 0; i < 4096; i++) {
            a[i] += 1;
        }
    }
    return a[0] == 500000 ? 0 : 1;
}
