/* particles.zrl in C. */
#include <stdint.h>
#include <stddef.h>
#ifndef SCALE
#define SCALE 300000
#endif
typedef struct { int64_t x, y, vx, vy; } P;
static void step(P *p) {
    p->x += p->vx; p->y += p->vy;
    if (p->x < 0 || p->x > 100000) p->vx = -p->vx;
    if (p->y < 0 || p->y > 100000) p->vy = -p->vy;
}
static int64_t energy(const P *p) { return p->vx * p->vx + p->vy * p->vy; }
static P ps[1024];
int main(void) {
    for (size_t i = 0; i < 1024; i++) ps[i] = (P){ (int64_t)(i * 97), (int64_t)(i * 89), (int64_t)(i % 7) + 1, (int64_t)(i % 5) + 1 };
    int64_t e = 0;
    for (int r = 0; r < SCALE; r++) {
        for (size_t j = 0; j < 1024; j++) step(&ps[j]);
        e += energy(&ps[(size_t)r % 1024]) + ps[7].x;
    }
    return (int)(e % 251);
}
