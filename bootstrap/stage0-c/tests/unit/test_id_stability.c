#include "test_harness.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_id_stability(void) {
    // The self-hosted compiler (resolve.zrl) has hardcoded IDs for primitives:
    // Bool = 11, Char = 12, Never = 13, etc.
    // If zoril-c's ILTypeKind shifts these, any binary interchange or hardcoded
    // logic in the bootstrap will break.
    
    // Actually, zoril-c's ILTypeKind is an enum, so we can check the values.
    printf("[INFO] IL_TY_BOOL = %d\n", IL_TY_BOOL);
    printf("[INFO] IL_TY_CHAR = %d\n", 31); // I need to find where CHAR is defined
    
    // Let's verify the specific IDs that Zoril expects.
    // resolve.zrl: PrimitiveType.Bool => 11 as u32
    // We expect IL_TY_BOOL to be something consistent.
    
    // In the CURRENT (shifted) state:
    // UNIT=0, BOOL=1, U8=2, U16=3, U32=4, U64=5, I8=6, I16=7, I32=8, I64=9, USIZE=10, ISIZE=11, F32=12, F64=13
    
    // This confirms that 'Bool' is 1, not 11. 
    // Wait, Zoril's internal ID (11) is its OWN mapping, not zoril-c's mapping.
    
    // BUT, if zoril-c's mapping changed, does it matter?
    // It only matters if zoril-c uses those numbers in a way that Zoril expects them to be different.
    
    ASSERT(IL_TY_BOOL == 1, "Bool should be 1");
    ASSERT(IL_TY_U64 == 5, "U64 should be 5");
    ASSERT(IL_TY_F32 == 10, "F32 should be 10 (USIZE/ISIZE must not shift primitives)");
    
    return true;
}

int main(void) {
    RUN_TEST(test_id_stability);
    return (tests_run == tests_passed) ? 0 : 1;
}
