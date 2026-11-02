use os;

export fn main() void = {
    let a: [4096]int = [0...];
    for (let iter = 0; iter < 500000; iter += 1) {
        for (let i = 0z; i < 4096z; i += 1) {
            a[i] += 1;
        };
    };
    if (a[0] != 500000) os::exit(1);
};
