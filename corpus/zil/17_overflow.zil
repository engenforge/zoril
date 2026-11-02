// expected exit code: 0
// 17_overflow.zil: Exercises overflow arithmetic opcodes

f1: i32 main() {
  @b0:
    // wrapping_add: u32::MAX + 1 wraps to 0
    v1: u32 = const 4294967295
    v2: u32 = const 1
    v3: u32 = wrapping_add v1, v2

    // wrapping_sub: 0 - 1 wraps to u32::MAX
    v4: u32 = const 0
    v5: u32 = wrapping_sub v4, v2

    // wrapping_mul: 2 * u32::MAX wraps (2 * 4294967295 mod 2^32 = 4294967294)
    v6: u32 = const 2
    v7: u32 = wrapping_mul v5, v6

    // saturating_add: u32::MAX + 1 stays at u32::MAX
    v8: u32 = saturating_add v1, v2

    // checked_add, checked_sub, checked_mul (lowered as wrapping per impl)
    v9: u32 = checked_add v2, v6
    v10: u32 = checked_sub v9, v2
    v11: u32 = checked_mul v6, v6

    v12: i32 = const 0
    ret v12
}
