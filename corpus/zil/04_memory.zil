// expected exit code: 42
// 04_memory.zil: Exercises alloc, load, and store opcodes

f1: i32 main() {
  @b0:
    v1: PtrMut<i32, 'local> = alloc 'local, i32
    v2: i32 = const 42
    v3: unit = store v1, v2
    v4: i32 = load v1
    ret v4
}
