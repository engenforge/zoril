// EXPECT: region escape: storing a pointer to local stack storage into a global
global g0: PtrMut<i32, 'local> = { 0, 0, 0, 0, 0, 0, 0, 0 }
global g1: PtrMut<i32, 'local> = { 0, 0, 0, 0, 0, 0, 0, 0 }

f0: i32 main() {
  @b0:
    v0: bool = const 1
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: PtrMut<PtrMut<i32, 'local>, 'static> = global_addr 0
    v3: PtrMut<PtrMut<i32, 'local>, 'static> = global_addr 1
    branch v0, @b1, @b2
  @b1:
    jump @b3
  @b2:
    jump @b3
  @b3:
    v4: PtrMut<PtrMut<i32, 'local>, 'static> = phi [@b1: v2, @b2: v3]
    store v4, v1
    v5: i32 = const 0
    ret v5
}
