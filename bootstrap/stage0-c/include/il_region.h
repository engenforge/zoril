#ifndef IL_REGION_H
#define IL_REGION_H

#include <stdint.h>
#include <stdbool.h>

// Forward declarations
struct StringTable;
struct ILModule;
struct ILType;
struct OwnershipState;

#define REGION_STATIC 0xFFFFFFF1
#define REGION_LOCAL  0xFFFFFFF2
#define REGION_HEAP   0xFFFFFFF3

// Standard region utilities
bool il_region_outlives(uint32_t a_id, uint32_t b_id);
const char* il_region_name(const struct ILModule* mod, uint32_t id);
uint32_t il_region_parse(struct StringTable* table, const char* name);
bool il_region_is_valid(const struct OwnershipState* state, const struct ILType* type);
bool is_ssa_region(uint32_t rid);

#endif
