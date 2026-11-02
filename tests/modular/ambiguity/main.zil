f0: i32 main() {
  @b0:
    v0: i32 = call mod0::calc_x()
    v1: i32 = call mod0_calc::x()
    v2: i32 = const 42
    v3: i32 = sub v0, v2
    v4: i32 = const 99
    v5: i32 = sub v1, v4
    v6: i32 = add v3, v5
    ret v6
}
