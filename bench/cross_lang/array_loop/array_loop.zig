pub fn main() u8 {
    var a: [4096]i32 = [_]i32{0} ** 4096;
    var iter: usize = 0;
    while (iter < 500000) : (iter += 1) {
        var i: usize = 0;
        while (i < 4096) : (i += 1) {
            a[i] += 1;
        }
    }
    return if (a[0] == 500000) 0 else 1;
}
