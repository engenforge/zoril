#!/bin/sh
# scripts/check_runtimes.sh — assert the runtime/linker pairing the build relies on.
#
# build/runtime.o (assembled from rt/runtime.s by host `as`) MUST export `_start`
# so that host `ld` resolves the entry symbol correctly.
#
# In addition, zbuild must enforce runtime pairing safety: passing a foreign or
# mismatched runtime object must be rejected with an explicit diagnostic.
#
# It also compares the four files the runtime exists in (rt/README.md): a symbol added to one
# and missed in another is a link failure in whichever build happens to need it, and one such
# change (adding `zoril_argc`/`zoril_argv`) had to edit all four by hand — the C copy beside the stage0-C
# assembly one failed first, with `undefined reference to zoril_argc`. See "the runtime copies".
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
. "$REPO_ROOT/scripts/lib/layout.sh"

fail=0
note() { echo "[FAIL] $*"; fail=1; }
ok()   { echo "[PASS] $*"; }
skip() { echo "[SKIP] $*"; }

has_start() {
    # `nm` prints `T _start` for a defined text symbol.
    nm "$1" 2>/dev/null | grep -qE '(^| )T _start$'
}

# ── build/runtime.o must export _start (it is linked by host ld) ───────────────
if [ -f build/runtime.o ]; then
    if has_start build/runtime.o; then
        ok "build/runtime.o exports _start (host ld can find the entry)"
    else
        note "build/runtime.o does NOT export _start — a host-ld link will default"
        note "  the entry to 0x401000 and segfault. Rebuild: rm build/runtime.o && make build/runtime.o"
    fi
else
    skip "build/runtime.o not built"
fi

# ── scripts/env.sh must not hand hare a search path that looks set but is empty ─
# Hare reads a set-but-empty HAREPATH as "no search path" and fails with "rt: Module not
# found"; scripts/env.sh used to export "" when there is no Hare checkout, which broke every
# bench hare step on such a host (found 2026-10-10). Sourcing it must leave hare able to build.
if command -v hare >/dev/null 2>&1; then
    if ! command -v as >/dev/null 2>&1 || ! command -v ld >/dev/null 2>&1; then
        skip "as/ld not in PATH — hare cannot build"
    else
        _backend="${BACKEND_BIN:-qbe}"
        _backend_path="$(command -v "$_backend" 2>/dev/null || echo "")"
        if [ -z "$_backend_path" ] && [ -x "$_backend" ]; then
            _backend_path="$_backend"
        fi
        if [ -z "$_backend_path" ]; then
            skip "backend ($_backend) does not resolve — hare cannot build"
        else
            _backend_dir="$(cd "$(dirname "$_backend_path")" 2>/dev/null && pwd)"
            _hc="/tmp/hare-env-check.$$"
            if ( PATH="$_backend_dir:$PATH"
                 . "$REPO_ROOT/scripts/env.sh" >/dev/null 2>&1; \
                 hare build -o "$_hc" "$REPO_ROOT/bench/cross_lang/fib/fib.ha" >/dev/null 2>&1 ); then
                ok "hare builds a benchmark program with scripts/env.sh sourced"
            else
                note "hare cannot build bench/cross_lang/fib/fib.ha with scripts/env.sh sourced:"
                note "  a set-but-empty HAREPATH reads as 'no search path' to hare (see scripts/env.sh)"
            fi
            rm -f "$_hc"
        fi
    fi
else
    skip "hare not installed (cannot check scripts/env.sh's HAREPATH)"
fi

