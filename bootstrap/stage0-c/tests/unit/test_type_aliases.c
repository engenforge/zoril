#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "surface_lexer.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "il_pass.h"
#include "qbe_emit.h"
#include "diagnostics.h"
#include "il_type.h"

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    const char* src = 
        "type MyInt = i64;\n"
        "type MyFloat = f64;\n"
        "type PtrInt = *MyInt;\n"
        "\n"
        "struct Point {\n"
        "    x: MyInt,\n"
        "    y: MyInt,\n"
        "}\n"
        "\n"
        "type MyPoint = Point;\n"
        "\n"
        "fn add(a: MyInt, b: MyInt) -> MyInt {\n"
        "    return a + b;\n"
        "}\n"
        "\n"
        "fn main() -> i32 {\n"
        "    let x: MyInt = 40;\n"
        "    let y: MyInt = 2;\n"
        "    let z: MyInt = add(x, y);\n"
        "    \n"
        "    let p: MyPoint = Point { x: x, y: y };\n"
        "    \n"
        "    if z == 42 {\n"
        "        return 0;\n"
        "    } else {\n"
        "        return 1;\n"
        "    }\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test_aliases.zil", report);
    if (!smod) {
        printf("Failed to parse module\n");
        diag_report_destroy(report);
        il_ctx_destroy(&ctx);
        return 1;
    }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) {
        printf("Failed to lower module\n");
        surface_mod_free(smod);
        diag_report_destroy(report);
        il_ctx_destroy(&ctx);
        return 1;
    }

    char il_buf[16384];
    il_print_module(mod, il_buf, sizeof(il_buf));
    printf("%s\n", il_buf);

    // Verify types of some instructions in 'add'
    const ILFunction* add_fn = NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (strcmp(mod->functions[i]->name, "add") == 0) {
            add_fn = mod->functions[i];
            break;
        }
    }

    if (!add_fn) {
        printf("Function 'add' not found\n");
        il_mod_free(mod);
        surface_mod_free(smod);
        il_ctx_destroy(&ctx);
        return 1;
    }

    if (add_fn->return_type->kind != IL_TY_I64) {
        printf("Error: 'add' return type is not i64, got %d\n", (int)add_fn->return_type->kind);
        il_mod_free(mod);
        surface_mod_free(smod);
        il_ctx_destroy(&ctx);
        return 1;
    }

    // Unified ABI: First param is env pointer (Ptr<unit>)
    if (add_fn->param_count < 3 || add_fn->param_types[0]->kind != IL_TY_PTR) {
         printf("Error: 'add' expected 3 params with env first, got %u\n", add_fn->param_count);
         il_mod_free(mod);
         surface_mod_free(smod);
         il_ctx_destroy(&ctx);
         return 1;
    }

    for (uint32_t i = 1; i < add_fn->param_count; i++) {
        if (add_fn->param_types[i]->kind != IL_TY_I64) {
            printf("Error: 'add' param %u type is not i64, got %d\n", i, (int)add_fn->param_types[i]->kind);
            il_mod_free(mod);
            surface_mod_free(smod);
            il_ctx_destroy(&ctx);
            return 1;
        }
    }

    printf("Type aliases resolved correctly!\n");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return 0;
}
