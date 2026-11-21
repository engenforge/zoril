// EXPECT: region escape: returning a pointer to local stack storage
f0: Ptr<i32, 'local> helper(v0: bool) {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: Ptr<i32, 'local> = borrow v1
    v3: Ptr<i32, 'local> = borrow v1
    branch v0, @b1, @b2
  @b1:
    jump @b3
  @b2:
    jump @b3
  @b3:
    v4: Ptr<i32, 'local> = phi [@b1: v2, @b2: v3]
    ret v4
}

f1: i32 main() {
  @b0:
    v1: i32 = const 0
    ret v1
}