# ── the runtime copies: four files, one interface ─────────────────────────────
#
#   rt/runtime.s               the canonical source: host `as` builds build/runtime.o from it, and
#                              every program the self-hosted compiler produces links that object
#   $STAGE1_DIR/rt/runtime.s   the frozen twin of it, linked into the stage1 binaries
#   $STAGE0_DIR/lib/rt/runtime.c  the stage0-C runtime and its syscall stubs
#                              ($STAGE0_DIR/lib/rt/sys_linux_x86_64.s), which `zoril-c` prefers
#   $STAGE0_DIR/lib/rt/runtime.s  the same runtime in assembly, for when no runtime.c is found
#
# The rule, stated in prose ("every runtime copy moves together"), is here in the form
# a build can enforce:
#
#   1. the twin is byte-identical to its canonical source;
#   2. the two stage0-C copies export the same text symbols (zoril-c links whichever of the two it
#      finds, so either must serve the same programs);
#   3. every copy exports each name the standard library declares `extern fn` — both compilers
#      compile the same stdlib modules — and each `zoril_*` name the codegen of the compiler that
#      links that copy can emit, read out of that compiler's own string literals;
#   4. the `__zoril_syscall_N` family, which both compilers call, is the same in all four;
#   5. a probe is linked against each copy and run: it calls every name that copy must export, and
#      checks the runtime's interface as C knows it (the arguments `_start` records and the
#      accessors hand back, `memcpy` / `memset` / `memcmp`'s sign, `malloc` / `realloc` / `free`, a
#      syscall stub). Exports and a link are a claim; running it is the measurement.

ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
_as_bin="${ASSEMBLER_BIN%% *}"
LINK_CC="${LINK_CC:-cc}"
_link_cc_bin="${LINK_CC%% *}"
_link_cc_ok=0
if command -v "$_link_cc_bin" >/dev/null 2>&1; then
    if echo 'int main(void){return 0;}' | $LINK_CC -x c -fno-stack-protector - -o /dev/null >/dev/null 2>&1; then
        _link_cc_ok=1
    fi
fi
RT_TMP=""
if command -v "$_as_bin" >/dev/null 2>&1 && command -v nm >/dev/null 2>&1; then
    RT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/zoril-runtimes.XXXXXX") || RT_TMP=""
fi

# text symbols an object defines (global or weak), one per line, sorted
obj_text_syms() {
    nm --defined-only --extern-only "$1" 2>/dev/null | awk '$2 ~ /^[TtWw]$/ { print $3 }' | sort -u
}
# the same for one configuration, whose objects are the words in its argument
cfg_text_syms() { for _o in $1; do obj_text_syms "$_o"; done | sort -u; }
# the `zoril_*` / `__zoril_*` names a compiler tree can emit, out of its string literals
codegen_names() {
    find "$1" \( -name '*.zrl' -o -name '*.c' -o -name '*.h' \) | while read -r _f; do
        grep -hoE '"[^"]*"' "$_f"
    done | grep -oE '(__)?zoril_[a-z0-9_]+' | grep -vx 'zoril_main' | sort -u
}
# every name an `extern fn` declaration in a standard library promises
stdlib_externs() {
    grep -hoE 'extern[[:space:]]+fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$@" 2>/dev/null \
        | sed -E 's/.*fn[[:space:]]+//' | sort -u
}

if [ -z "$RT_TMP" ]; then
    skip "as/nm not installed — cannot compare the runtime copies"
else
    # Assemble each copy once; the symbol files are the whole comparison input.
    built=1
    "$ASSEMBLER_BIN" -o "$RT_TMP/rt.o" rt/runtime.s >> "$RT_TMP/log" 2>&1 || built=0
    "$ASSEMBLER_BIN" -o "$RT_TMP/stage1.o" "$STAGE1_DIR/rt/runtime.s" >> "$RT_TMP/log" 2>&1 || built=0
    "$ASSEMBLER_BIN" -o "$RT_TMP/stage0c-asm.o" "$STAGE0_DIR/lib/rt/runtime.s" >> "$RT_TMP/log" 2>&1 || built=0
    if [ "$_link_cc_ok" -eq 1 ]; then
        "$ASSEMBLER_BIN" -o "$RT_TMP/stage0c-sys.o" "$STAGE0_DIR/lib/rt/sys_linux_x86_64.s" >> "$RT_TMP/log" 2>&1 || built=0
        $LINK_CC -c -fno-stack-protector -fno-builtin -o "$RT_TMP/stage0c-c.o" "$STAGE0_DIR/lib/rt/runtime.c" \
            >> "$RT_TMP/log" 2>&1 || built=0
    fi

    for _c in "rt|$RT_TMP/rt.o" "stage1_rt|$RT_TMP/stage1.o" "stage0c-asm|$RT_TMP/stage0c-asm.o"; do
        cfg_text_syms "${_c#*|}" > "$RT_TMP/syms-${_c%%|*}"
    done
    if [ "$_link_cc_ok" -eq 1 ] && [ "$built" -eq 1 ]; then
        cfg_text_syms "$RT_TMP/stage0c-c.o $RT_TMP/stage0c-sys.o" > "$RT_TMP/syms-stage0c-c"
    fi

    # For each copy: the compiler whose codegen it must serve, and the material a link uses.
    cat > "$RT_TMP/configs" <<EOF
