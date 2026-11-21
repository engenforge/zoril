// EXPECT: region escape: storing a pointer to local stack storage into a global
global g0: PtrMut<i32, 'local> = { 0, 0, 0, 0, 0, 0, 0, 0 }

f0: i32 main() {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: PtrMut<PtrMut<i32, 'local>, 'static> = global_addr 0
    v3: PtrMut<PtrMut<i32, 'local>, 'local> = region_cast 'local, v2
    store v3, v1
    v4: i32 = const 0
    ret v4
}
