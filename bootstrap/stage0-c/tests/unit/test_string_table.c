#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "string_table.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_string_interning(void) {
    StringTable* st = string_table_create();
    ASSERT(st != NULL, "Failed to create string table");

    uint32_t s1 = string_table_intern(st, "hello");
    uint32_t s2 = string_table_intern(st, "world");
    uint32_t s1_again = string_table_intern(st, "hello");

    ASSERT(s1 != s2, "Unique strings should have different IDs");
    ASSERT(s1 == s1_again, "Identical strings should have the same ID");

    ASSERT(strcmp(string_table_lookup(st, s1), "hello") == 0, "Resolution failed for hello");
    ASSERT(strcmp(string_table_lookup(st, s2), "world") == 0, "Resolution failed for world");

    string_table_free(st);
    return true;
}

static bool test_string_table_growth(void) {
    StringTable* st = string_table_create();
    
    // Default capacity is usually small (e.g. 16 or 32)
    // Let's add 500 strings to force growth
    for (int i = 0; i < 500; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "string_%d", i);
        string_table_intern(st, buf);
    }
    
    ASSERT(st->count == 500, "Count should be 500");
    uint32_t s = string_table_intern(st, "string_250");
    ASSERT(strcmp(string_table_lookup(st, s), "string_250") == 0, "Lookup failed after growth");

    string_table_free(st);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_string_interning);
    RUN_TEST(test_string_table_growth);
    printf("[%2d/%2d] String table and interning\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
