#include "arena.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void arena_init(Arena* arena, size_t default_block_size) {
    arena->first = NULL;
    arena->last = NULL;
    arena->default_block_size = default_block_size ? default_block_size : 1024 * 1024;
}

static ArenaBlock* alloc_block(size_t size) {
    ArenaBlock* block = malloc(sizeof(ArenaBlock) + size);
    if (!block) {
        fprintf(stderr, "Fatal error: Out of memory in Arena allocator\n");
        exit(1);
    }
    block->next = NULL;
    block->size = size;
    block->used = 0;
    return block;
}

void* arena_alloc(Arena* arena, size_t size, size_t align) {
    if (size == 0) return NULL;
    
    // Ensure 8-byte alignment by default if not specified
    if (align == 0) align = 8;
    
    if (arena->last) {
        size_t padding = (align - (uintptr_t)(arena->last->data + arena->last->used)) % align;
        if (arena->last->used + padding + size <= arena->last->size) {
            void* ptr = arena->last->data + arena->last->used + padding;
            arena->last->used += padding + size;
            return ptr;
        }
    }
    
    // Need a new block
    size_t new_size = arena->default_block_size;
    if (size + align > new_size) {
        new_size = size + align;
    }
    
    ArenaBlock* block = alloc_block(new_size);
    if (arena->last) {
        arena->last->next = block;
    } else {
        arena->first = block;
    }
    arena->last = block;
    
    size_t padding = (align - (uintptr_t)block->data) % align;
    void* ptr = block->data + padding;
    block->used = padding + size;
    return ptr;
}

void* arena_realloc(Arena* arena, void* old_ptr, size_t old_size, size_t new_size, size_t align) {
    if (new_size <= old_size) return old_ptr;
    void* new_ptr = arena_alloc(arena, new_size, align);
    if (old_ptr && old_size > 0) {
        memcpy(new_ptr, old_ptr, old_size);
    }
    return new_ptr;
}

void arena_reset(Arena* arena) {
    ArenaBlock* current = arena->first;
    while (current) {
        current->used = 0;
        current = current->next;
    }
    arena->last = arena->first;
}

void arena_merge(Arena* dest, Arena* src) {
    if (!src->first) return;
    if (!dest->first) {
        dest->first = src->first;
        dest->last = src->last;
    } else {
        dest->last->next = src->first;
        dest->last = src->last;
    }
    src->first = NULL;
    src->last = NULL;
}

void arena_destroy(Arena* arena) {
    ArenaBlock* current = arena->first;
    while (current) {
        ArenaBlock* next = current->next;
        free(current);
        current = next;
    }
    arena->first = NULL;
    arena->last = NULL;
}
