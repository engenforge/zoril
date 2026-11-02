#ifndef ARENA_H
#define ARENA_H

#include <stddef.h>
#include <stdint.h>

typedef struct ArenaBlock {
    struct ArenaBlock* next;
    size_t size;
    size_t used;
    uint8_t data[];
} ArenaBlock;

typedef struct {
    ArenaBlock* first;
    ArenaBlock* last;
    size_t default_block_size;
} Arena;

void arena_init(Arena* arena, size_t default_block_size);
void* arena_alloc(Arena* arena, size_t size, size_t align);
void* arena_realloc(Arena* arena, void* old_ptr, size_t old_size, size_t new_size, size_t align);
void arena_reset(Arena* arena);
void arena_merge(Arena* dest, Arena* src);
void arena_destroy(Arena* arena);

#endif
