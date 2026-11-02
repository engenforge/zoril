#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_type.h"

static bool test_trait_bounds(void) {
    printf("DEBUG: test_trait_bounds running\n");
    const char* src = 
        "trait Drawable {\n"
        "    fn draw(self) -> i32;\n"
        "}\n"
        "struct Circle { radius: i32 }\n"
        "impl Drawable for Circle {\n"
        "    fn draw(self) -> i32 { return self.radius; }\n"
        "}\n"
        "fn do_draw<T: Drawable>(obj: T) -> i32 {\n"
        "    return obj.draw();\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let c = Circle { radius: 10 };\n"
        "    return do_draw(c);\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_trait_bounds.zil", report);
    
    bool ok = true;
    if (!mod) {
        printf("Failed to parse trait bounds.\n");
        for (uint32_t i=0; i<report->count; i++) printf("%s\n", report->diagnostics[i].message);
        ok = false;
    } else {
        ILModule* il_mod = surface_lower_module(mod, NULL, false);
        if (!il_mod) {
            printf("Failed to lower trait bounds\n");
            ok = false;
        } else {
            char buf[16384];
            il_print_module(il_mod, buf, sizeof(buf));
            printf("--- IL OUTPUT ---\n%s\n-----------------\n", buf);
            VerificationResult vres = verify_module(il_mod);
            if (vres.error_count > 0) {
                printf("Verification failed for trait bounds\n");
                for (uint32_t i=0; i<vres.error_count; i++) printf("Error: %s\n", vres.errors[i].message);
                ok = false;
            } else {
                if (!strstr(buf, "do_draw_Circle")) {
                    printf("Expected do_draw_Circle in IL\n");
                    ok = false;
                }
            }
            verify_result_free(&vres);
            il_mod_free(il_mod);
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    if (test_trait_bounds()) {
        printf("[PASS] Trait Bounds\n");
        il_ctx_destroy(&ctx);
        return 0;
    } else {
        printf("[FAIL] Trait Bounds\n");
        il_ctx_destroy(&ctx);
        return 1;
    }
}
