// expected exit code: 6
// 23_array_construct.zil: Exercises array_construct and array_load opcodes

f1: i32 main() {
  @b0:
    v1: i32 = const 1
    v2: i32 = const 2
    v3: i32 = const 3
    v4: [i32; 3] = array_construct v1, v2, v3

    // Store the constructed array and load element at index 2
    v5: PtrMut<[i32; 3], 'local> = alloc 'local, [i32; 3]
    v6: unit = store v5, v4
    v7: u64 = const 2
    v8: u64 = const 3
    bounds_check v7, v8
    v9: i32 = array_load v5, v7

    // Return sum 1+2+3 = 6
    v10: i32 = add v1, v2
    v11: i32 = add v10, v3
    ret v11
}
