// expected exit code: 30
// 24_tuples.zil: Exercises tuple type allocation and field access

f1: i32 main() {
  @b0:
    // Allocate a (i32, i32) tuple on the stack
    v1: PtrMut<(i32, i32), 'local> = alloc 'local, (i32, i32)

    // Store 10 into field 0
    v2: i32 = const 10
    v3: PtrMut<i32, 'local> = field_addr v1, 0
    v4: unit = store v3, v2

    // Store 20 into field 1
    v5: i32 = const 20
    v6: PtrMut<i32, 'local> = field_addr v1, 1
    v7: unit = store v6, v5

    // Load both fields and add them
    v8: Ptr<(i32, i32), 'local> = bitcast v1
    v9: Ptr<i32, 'local> = field_addr v8, 0
    v10: i32 = load v9
    v11: Ptr<i32, 'local> = field_addr v8, 1
    v12: i32 = load v11
    v13: i32 = add v10, v12

    ret v13
}
