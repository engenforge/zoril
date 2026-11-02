// expected exit code: 100
// 05_ownership_move.zil: Exercises move semantics

f1: i32 main() {
  @b0:
    v1: BoxMut<i32> = alloc 'heap, i32
    v2: i32 = const 100
    v3: unit = store v1, v2
    v4: BoxMut<i32> = move v1
    v5: i32 = load v4
    drop v4
    ret v5
}
