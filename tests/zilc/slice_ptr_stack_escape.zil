// EXPECT: region escape: returning a pointer to local stack storage
// zilc runs the ZIL verifier, rejecting a function that returns slice_ptr of a slice over local stack storage.
f0: Ptr<i32, 'local> leak() {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: i32 = const 42
    store v1, v2
    v3: i64 = const 1
    v4: Ptr<i32, 'local> = cast v1
    v5: Slice<i32, 'local> = slice_construct v4, v3
    v6: Ptr<i32, 'local> = slice_ptr v5
    ret v6
}

f1: i32 main() {
  @b0:
    v1: Ptr<i32, 'local> = call f0()
    v2: i32 = load v1
    ret v2
}
