// EXPECT: region escape: storing a pointer to local stack storage into a global
global g0: PtrMut<i32, 'static> = { 0, 0, 0, 0, 0, 0, 0, 0 }

f1: i32 main() {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: PtrMut<PtrMut<i32, 'local>, 'static> = global_addr 0
    store v2, v1
    v3: i32 = const 0
    ret v3
}
