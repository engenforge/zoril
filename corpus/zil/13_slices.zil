// expected exit code: 10
// 13_slices.zil: Exercises slice construction and access

f1: i32 main() {
  @b0:
    v1: u64 = const 10
    v2: BoxMut<[i32; 10]> = alloc 'heap, [i32; 10]
    v3: SliceMut<i32, 'heap> = slice_construct v2, v1
    v4: u64 = slice_len v3
    v5: i32 = bitcast v4
    drop v2
    ret v5
}
