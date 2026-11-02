use os;

fn fib(n: int) int = {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
};

export fn main() void = {
    let sum: int = 0;
    for (let i = 0; i < 3; i += 1) {
        sum += fib(38);
    };
    if (sum != 117264507) os::exit(1);
};
