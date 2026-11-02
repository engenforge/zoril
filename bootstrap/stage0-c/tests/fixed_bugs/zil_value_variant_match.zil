// expected exit 42
// Value-form `vR: bool = variant_match vS, Type, K` (ZIL since c66fe15) was misread as the
// terminator form: the type name was parsed as the index, and the absent targets became @b0.
// The verifier also did not accept that bool as an unwrap guard.

type T1: sum { None: unit, Some: i32 }

f1: i32 main() {
  @b0:
    v1: i32 = const 42
    v2: T1 = sum_construct T1, 1, v1
    v3: PtrMut<T1, 'local> = alloc 'local, T1
    v4: unit = store v3, v2
    v5: Ptr<T1, 'local> = bitcast v3
    v8: bool = variant_match v5, T1, 1
    branch v8, @b1, @b2
  @b1:
    v6: i32 = unwrap v5
    ret v6
  @b2:
    v7: i32 = const 0
    ret v7
}
