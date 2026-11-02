#ifndef TEST_HARNESS_H
#define TEST_HARNESS_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int tests_run;
extern int tests_passed;

static inline int* test_get_skipped_ptr(void) {
    static int skipped = 0;
    return &skipped;
}

static inline const char** test_get_skip_reason_ptr(void) {
    static const char* reason = NULL;
    return &reason;
}

#define tests_skipped (*test_get_skipped_ptr())
#define test_skip_reason (*test_get_skip_reason_ptr())

#define SKIP(reason) \
    do { \
        test_skip_reason = (reason); \
        return true; \
    } while (0)

#define RUN_TEST(test_fn) \
    do { \
        tests_run++; \
        test_skip_reason = NULL; \
        printf("[RUN ] %s\n", #test_fn); \
        fflush(stdout); \
        if (test_fn()) { \
            if (test_skip_reason) { \
                tests_skipped++; \
                printf("[SKIP] %s (%s)\n", #test_fn, test_skip_reason); \
                fflush(stdout); \
            } else { \
                tests_passed++; \
                const char* quiet = getenv("QUIET"); \
                if (!quiet || strcmp(quiet, "1") != 0) { \
                    printf("[PASS] %s\n", #test_fn); \
                    fflush(stdout); \
                } \
            } \
        } else { \
            printf("[FAIL] %s\n", #test_fn); \
            fflush(stdout); \
        } \
    } while (0)

#define ASSERT(condition, msg) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "[FAIL] %s:%d: %s\n", __FILE__, __LINE__, msg); \
            return false; \
        } \
    } while (0)

#define ABORT_IF_NULL(ptr) \
    do { \
        if (!(ptr)) { \
            fprintf(stderr, "ABORT: %s is NULL at %s:%d\n", #ptr, __FILE__, __LINE__); \
            exit(1); \
        } \
    } while (0)

static inline void test_get_tmp_path(char* buf, size_t size, const char* name) {
#ifdef TEST_TMP_DIR
    snprintf(buf, size, "%s/%d_%s", (char*)TEST_TMP_DIR, (int)getpid(), name);
#else
    snprintf(buf, size, "tmp_%d_%s", (int)getpid(), name);
#endif
}

static inline const char* test_get_backend_bin(void) {
    const char* b = getenv("BACKEND_BIN");
    if (b && b[0] != '\0') return b;
    return "qbe";
}

static inline const char* test_get_assembler_bin(void) {
    const char* a = getenv("ASSEMBLER_BIN");
    if (a && a[0] != '\0') return a;
    return "as";
}

static inline const char* test_get_linker_bin(void) {
    const char* l = getenv("LINKER_BIN");
    if (l && l[0] != '\0') return l;
    return "ld";
}

static inline const char* test_get_cc_bin(void) {
    const char* c = getenv("CC");
    if (c && c[0] != '\0') return c;
    return "cc";
}

static inline const char* test_get_link_cc_bin(void) {
    const char* c = getenv("LINK_CC");
    if (c && c[0] != '\0') return c;
    return "cc";
}

static inline bool test_has_link_cc(void) {
    const char* c = test_get_link_cc_bin();
    char check_cmd[1024];
    snprintf(check_cmd, sizeof(check_cmd), "echo 'int main(void){return 0;}' | %s -x c -fno-stack-protector - -o /dev/null > /dev/null 2>&1", c);
    return system(check_cmd) == 0;
}

static inline bool test_has_backend(void) {
    const char* b = test_get_backend_bin();
    char check_cmd[1024];
    snprintf(check_cmd, sizeof(check_cmd), "command -v %s > /dev/null 2>&1", b);
    return system(check_cmd) == 0;
}

#endif
