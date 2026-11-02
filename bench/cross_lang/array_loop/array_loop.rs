fn main() {
    let mut a: [i32; 4096] = [0; 4096];
    for _ in 0..500000 {
        for i in 0..4096 {
            a[i] += 1;
        }
    }
    if a[0] != 500000 {
        std::process::exit(1);
    }
}
