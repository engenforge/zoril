fn fib(n: i32) i32 {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

pub fn main() u8 {
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        sum += fib(38);
    }
    return if (sum == 117264507) 0 else 1;
}
