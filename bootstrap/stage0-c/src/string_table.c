#include <stdlib.h>
#include <string.h>
#include "string_table.h"
#include "il_region.h"

StringTable* string_table_create(void) {
    StringTable* table = malloc(sizeof(StringTable));
    if (!table) return NULL;
    table->count = 0;
    table->capacity = 16;
    table->strings = malloc(sizeof(char*) * table->capacity);
    if (!table->strings) {
        free(table);
        return NULL;
    }
    return table;
}

void string_table_free(StringTable* table) {
    if (!table) return;
    for (uint32_t i = 0; i < table->count; i++) {
        free(table->strings[i]);
    }
    free(table->strings);
    free(table);
}

uint32_t string_table_intern(StringTable* table, const char* str) {
    if (!table || !str) return 0;
    
    if (strcmp(str, "static") == 0) return REGION_STATIC;
    if (strcmp(str, "local") == 0) return REGION_LOCAL;
    if (strcmp(str, "heap") == 0) return REGION_HEAP;

    // Check if string is already in the table
    for (uint32_t i = 0; i < table->count; i++) {
        if (table->strings && table->strings[i] && strcmp(table->strings[i], str) == 0) {
            return i + 1; // Return 1-based ID
        }
    }
    
    // Resize if needed
    if (table->count >= table->capacity) {
        uint32_t new_cap = table->capacity == 0 ? 16 : table->capacity * 2;
        char** new_strings = realloc(table->strings, sizeof(char*) * new_cap);
        if (!new_strings) return 0;
        table->strings = new_strings;
        table->capacity = new_cap;
    }
    
    if (!table->strings || table->count >= table->capacity) return 0;

    // Add new string
    char* new_str = strdup(str);
    if (!new_str) return 0;
    table->strings[table->count] = new_str;
    table->count++;
    return table->count;
}

const char* string_table_lookup(const StringTable* table, uint32_t id) {
    if (!table || id == 0 || id > table->count) return NULL;
    return table->strings[id - 1];
}