rt|src|rt/runtime.s
stage1_rt|$STAGE1_DIR/src|$STAGE1_DIR/rt/runtime.s
stage0c-asm|$STAGE0_DIR/src|$STAGE0_DIR/lib/rt/runtime.s
EOF
    if [ "$_link_cc_ok" -eq 1 ] && [ "$built" -eq 1 ]; then
        cat >> "$RT_TMP/configs" <<EOF
stage0c-c|$STAGE0_DIR/src|$STAGE0_DIR/lib/rt/runtime.c $STAGE0_DIR/lib/rt/sys_linux_x86_64.s
EOF
    fi

    if [ "$built" -eq 0 ]; then
        note "a runtime copy did not assemble or compile:"
        tail -5 "$RT_TMP/log" | sed 's/^/       /'
    else
        # 1. the frozen twin
        if cmp -s rt/runtime.s "$STAGE1_DIR/rt/runtime.s"; then
            ok "rt/runtime.s and $STAGE1_DIR/rt/runtime.s are byte-identical (the frozen twin)"
        else
            note "$STAGE1_DIR/rt/runtime.s is not byte-identical to rt/runtime.s, its canonical source:"
            diff rt/runtime.s "$STAGE1_DIR/rt/runtime.s" | head -12 | sed 's/^/       /'
            echo "       the stage1 binaries link it, so keep it a copy: cp rt/runtime.s $STAGE1_DIR/rt/runtime.s"
            echo "       a hand edit inside $STAGE1_DIR is a backport; record it in doc/bootstrap/two_stage.md §3"
        fi

        # 2. the two stage0-C copies are interchangeable
        if [ "$_link_cc_ok" -eq 1 ]; then
            comm -23 "$RT_TMP/syms-stage0c-c" "$RT_TMP/syms-stage0c-asm" > "$RT_TMP/only-c"
            comm -13 "$RT_TMP/syms-stage0c-c" "$RT_TMP/syms-stage0c-asm" > "$RT_TMP/only-asm"
            if [ ! -s "$RT_TMP/only-c" ] && [ ! -s "$RT_TMP/only-asm" ]; then
                ok "the two stage0-C runtimes export the same text symbols ($(wc -l < "$RT_TMP/syms-stage0c-c"))"
            else
                note "the two stage0-C runtimes are not interchangeable (zoril-c links whichever it finds):"
                [ -s "$RT_TMP/only-c" ] && printf '       only in runtime.c + sys_linux_x86_64.s: %s\n' \
                    "$(tr '\n' ' ' < "$RT_TMP/only-c")"
                [ -s "$RT_TMP/only-asm" ] && printf '       only in runtime.s: %s\n' \
                    "$(tr '\n' ' ' < "$RT_TMP/only-asm")"
            fi
        else
            skip "stage0-C runtime.c comparison requires a GCC/Clang-compatible driver (LINK_CC)"
        fi

        # 3./4. what every copy must export
        req_stdlib=$(stdlib_externs stdlib/*.zrl stdlib/*/*.zrl "$STAGE1_DIR"/stdlib/*.zrl)
        while IFS='|' read -r label tree material; do
            # a name ending in `_` names a family (`__zoril_syscall_`), checked for all four below
            req="$req_stdlib $(codegen_names "$tree" | grep -v '_$')"
            missing=""
            for _s in $req; do
                grep -qxF "$_s" "$RT_TMP/syms-$label" || missing="$missing $_s"
            done
            if [ -z "$missing" ]; then
                ok "$label exports every name it must ($(echo $req | wc -w): stdlib externs + $tree codegen)"
            else
                note "$label does not export:$missing"
                echo "       required by the \`extern fn\` declarations of stdlib/*.zrl and by $tree's codegen"
            fi
        done < "$RT_TMP/configs"

        _syscall_labels="rt stage1_rt stage0c-asm"
        [ "$_link_cc_ok" -eq 1 ] && _syscall_labels="$_syscall_labels stage0c-c"
        for _label in $_syscall_labels; do
            grep -E '^__zoril_syscall_[0-9]+$' "$RT_TMP/syms-$_label" > "$RT_TMP/syscall-$_label"
        done
        fam_ok=1
        for _label in $_syscall_labels; do
            [ "$_label" = rt ] && continue
            cmp -s "$RT_TMP/syscall-rt" "$RT_TMP/syscall-$_label" || fam_ok=0
        done
        if [ "$fam_ok" -eq 1 ] && [ -s "$RT_TMP/syscall-rt" ]; then
            ok "every copy defines the same __zoril_syscall_N family ($(wc -l < "$RT_TMP/syscall-rt") stubs)"
        else
            note "the copies disagree about the __zoril_syscall_N family:"
            for _label in $_syscall_labels; do
                printf '       %-11s %s\n' "$_label" \
                    "$(tr '\n' ' ' < "$RT_TMP/syscall-$_label" | sed 's/__zoril_syscall_//g')"
            done
        fi

        # 5. the probe: a program that calls every name a copy must export has to link against it,
        #    and the runtime's interface as C sees it has to behave the same in every copy. Exports
        #    and a link are a claim; running it is the measurement. This found two divergences on
        #    2026-10-13: rt/runtime.s's memcmp returned the opposite sign (and a stale result for
        #    n = 0, since a `repe` with %rcx = 0 leaves the flags alone), and its free unmapped an
        #    address shifted right by three, so every free leaked.
        cat > "$RT_TMP/probe.c" <<'PROBE'
/* The runtime interface as C knows it, run against one copy of the runtime at a time. Returns 0,
   or the code of the first check that failed (90: the one check that needs /proc could not run),
   after writing its reason to stderr with a syscall stub - there is no libc here. */
extern long __zoril_syscall_1(long n, long a1);
extern long __zoril_syscall_2(long n, long a1, long a2);
extern long __zoril_syscall_3(long n, long a1, long a2, long a3);
extern void* memset(void* dest, int c, unsigned long n);
extern void* memcpy(void* dest, const void* src, unsigned long n);
extern int memcmp(const void* a, const void* b, unsigned long n);
extern void* malloc(unsigned long n);
extern void* realloc(void* p, unsigned long n);
extern void free(void* p);
extern int zoril_argc(void);
extern char** zoril_argv(void);

static void reason(const char* msg) {
    unsigned long len = 0;
    while (msg[len] != 0) len++;
    __zoril_syscall_3(1, 2, (long)msg, (long)len);
}

/* the first field of /proc/self/statm: the process's virtual size, in pages */
static long vsize_pages(void) {
    char buf[64];
    long fd = __zoril_syscall_3(2, (long)"/proc/self/statm", 0, 0);
    long n = 0, v = 0, i = 0;
    if (fd < 0) return -1;
    n = __zoril_syscall_3(0, fd, (long)buf, 63);
    __zoril_syscall_1(3, fd);
    if (n <= 0) return -1;
    while (i < n && buf[i] >= '0' && buf[i] <= '9') {
        v = v * 10 + (buf[i] - '0');
        i++;
    }
    return v;
}

int main(int argc, char** argv) {
    unsigned char buf[16];
    unsigned char src[8];
    unsigned char* heap;
    unsigned char* bigger;
    long before, after;
    int i;

    /* 1x: the entry point handed main the kernel's arguments and the accessors hand back the same
       ones - their whole reason for existing */
    if (argc < 3 || argv == 0 || argv[0] == 0 || argv[2] == 0) {
        reason("main did not receive the arguments it was run with\n");
        return 10;
    }
    if (zoril_argc() != argc) {
        reason("zoril_argc does not agree with main's argc\n");
        return 11;
    }
    if (zoril_argv() == 0 || memcmp(zoril_argv(), argv, 8) != 0) {
        reason("zoril_argv does not agree with main's argv\n");
        return 12;
    }

    /* 2x: memset writes the low byte of its value over n bytes and returns dest */
    for (i = 0; i < 16; i++) buf[i] = (unsigned char)i;
    if (memset(buf, 0x1ff, 4) != buf) {
        reason("memset did not return dest\n");
        return 20;
    }
    if (buf[0] != 0xff || buf[3] != 0xff || buf[4] != 4) {
        reason("memset wrote the wrong bytes (the value's low byte only)\n");
        return 21;
    }
    if (memset(buf, 9, 0) != buf) {
        reason("memset with n = 0 did not return dest\n");
        return 22;
    }

    /* 3x: memcpy copies n bytes and returns dest */
    for (i = 0; i < 8; i++) src[i] = (unsigned char)(0x80 + i);
    if (memcpy(buf + 2, src, 8) != buf + 2) {
        reason("memcpy did not return dest\n");
        return 30;
    }
    if (buf[1] != 0xff || buf[2] != 0x80 || buf[9] != 0x87) {
        reason("memcpy copied the wrong bytes\n");
        return 31;
    }
    if (memcpy(buf, src, 0) != buf) {
        reason("memcpy with n = 0 did not return dest\n");
        return 32;
    }

    /* 4x: memcmp's sign, the only thing C defines - including for a byte with the high bit set,
       where a signed comparison and an unsigned one disagree */
    if (memcmp(src, src, 8) != 0) {
        reason("memcmp: equal buffers are not equal\n");
        return 40;
    }
    if (memcmp(src, src, 0) != 0) {
        reason("memcmp with n = 0 is not 0\n");
        return 41;
    }
    if (memcmp(src, src + 1, 7) >= 0) {
        reason("memcmp: a < b did not return a negative value\n");
        return 42;
    }
    if (memcmp(src + 1, src, 7) <= 0) {
        reason("memcmp: a > b did not return a positive value\n");
        return 43;
    }
    buf[0] = 0x80;
    buf[1] = 0x01;
    if (memcmp(buf, buf + 1, 1) <= 0) {
        reason("memcmp: 0x80 against 0x01 is not positive (it compares as unsigned)\n");
        return 44;
    }

    /* 5x: the allocator: fresh memory is zero-filled and contents survive realloc */
    heap = (unsigned char*)malloc(24);
    if (heap == 0) {
        reason("malloc returned 0\n");
        return 50;
    }
    if (heap[23] != 0) {
        reason("malloc returned memory that is not zero-filled\n");
        return 51;
    }
    memset(heap, 7, 24);
    bigger = (unsigned char*)realloc(heap, 48);
    if (bigger == 0) {
        reason("realloc returned 0\n");
        return 52;
    }
    if (bigger[0] != 7 || bigger[23] != 7 || bigger[24] != 0) {
        reason("realloc did not preserve the contents\n");
        return 53;
    }

    /* 6x: free releases the mapping - the one check that needs /proc */
    before = vsize_pages();
    if (before < 0) {
        reason("cannot read /proc/self/statm here\n");
        return 90;
    }
    heap = (unsigned char*)malloc(3 * 4096);
    if (heap == 0) {
        reason("malloc of three pages returned 0\n");
        return 61;
    }
    after = vsize_pages();
    if (after <= before) {
        reason("malloc did not map anything\n");
        return 62;
    }
    free(heap);
    if (vsize_pages() != before) {
        reason("free did not release the mapping (munmap on the wrong address?)\n");
        return 63;
    }
    free(bigger);

    /* 7x: the syscall stubs reach the kernel */
    if (__zoril_syscall_1(39, 0) <= 0) {
        reason("__zoril_syscall_1: getpid returned <= 0\n");
        return 70;
    }

    return 0;
}
PROBE
        if [ "$_link_cc_ok" -eq 1 ]; then
            while IFS='|' read -r label tree material; do
                req="$req_stdlib $(codegen_names "$tree" | grep -v '_$')"
                {
                    echo '.section .text'
                    echo '.globl main'
                    echo 'main:'
                    for _s in $req; do echo "    call $_s"; done
                    echo '    xor %eax, %eax'
                    echo '    ret'
                } > "$RT_TMP/calls-$label.s"
                if $LINK_CC -no-pie -nostdlib -fno-builtin -fno-stack-protector -o "$RT_TMP/calls-$label" \
                        "$RT_TMP/calls-$label.s" $material >> "$RT_TMP/link-$label.log" 2>&1; then
                    ok "$label links a stub that calls all $(echo $req | wc -w) names it must export"
                else
                    note "$label cannot link a stub that calls the runtime symbols the language needs:"
                    grep -E 'undefined reference|rror' "$RT_TMP/link-$label.log" | head -5 | sed 's/^/       /'
                fi

                if $LINK_CC -no-pie -nostdlib -fno-builtin -fno-stack-protector -o "$RT_TMP/run-$label" \
                        "$RT_TMP/probe.c" $material >> "$RT_TMP/run-$label.log" 2>&1; then
                    "$RT_TMP/run-$label" probe-one probe-two > "$RT_TMP/out-$label" 2>&1
                    _rc=$?
                    case "$_rc" in
                        0)  ok "$label runs the runtime probe (argc/argv, byte helpers, allocator, free, a syscall)" ;;
                        90) skip "$label: the runtime probe cannot check free (/proc/self/statm unreadable)" ;;
                        *)  note "$label fails the runtime probe (exit $_rc) after printing:"
                            sed 's/^/       /' "$RT_TMP/out-$label" ;;
                    esac
                else
                    note "$label cannot link the runtime probe:"
                    grep -E 'undefined reference|rror' "$RT_TMP/run-$label.log" | head -5 | sed 's/^/       /'
                fi
            done < "$RT_TMP/configs"
        else
            skip "the runtime probe requires a GCC/Clang-compatible driver (LINK_CC)"
        fi
    fi

    # The hosted runtime (`zoril --hosted`) keeps every name only Zoril defines and drops every name
    # libc owns, so it neither lacks something the codegen calls nor interposes on libc.
    if "$ASSEMBLER_BIN" --defsym HOSTED=1 -o "$RT_TMP/hosted.o" rt/runtime.s >> "$RT_TMP/log" 2>&1; then
        cfg_text_syms "$RT_TMP/hosted.o" > "$RT_TMP/syms-hosted"
        _h_missing=""
        for _s in $(grep -E '^(__)?zoril_' "$RT_TMP/syms-rt" | grep -vxE 'zoril_memcpy|zoril_memset'); do
            grep -qxF "$_s" "$RT_TMP/syms-hosted" || _h_missing="$_h_missing $_s"
        done
        _h_clash=""
        for _s in _start memcpy memset memcmp write abort malloc free realloc fd_open fd_close; do
            grep -qxF "$_s" "$RT_TMP/syms-hosted" && _h_clash="$_h_clash $_s"
        done
        if [ -z "$_h_missing" ] && [ -z "$_h_clash" ] && grep -qxF main "$RT_TMP/syms-hosted"; then
            ok "the hosted runtime defines main and every Zoril-only name, and none of libc's"
        else
            [ -z "$_h_missing" ] || note "the hosted runtime does not export:$_h_missing"
            [ -z "$_h_clash" ] || note "the hosted runtime defines names libc owns:$_h_clash"
            grep -qxF main "$RT_TMP/syms-hosted" || note "the hosted runtime does not define main"
        fi
    else
        note "rt/runtime.s does not assemble with HOSTED=1"
    fi
    rm -rf "$RT_TMP"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: the runtime/linker pairing is not consistent."
    exit 1
fi
echo "PASS: the runtime/linker pairing is consistent."
