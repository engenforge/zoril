#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_type.h"

static bool test_trait_parsing(void) {
    const char* src = 
        "trait Drawable {\n"
        "    fn draw(self);\n"
        "}\n"
        "struct Circle { radius: i32 }\n"
        "impl Drawable for Circle {\n"
        "    fn draw(self) {\n"
        "        let x = self.radius;\n"
        "    }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_traits.zil", report);
    
    bool ok = true;
    if (!mod) {
        printf("Failed to parse trait definitions.\n");
        for (uint32_t i=0; i<report->count; i++) printf("%s\n", report->diagnostics[i].message);
        ok = false;
    } else {
        // Check if trait and impl were parsed
        if (mod->trait_count != 1) {
            printf("Expected 1 trait, got %u\n", mod->trait_count);
            ok = false;
        } else if (strcmp(mod->traits[0]->name, "Drawable") != 0) {
            printf("Expected trait Drawable, got %s\n", mod->traits[0]->name);
            ok = false;
        }
        
        if (mod->impl_count != 1) {
            printf("Expected 1 impl, got %u\n", mod->impl_count);
            ok = false;
        } else if (!mod->impls[0]->trait_name || strcmp(mod->impls[0]->trait_name, "Drawable") != 0) {
            printf("Expected impl for Drawable, got %s\n", mod->impls[0]->trait_name ? mod->impls[0]->trait_name : "NULL");
            ok = false;
        }
        
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    if (test_trait_parsing()) {
        printf("[PASS] Trait Parsing\n");
        il_ctx_destroy(&ctx);
        return 0;
    } else {
        printf("[FAIL] Trait Parsing\n");
        il_ctx_destroy(&ctx);
        return 1;
    }
}
