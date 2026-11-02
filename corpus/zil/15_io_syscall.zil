// expected exit code: 0
// 15_io_syscall.zil: Exercises syscalls

f1: i32 main() {
  @b0:
    v1: i64 = const 1 // write
    v2: i64 = const 1 // stdout
    v3: Slice<u8> = string_const "IL Syscall\n"
    v4: Ptr<u8, 'static> = bitcast v3
    v5: u64 = slice_len v3
    v6: i64 = syscall v1, v2, v4, v5
    v7: i32 = const 0
    ret v7
}
