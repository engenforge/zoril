// expected exit code: 0
// 16_async.zil: Exercises async opcodes

f1: i32 main() {
  @b0:
    v1: u64 = const 32
    v2: async_context = async_setup v1
    // to_submit and min_complete are immediates, not values
    v5: i64 = async_enter v2, 0, 0
    async_close v2
    v6: i32 = const 0
    ret v6
}
