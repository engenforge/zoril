// expected exit code: 0
// 19_fd_io.zil: Exercises fd_open, fd_write, fd_close

f1: i32 main() {
  @b0:
    // Open /dev/null for writing (O_WRONLY = 1, mode = 0); flags and mode are immediates
    v1: Slice<u8> = string_const "/dev/null"
    v2: Ptr<u8, 'static> = bitcast v1
    v5: fd<w> = fd_open v2, 1, 0

    // Write a string to /dev/null
    v6: Slice<u8> = string_const "fd_io test\n"
    v7: Ptr<u8, 'static> = bitcast v6
    v8: u64 = slice_len v6
    v9: i64 = fd_write v5, v7, v8

    fd_close v5

    v10: i32 = const 0
    ret v10
}
