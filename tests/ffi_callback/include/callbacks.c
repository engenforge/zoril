/* A tiny C library with callbacks; no libc. Linked with rt/runtime.o by test_ffi_callback.sh. */
typedef int (*item_cb)(void *, int);
typedef int (*done_cb)(void *);
struct vtable { item_cb on_item; done_cb on_done; };

int c_for_each(int n, item_cb cb, void *ud) {
    for (int i = 1; i <= n; i++) cb(ud, i);
    return n;
}

int c_run_vtable(const struct vtable *vt, void *ud) {
    for (int i = 1; i <= 3; i++) vt->on_item(ud, i);
    return vt->on_done(ud);
}

int c_reenter(int levels, item_cb cb, void *ud) {
    return cb(ud, levels);
}

/* Small results with garbage in the upper bits of the register, which the C ABI allows: a caller
   must extend them itself. Written in assembly so the compiler cannot return them clean. */
__asm__(".globl c_dirty_u8\nc_dirty_u8:\n  mov $0x1205, %eax\n  ret\n"
        ".globl c_dirty_bool\nc_dirty_bool:\n  mov $0x7700, %eax\n  ret\n"
        ".globl c_dirty_i16\nc_dirty_i16:\n  mov $0x1234FFFE, %eax\n  ret\n");
