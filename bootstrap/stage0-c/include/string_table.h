#ifndef STRING_TABLE_H
#define STRING_TABLE_H

#include <stdint.h>
#include <stddef.h>

typedef struct StringTable {
    char** strings;
    uint32_t count;
    uint32_t capacity;
} StringTable;


StringTable* string_table_create(void);
void string_table_free(StringTable* table);

// Returns a unique ID for the string. If the string is already in the table, 
// the existing ID is returned. Otherwise, it is added and a new ID is assigned.
uint32_t string_table_intern(StringTable* table, const char* str);

// Resolves a string ID back to its original string. Returns NULL if ID is invalid.
const char* string_table_lookup(const StringTable* table, uint32_t id);

#endif
