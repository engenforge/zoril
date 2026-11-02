export fn is_prime(n: int) bool = {
    if (n <= 1) return false;
    let d: int = 2;
    for (d * d <= n; d += 1) {
        if (n % d == 0) return false;
    };
    return true;
};

export fn count_primes(limit: int) int = {
    let count: int = 0;
    for (let n = 2; n <= limit; n += 1) {
        if (is_prime(n)) count += 1;
    };
    return count;
};
