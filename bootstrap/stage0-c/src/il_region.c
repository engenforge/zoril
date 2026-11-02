#include "il_region.h"
#include "il_cfg.h"
#include "il_type.h"
#include "il_ownership.h"
#include "string_table.h"
#include <string.h>
#include <stdlib.h>

bool il_region_outlives(uint32_t a_id, uint32_t b_id) {
    if (a_id == b_id) return true;
    if (a_id == REGION_STATIC) return true;
    if (a_id == REGION_HEAP) return true;
    // Any SSA region (a borrow of a specific local) outlives the general 'local' region 
    // when used as a constraint (e.g. for function parameters).
    if (is_ssa_region(a_id) && b_id == REGION_LOCAL) return true;
    // REGION_LOCAL (caller's stack) outlives parameter regions (callee's view of arguments)
    if (a_id == REGION_LOCAL && is_ssa_region(b_id)) return true;
    return false;
}

const char* il_region_name(const struct ILModule* mod, uint32_t id) {
    if (id == REGION_STATIC) return "static";
    if (id == REGION_LOCAL) return "local";
    if (id == REGION_HEAP) return "heap";
    if (mod && mod->region_table) {
        return string_table_lookup(mod->region_table, id);
    }
    return NULL;
}

uint32_t il_region_parse(struct StringTable* table, const char* name) {
    if (table) {
        return string_table_intern(table, name);
    } else {
        if (strcmp(name, "static") == 0) return REGION_STATIC;
        if (strcmp(name, "local") == 0) return REGION_LOCAL;
        if (strcmp(name, "heap") == 0) return REGION_HEAP;
        
        // Handle numeric IDs directly (e.g. from IL parsing without module table)
        if (name[0] >= '0' && name[0] <= '9') {
            uint32_t rid = (uint32_t)atoi(name);
            if (rid == 0) return REGION_STATIC;
            return rid;
        }
        return REGION_LOCAL; // Default
    }
}

bool il_region_is_valid(const struct OwnershipState* state, const ILType* type) {
    if (!type || !state) return true;
    if (type->kind == IL_TY_PTR) {
        uint32_t rid = type->as.ptr.region_id;
        if (is_ssa_region(rid) && rid < state->count) {
            if (ownership_get(state, rid) == VAL_MOVED) {
                return false;
            }
        }
        return il_region_is_valid(state, type->as.ptr.pointee);
    }
    if (type->kind == IL_TY_BOX) {
        uint32_t rid = type->as.box.region_id;
        if (is_ssa_region(rid) && rid < state->count) {
            if (ownership_get(state, rid) == VAL_MOVED) {
                return false;
            }
        }
        return il_region_is_valid(state, type->as.box.pointee);
    }
    if (type->kind == IL_TY_SLICE) {
        uint32_t rid = type->as.slice.region_id;
        if (is_ssa_region(rid) && rid < state->count) {
            if (ownership_get(state, rid) == VAL_MOVED) {
                return false;
            }
        }
        return il_region_is_valid(state, type->as.slice.element);
    }
    if (type->kind == IL_TY_ARRAY) return il_region_is_valid(state, type->as.array.element);
    return true;
}

bool is_ssa_region(uint32_t rid) {
    return rid != 0 && rid < 0xFFFFFFF0;
}
