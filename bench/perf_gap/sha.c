/* The stdlib Sha256 algorithm, written the same way in C (byte-at-a-time update). */
#include <stdint.h>
#include <stddef.h>
#ifndef SCALE
#define SCALE 1048576
#endif
typedef struct { uint32_t state[8]; uint8_t buffer[64]; size_t buf_len; uint64_t total_len; uint32_t k[64]; } Sha256;
static const uint32_t K[64] = {
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
static void init(Sha256 *s) {
    static const uint32_t H[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    for (int i = 0; i < 8; i++) s->state[i] = H[i];
    for (int i = 0; i < 64; i++) { s->buffer[i] = 0; s->k[i] = K[i]; }
    s->buf_len = 0; s->total_len = 0;
}
static void compress(Sha256 *s) {
    uint32_t w[64] = {0};
    size_t t = 0;
    for (; t < 16; t++) {
        size_t idx = t * 4;
        w[t] = ((uint32_t)s->buffer[idx] << 24) | ((uint32_t)s->buffer[idx+1] << 16) | ((uint32_t)s->buffer[idx+2] << 8) | s->buffer[idx+3];
    }
    for (; t < 64; t++) {
        uint32_t w15 = w[t-15], w2 = w[t-2];
        uint32_t g0 = ((w15 >> 7) | (w15 << 25)) ^ ((w15 >> 18) | (w15 << 14)) ^ (w15 >> 3);
        uint32_t g1 = ((w2 >> 17) | (w2 << 15)) ^ ((w2 >> 19) | (w2 << 13)) ^ (w2 >> 10);
        w[t] = g1 + w[t-7] + g0 + w[t-16];
    }
    uint32_t a=s->state[0],b=s->state[1],c=s->state[2],d=s->state[3],e=s->state[4],f=s->state[5],g=s->state[6],h=s->state[7];
    for (size_t i = 0; i < 64; i++) {
        uint32_t s1 = ((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7));
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t t1 = h + s1 + ch + s->k[i] + w[i];
        uint32_t s0 = ((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10));
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = s0 + maj;
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    s->state[0]+=a; s->state[1]+=b; s->state[2]+=c; s->state[3]+=d; s->state[4]+=e; s->state[5]+=f; s->state[6]+=g; s->state[7]+=h;
}
static void update(Sha256 *s, const uint8_t *data, size_t len) {
    s->total_len += len;
    for (size_t i = 0; i < len; i++) {
        s->buffer[s->buf_len] = data[i];
        s->buf_len++;
        if (s->buf_len == 64) { compress(s); s->buf_len = 0; }
    }
}
static void finalize(Sha256 *s, uint8_t out[32]) {
    uint64_t bits = s->total_len * 8;
    uint8_t pad = 0x80; update(s, &pad, 1);
    uint8_t z = 0; while (s->buf_len != 56) update(s, &z, 1);
    for (int i = 7; i >= 0; i--) { uint8_t b = (uint8_t)(bits >> (i * 8)); update(s, &b, 1); }
    for (int i = 0; i < 8; i++) { out[i*4] = s->state[i] >> 24; out[i*4+1] = s->state[i] >> 16; out[i*4+2] = s->state[i] >> 8; out[i*4+3] = s->state[i]; }
}
static uint8_t buf[SCALE];
int main(void) {
    for (size_t i = 0; i < sizeof buf; i++) buf[i] = (uint8_t)(i * 31);
    uint32_t acc = 0;
    for (int r = 0; r < 32; r++) {
        Sha256 h; init(&h); update(&h, buf, sizeof buf);
        uint8_t d[32]; finalize(&h, d);
        acc += d[0] + d[31]; buf[0] = d[1];
    }
    return (int)(acc % 251);
}
