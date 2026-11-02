// expected exit code: 7
// Phase D step 1: the IL text can name a raw pointer, distinct from a reference. `RawPtr` and
// `RawPtrMut` are their own tags in the type system now (src/il_type.zrl), but nothing in the
// lowering builds them yet, so what this pins is the spelling end to end: the parser, the
// verifier's Copy rule, layout, and codegen, where both still lower to QBE's `l`. The two functions
// below are never called; their signatures are the whole test.

f2: RawPtrMut<i32, 'local> keep_raw(p: RawPtrMut<i32, 'local>) {
  @b0:
    ret v1
}
f3: RawPtr<i32, 'local> keep_ref(p: RawPtr<i32, 'local>) {
  @b0:
    ret v1
}
f1: i32 main() {
  @b0:
    v1: i32 = const 7
    ret v1
}
