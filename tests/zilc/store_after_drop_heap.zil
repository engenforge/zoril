// EXPECT: use after drop: value was already dropped
f0: i32 main() {
  @b0:
    v1: BoxMut<i32> = alloc 'heap, i32
    v2: i32 = const 5
    v3: unit = store v1, v2
    v4: unit = drop v1
    v5: unit = store v1, v2
    v6: i32 = const 0
    ret v6
}
