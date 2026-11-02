pub fn is_prime(n: i32) -> bool {
    if n <= 1 { return false; }
    let mut d = 2;
    while d * d <= n {
        if n % d == 0 { return false; }
        d += 1;
    }
    true
}

pub fn count_primes(limit: i32) -> i32 {
    let mut count = 0;
    let mut n = 2;
    while n <= limit {
        if is_prime(n) { count += 1; }
        n += 1;
    }
    count
}
