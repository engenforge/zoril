// EXPECT: use after drop: value was already dropped
f0: i32 main() {
  @b0:
    v0: bool = const 1
    v1: BoxMut<i32> = alloc 'heap, i32
    v2: i32 = const 5
    v3: unit = store v1, v2
    branch v0, @b1, @b2
  @b1:
    v4: unit = drop v1
    jump @b3
  @b2:
    jump @b3
  @b3:
    v5: i32 = load v1
    ret v5
}
