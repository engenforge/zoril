#include "arena.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "il_type.h"

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    Arena arena;
    arena_init(&arena, 1024);
    
    // Test basic allocation
    void* p1 = arena_alloc(&arena, 10, 8);
    assert(p1 != NULL);
    memset(p1, 0xAA, 10);
    
    // Test alignment
    void* p2 = arena_alloc(&arena, 10, 16);
    assert(p2 != NULL);
    assert(((uintptr_t)p2 % 16) == 0);
    memset(p2, 0xBB, 10);
    
    // Test multiple blocks
    void* last_p = NULL;
    for (int i = 0; i < 100; i++) {
        last_p = arena_alloc(&arena, 100, 8);
        assert(last_p != NULL);
        memset(last_p, (uint8_t)i, 100);
    }
    
    // Test reset
    arena_reset(&arena);
    void* p3 = arena_alloc(&arena, 10, 8);
    assert(p3 == p1); // Should reuse first block start
    
    arena_destroy(&arena);
    printf("[PASS] Arena unit test\n");
    il_ctx_destroy(&ctx);
    return 0;
}
