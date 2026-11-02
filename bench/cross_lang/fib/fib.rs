fn fib(n: i32) -> i32 {
    if n <= 1 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

fn main() {
    let mut sum: i32 = 0;
    for _ in 0..3 {
        sum += fib(38);
    }
    if sum != 117264507 {
        std::process::exit(1);
    }
}
