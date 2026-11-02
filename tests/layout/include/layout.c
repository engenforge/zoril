/* The C twin of layout.zrl: the same structs, the same output lines. Compared by
   scripts/test_struct_layout.sh. */
#include <stdalign.h>
#include <stddef.h>
#include <stdio.h>

struct A { unsigned char a; int b; double c; const unsigned char *d; };
struct B { unsigned char x; unsigned short y; unsigned char z; };
struct C { struct A a; unsigned char t; };
struct D { unsigned long p; unsigned char q; };
struct F { unsigned char c, d, e; };
struct G { float f; _Bool h; long i; };
struct H { short n; long m; short k; };
struct Arr { unsigned char a[5]; unsigned int b; };
struct ArrS { struct B a[2]; unsigned char t; };
/* No member for an empty Zoril struct: C has no zero-sized member. */
struct Zst { unsigned char a; unsigned int b; };

#define LINE(name, T, o0, o1, o2, o3) \
    printf("%s %zu %zu %zu %zu %zu %zu\n", name, sizeof(T), alignof(T), (size_t)(o0), (size_t)(o1), (size_t)(o2), (size_t)(o3))

int main(void) {
    LINE("A", struct A, offsetof(struct A, a), offsetof(struct A, b), offsetof(struct A, c), offsetof(struct A, d));
    LINE("B", struct B, offsetof(struct B, x), offsetof(struct B, y), offsetof(struct B, z), 0);
    LINE("C", struct C, offsetof(struct C, a), offsetof(struct C, t), 0, 0);
    LINE("D", struct D, offsetof(struct D, p), offsetof(struct D, q), 0, 0);
    LINE("F", struct F, offsetof(struct F, c), offsetof(struct F, d), offsetof(struct F, e), 0);
    LINE("G", struct G, offsetof(struct G, f), offsetof(struct G, h), offsetof(struct G, i), 0);
    LINE("H", struct H, offsetof(struct H, n), offsetof(struct H, m), offsetof(struct H, k), 0);
    LINE("Arr", struct Arr, offsetof(struct Arr, a), offsetof(struct Arr, b), 0, 0);
    LINE("ArrS", struct ArrS, offsetof(struct ArrS, a), offsetof(struct ArrS, t), 0, 0);
    LINE("Zst", struct Zst, offsetof(struct Zst, a), offsetof(struct Zst, b), 0, 0);
    return 0;
}
