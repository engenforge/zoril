// expected exit code: 0
// 06_ownership_drop.zil: Exercises manual drop

f1: i32 main() {
  @b0:
    v1: BoxMut<i32> = alloc 'heap, i32
    v2: i32 = const 5
    v3: unit = store v1, v2
    v4: unit = drop v1
    v5: i32 = const 0
    ret v5
}
