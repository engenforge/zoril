// EXPECT: region escape: returning a pointer to local stack storage
// zilc runs the ZIL verifier, rejecting a function that returns a pointer to local stack storage.
f0: Ptr<i32, 'local> leak() {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: i32 = const 42
    store v1, v2
    v3: Ptr<i32, 'local> = cast v1
    ret v3
}

f1: i32 main() {
  @b0:
    v1: Ptr<i32, 'local> = call f0()
    v2: i32 = load v1
    ret v2
}
