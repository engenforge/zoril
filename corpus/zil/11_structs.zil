// expected exit code: 42
// 11_structs.zil: Exercises struct field access

type T0: struct { x: i32, y: i64 }

f1: i32 main() {
  @b0:
    v1: PtrMut<T0, 'local> = alloc 'local, T0
    v2: PtrMut<i32, 'local> = field_addr v1, 0
    v3: i32 = const 42
    v4: unit = store v2, v3
    v5: i32 = load v2
    ret v5
}
