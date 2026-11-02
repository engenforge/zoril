// Role: doc header threading test
// Algorithm: constant return
f0: u64 get_one(__env: Ptr<unit, 'local>) {
  @b0:
    v2: Ptr<i32, 'local> = alloc 'local, i32
    v3: Ptr<u64, 'local> = alloc 'local, u64
    jump @entry_1
  @entry_1:
    v1: Ptr<unit, 'local> = param 0
    v4: i32 = const 1
    v5: u64 = cast v4
    ret v5
}
