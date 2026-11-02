#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include "version.h"
#include "il_read.h"
#include "il_cfg.h"
#include "il_print.h"
#include "verifier.h"
#include "qbe_emit.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "diagnostics.h"
#include "il_pass.h"

static void print_usage(FILE* out, const char* prog) {
    fprintf(out, "Usage: %s [options] <input.[zrl|zil]>\n", prog);
    fprintf(out, "Options:\n");
    fprintf(out, "  -o <file>      Output file (default: a.out, or stdout if --emit-ir)\n");
    fprintf(out, "  -I <path>      Add directory to import search path\n");
    fprintf(out, "  --stdlib <dir> Specify directory containing runtime.c and sys_linux_x86_64.s\n");
    fprintf(out, "  -h, --help     Display this help message and exit\n");
    fprintf(out, "  --version      Display version information and exit\n");
    fprintf(out, "  --verify       Verify only, do not emit IR or compile\n");
    fprintf(out, "  --no-verify    Skip verification (stage0-C is a build tool, not the shipped checker)\n");
    fprintf(out, "  --emit-ir      Emit QBE IR to output instead of compiling to executable\n");
    fprintf(out, "  --print-il     Print Zoril IL to stdout\n");
    fprintf(out, "  --il           Force input to be treated as IL (.zil)\n");
    fprintf(out, "  --surface      Force input to be treated as Surface syntax (.zrl)\n");
    fprintf(out, "  --json-errors  Output errors in JSON format\n");
    fprintf(out, "  --keep-ssa     Keep intermediate .ssa file after compilation\n");
    fprintf(out, "  --release      Enable release mode (wrapping arithmetic)\n");
}

static void print_version(void) {
    printf("zoril-c version %s (%s, %s)\n", VERSION, GIT_HASH, BUILD_DATE);
}

static char** loaded_files = NULL;
static uint32_t loaded_file_count = 0;

static char** include_paths = NULL;
static uint32_t include_path_count = 0;
static const char* stdlib_path = NULL;

static void add_include_path(const char* path) {
    char** new_paths = realloc(include_paths, (include_path_count + 1) * sizeof(char*));
    if (!new_paths) {
        perror("realloc");
        exit(1);
    }
    include_paths = new_paths;
    include_paths[include_path_count++] = strdup(path);
}

static bool is_file_loaded(const char* path) {
    char* real = realpath(path, NULL);
    const char* target = real ? real : path;
    for (uint32_t i = 0; i < loaded_file_count; i++) {
        if (strcmp(loaded_files[i], target) == 0) {
            if (real) free(real);
            return true;
        }
    }
    if (real) free(real);
    return false;
}

static void add_loaded_file(const char* path) {
    char* real = realpath(path, NULL);
    const char* target = real ? real : path;
    char** new_loaded_files = realloc(loaded_files, (loaded_file_count + 1) * sizeof(char*));
    if (!new_loaded_files) {
        perror("realloc");
        if (real) free(real);
        exit(1);
    }
    loaded_files = new_loaded_files;
    loaded_files[loaded_file_count++] = strdup(target);
    if (real) free(real);
}

static SurfaceModule* load_module_recursive(const char* input_path, DiagnosticReport* report) {
    if (is_file_loaded(input_path)) return NULL;
    add_loaded_file(input_path);
    const char* persistent_path = loaded_files[loaded_file_count - 1];

    FILE* f = fopen(persistent_path, "rb");
    if (!f) {
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return NULL;
    }
    fseek(f, 0, SEEK_SET);

    char* buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fclose(f);
        return NULL;
    }

    if (fread(buffer, 1, (size_t)size, f) != (size_t)size) {
        free(buffer);
        fclose(f);
        return NULL;
    }
    buffer[size] = '\0';
    fclose(f);

    SurfaceModule* smod = surface_parse_module(buffer, persistent_path, report);
    if (report) diag_add_source(report, persistent_path, buffer);
    else free(buffer);
    if (!smod) return NULL;

    // Resolve imports relative to current file
    char path_copy[1024];
    strncpy(path_copy, persistent_path, sizeof(path_copy) - 1);
    path_copy[sizeof(path_copy) - 1] = '\0';
    const char* dir = dirname(path_copy);

    // Recursively load imports
    uint32_t i = 0;
    while (i < smod->import_count) {
        char import_path[1024];
        bool found = false;

        if (smod->imports[i]->path[0] == '/') {
            snprintf(import_path, sizeof(import_path), "%s", smod->imports[i]->path);
            found = true;
        } else {
            // Try relative to current file
            snprintf(import_path, sizeof(import_path), "%s/%s", dir, smod->imports[i]->path);
            if (strstr(import_path, ".zrl") == NULL) {
                 strncat(import_path, ".zrl", sizeof(import_path) - strlen(import_path) - 1);
            }
            if (access(import_path, F_OK) == 0) {
                found = true;
            } else {
                // Try each include path
                for (uint32_t j = 0; j < include_path_count; j++) {
                    snprintf(import_path, sizeof(import_path), "%s/%s", include_paths[j], smod->imports[i]->path);
                    if (strstr(import_path, ".zrl") == NULL) {
                         strncat(import_path, ".zrl", sizeof(import_path) - strlen(import_path) - 1);
                    }
                    if (access(import_path, F_OK) == 0) {
                        found = true;
                        break;
                    }
                }
            }
        }

        if (!found && smod->imports[i]->path[0] != '/') {
            // Revert to relative path for the error message/failure if not found anywhere
            snprintf(import_path, sizeof(import_path), "%s/%s", dir, smod->imports[i]->path);
            if (strstr(import_path, ".zrl") == NULL) {
                strncat(import_path, ".zrl", sizeof(import_path) - strlen(import_path) - 1);
            }
        }

        SurfaceModule* imported = load_module_recursive(import_path, report);
        if (imported) {
            smod->imports[i]->resolved_path = strdup(import_path);
            surface_mod_merge(smod, imported);
            surface_mod_free(imported);
        }
 else {
            // It might already be loaded or failed. If it failed, report is updated.
        }
        i++;
    }

    return smod;
}

int main(int argc, char** argv) {
    const char* input_path = NULL;
    const char* output_path = NULL;
    bool verify_only = false;
    bool no_verify   = false;
    bool emit_ir = false;
    bool print_il = false;
    bool force_il = false;
    bool force_surface = false;
    bool json_errors = false;
    bool keep_ssa = false;
    bool release_mode = false;
    VerificationResult vres = { .is_safe = true, .errors = NULL, .error_count = 0, .error_capacity = 0 };

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_path = argv[++i];
        } else if (strcmp(argv[i], "-I") == 0 && i + 1 < argc) {
            add_include_path(argv[++i]);
        } else if (strcmp(argv[i], "--stdlib") == 0 && i + 1 < argc) {
            stdlib_path = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(stdout, argv[0]);
            return 0;
        } else if (strcmp(argv[i], "--version") == 0) {
            print_version();
            return 0;
        } else if (strcmp(argv[i], "--verify") == 0) {
            verify_only = true;
        } else if (strcmp(argv[i], "--no-verify") == 0) {
            no_verify = true;
        } else if (strcmp(argv[i], "--json-errors") == 0) {
            json_errors = true;
        } else if (strcmp(argv[i], "--emit-ir") == 0) {
            emit_ir = true;
        } else if (strcmp(argv[i], "--print-il") == 0) {
            print_il = true;
        } else if (strcmp(argv[i], "--il") == 0) {
            force_il = true;
        } else if (strcmp(argv[i], "--surface") == 0) {
            force_surface = true;
        } else if (strcmp(argv[i], "--keep-ssa") == 0) {
            keep_ssa = true;
        } else if (strcmp(argv[i], "--release") == 0) {
            release_mode = true;
        } else if (argv[i][0] == '-') {
            print_usage(stderr, argv[0]);
            return 1;
        } else {
            input_path = argv[i];
        }
    }

    if (!input_path) {
        print_usage(stderr, argv[0]);
        return 1;
    }

    if (verify_only && no_verify) {
        fprintf(stderr, "--verify and --no-verify are mutually exclusive.\n");
        return 2;
    }

    bool is_surface = false;
    if (force_surface) is_surface = true;
    else if (force_il) is_surface = false;
    else {
        const char* ext = strrchr(input_path, '.');
        if (ext && strcmp(ext, ".zrl") == 0) is_surface = true;
    }

    ILModule* mod = NULL;
    SurfaceModule* smod = NULL;
    DiagnosticReport* report = diag_report_create();
    ILContext il_ctx;
    int exit_code = 0;
    il_ctx_init(&il_ctx);
    char tmp_out[4096] = {0};
    char ssa_file[4096] = {0};
    char s_file[4096] = {0};
    char obj_file[4096] = {0};

    if (is_surface) {
        fprintf(stderr, "Parsing surface module(s)...\n");
        smod = load_module_recursive(input_path, report);
        if (!smod || report->count > 0) {
            fprintf(stderr, "Error: Parsing failed.\n");
            exit_code = 1;
            goto cleanup;
        }
        fprintf(stderr, "Lowering to IL...\n");
        mod = surface_lower_module(smod, report, release_mode);
        surface_mod_free(smod);
        smod = NULL;
    } else {
        FILE* f = fopen(input_path, "rb");
        if (!f) { perror("fopen"); exit_code = 1; goto cleanup; }
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        if (size < 0) { perror("ftell"); fclose(f); exit_code = 1; goto cleanup; }
        fseek(f, 0, SEEK_SET);
        char* buffer = malloc((size_t)size + 1);
        if (!buffer) { perror("malloc"); fclose(f); exit_code = 1; goto cleanup; }
        if (fread(buffer, 1, (size_t)size, f) != (size_t)size && size > 0) {
            perror("fread");
            free(buffer);
            fclose(f);
            exit_code = 1;
            goto cleanup;
        }
        buffer[size] = '\0';
        fclose(f);

        const char* end;
        fprintf(stderr, "Reading IL module...\n");
        mod = il_read_module(buffer, &end);
        free(buffer);
    }

    if (!mod) {
        fprintf(stderr, "Error obtaining Zoril IL module.\n");
        exit_code = 1;
        goto cleanup;
    }

    if (report->count > 0) {
        exit_code = 1;
        goto cleanup;
    }

    fprintf(stderr, "Read module with %u functions.\n", mod->function_count);
    fflush(stderr);

    // 1. Fundamental Passes: Populate types and add auto-drops.
    // These are required for correctness of the lowering and for the verifier to pass.
    if (mod->function_count > 0) {
        for (uint32_t i = 0; i < mod->function_count; i++) {
            il_func_populate_types(mod, mod->functions[i]);
            il_func_auto_drop(mod, mod->functions[i]);
        }
    }

    if (print_il) {
        il_mod_print(mod, stdout);
        exit_code = 0;
        goto cleanup;
    }

    // 2. Verification: ensure the module is safe before optimization or emission.
    //
    // --no-verify exists because stage0-C's verifier is not the checker this project ships, and it
    // is on its way out: the cold-start seed drops verifier.c entirely and relies on the built
    // compiler re-checking its own source with the shipped verifier. Until then the flag lets a
    // caller use stage0-C as a build tool without being blocked by an unmaintained checker.
    if (no_verify) {
        fprintf(stderr, "Verification skipped (--no-verify).\n");
        fflush(stderr);
        goto verify_done;   // vres is already { .is_safe = true }
    }
    fprintf(stderr, "Verifying module...\n");
    fflush(stderr);
    vres = verify_module(mod);
    fprintf(stderr, "Verification complete.\n");
    fflush(stderr);
    if (!vres.is_safe) {
        if (!json_errors) fprintf(stderr, "Verification failed:\n");
        for (uint32_t i = 0; i < vres.error_count; i++) {
            const char* file = vres.errors[i].file_path;
            const char* source = diag_get_source_for_path(report, file);
            uint32_t offset = diag_calculate_offset(source, vres.errors[i].line, vres.errors[i].col);
            SourceLocation loc = {
                .file_path = file,
                .source = source,
                .line = vres.errors[i].line,
                .col = vres.errors[i].col,
                .offset = offset,
                .length = 1
            };
            diag_emit(report, DIAG_ERROR, loc, "%s", vres.errors[i].message);
        }
        exit_code = 1;
        goto cleanup;
    }

verify_done:
    if (verify_only) {
        fprintf(stderr, "Verification successful.\n");
        exit_code = 0;
        goto cleanup;
    }

    // 3. Optimization/Analysis Passes: Run after verification.
    if (mod->function_count > 0) {
        fprintf(stderr, "Running optimization passes...\n");
        fflush(stderr);
        for (uint32_t i = 0; i < mod->function_count; i++) {
            fprintf(stderr, "  [%u/%u] %s...\n", i + 1, mod->function_count, mod->functions[i]->name);
            fflush(stderr);
            il_pass_const_fold(mod, mod->functions[i]);
            il_pass_must_use_check(mod, mod->functions[i], report);
            il_pass_arena_capacity_check(mod, mod->functions[i], report);
        }
        fprintf(stderr, "Optimization passes complete.\n");
        fflush(stderr);
    }

    if (print_il) {
        il_mod_print(mod, stdout);
        exit_code = 0;
        goto cleanup;
    }

    if (emit_ir) {
        FILE* out = stdout;
        if (output_path) {
            out = fopen(output_path, "w");
            if (!out) {
                perror("fopen output");
                exit_code = 1;
                goto cleanup;
            }
        }
        qbe_emit_module(mod, out);
        if (output_path) fclose(out);
    } else {
        const char* final_out = output_path ? output_path : "a.out";
        snprintf(tmp_out, sizeof(tmp_out), "%s.tmp", final_out);
        snprintf(ssa_file, sizeof(ssa_file), "%s.ssa", final_out);
        snprintf(s_file, sizeof(s_file), "%s.s", final_out);
        snprintf(obj_file, sizeof(obj_file), "%s.o", final_out);

        FILE* out = fopen(ssa_file, "w");
        if (!out) {
            perror("fopen temp ssa");
            exit_code = 1;
            goto cleanup;
        }
        qbe_emit_module(mod, out);
        fclose(out);

        char cmd[8192];
        const char* backend_bin = getenv("BACKEND_BIN");
        if (!backend_bin || backend_bin[0] == '\0') backend_bin = "qbe";
        printf("Compiling %s to assembly...\n", ssa_file);
        snprintf(cmd, sizeof(cmd), "%s -o %s %s", backend_bin, s_file, ssa_file);
        if (system(cmd) != 0) {
            fprintf(stderr, "Error: %s compilation failed\n", backend_bin);
            exit_code = 1;
            goto cleanup;
        }

        printf("Assembling and linking to %s...\n", final_out);
        
        char sys_path[4096];
        char runtime_path[4096];
        char exe_path[4096];

        bool stdlib_found = false;
        bool use_asm_runtime = false;

        if (stdlib_path) {
            snprintf(runtime_path, sizeof(runtime_path), "%s/runtime.c", stdlib_path);
            if (access(runtime_path, F_OK) == 0) {
                stdlib_found = true;
                snprintf(sys_path, sizeof(sys_path), "%s/sys_linux_x86_64.s", stdlib_path);
            } else {
                snprintf(runtime_path, sizeof(runtime_path), "%s/runtime.s", stdlib_path);
                if (access(runtime_path, F_OK) == 0) {
                    stdlib_found = true;
                    use_asm_runtime = true;
                    sys_path[0] = '\0';
                }
            }
        }

        if (!stdlib_found && realpath(argv[0], exe_path)) {
            char* dir = dirname(exe_path);
            
            // Try runtime.s first (assembly runtime linked via as + ld)
            snprintf(runtime_path, sizeof(runtime_path), "%s/lib/rt/runtime.s", dir);
            if (access(runtime_path, F_OK) == 0) {
                stdlib_found = true;
                use_asm_runtime = true;
                sys_path[0] = '\0';
            } else {
                snprintf(runtime_path, sizeof(runtime_path), "%s/../lib/rt/runtime.s", dir);
                if (access(runtime_path, F_OK) == 0) {
                    stdlib_found = true;
                    use_asm_runtime = true;
                    sys_path[0] = '\0';
                }
            }

            // If not found, try runtime.c
            if (!stdlib_found) {
                snprintf(runtime_path, sizeof(runtime_path), "%s/lib/rt/runtime.c", dir);
                if (access(runtime_path, F_OK) == 0) {
                    stdlib_found = true;
                    snprintf(sys_path, sizeof(sys_path), "%s/lib/rt/sys_linux_x86_64.s", dir);
                } else {
                    snprintf(runtime_path, sizeof(runtime_path), "%s/../lib/rt/runtime.c", dir);
                    if (access(runtime_path, F_OK) == 0) {
                        stdlib_found = true;
                        snprintf(sys_path, sizeof(sys_path), "%s/../lib/rt/sys_linux_x86_64.s", dir);
                    }
                }
            }
        }
        
        if (!stdlib_found) {
            // Last ditch effort: current directory or defaults
            if (access("lib/rt/runtime.s", F_OK) == 0) {
                snprintf(runtime_path, sizeof(runtime_path), "lib/rt/runtime.s");
                use_asm_runtime = true;
                sys_path[0] = '\0';
            } else if (access("runtime.s", F_OK) == 0) {
                snprintf(runtime_path, sizeof(runtime_path), "runtime.s");
                use_asm_runtime = true;
                sys_path[0] = '\0';
            } else if (access("lib/rt/runtime.c", F_OK) == 0) {
                snprintf(runtime_path, sizeof(runtime_path), "lib/rt/runtime.c");
                snprintf(sys_path, sizeof(sys_path), "lib/rt/sys_linux_x86_64.s");
            } else if (access("runtime.c", F_OK) == 0) {
                snprintf(runtime_path, sizeof(runtime_path), "runtime.c");
                snprintf(sys_path, sizeof(sys_path), "sys_linux_x86_64.s");
            }
        }

        if (use_asm_runtime) {
            const char* as_bin = getenv("ASSEMBLER_BIN");
            if (!as_bin || as_bin[0] == '\0') as_bin = "as";
            const char* ld_bin = getenv("LINKER_BIN");
            if (!ld_bin || ld_bin[0] == '\0') ld_bin = "ld";

            // 1. Assemble the program
            snprintf(cmd, sizeof(cmd), "%s -o %s %s", as_bin, obj_file, s_file);
            if (system(cmd) != 0) {
                fprintf(stderr, "Error: Assembler (%s) failed\n", as_bin);
                remove(tmp_out);
                exit_code = 1;
                goto cleanup;
            }

            // 2. Assemble the runtime (.s)
            char rt_obj[4096];
            snprintf(rt_obj, sizeof(rt_obj), "%s.rt.o", final_out);
            snprintf(cmd, sizeof(cmd), "%s -o %s %s", as_bin, rt_obj, runtime_path);
            if (system(cmd) != 0) {
                fprintf(stderr, "Error: Failed to assemble runtime\n");
                remove(tmp_out);
                exit_code = 1;
                goto cleanup;
            }

            // 3. Link with ld
            snprintf(cmd, sizeof(cmd), "%s -o %s %s %s", ld_bin, tmp_out, obj_file, rt_obj);
            if (system(cmd) != 0) {
                fprintf(stderr, "Error: Linker (%s) failed\n", ld_bin);
                remove(tmp_out);
                exit_code = 1;
                goto cleanup;
            }

            // Cleanup objects
            remove(obj_file);
            remove(rt_obj);
        } else {
            const char* link_cc = getenv("LINK_CC");
            if (!link_cc || link_cc[0] == '\0') link_cc = "cc";

            snprintf(cmd, sizeof(cmd), "%s -no-pie -nostdlib -fno-builtin -fno-stack-protector -o %s %s %s %s", link_cc, tmp_out, s_file, runtime_path, sys_path);
            if (system(cmd) != 0) {
                remove(tmp_out);
                fprintf(stderr, "Error: Link driver (%s) failed\n", link_cc);
                exit_code = 1;
                goto cleanup;
            }
        }

        if (!keep_ssa) remove(ssa_file);
        remove(s_file);
        if (rename(tmp_out, final_out) != 0) {
            perror("rename output");
            remove(tmp_out);
            exit_code = 1;
            goto cleanup;
        }
        printf("Successfully built %s\n", final_out);
    }

cleanup:
    if (exit_code != 0) {
        if (tmp_out[0]) remove(tmp_out);
        if (ssa_file[0] && !keep_ssa) remove(ssa_file);
        if (s_file[0]) remove(s_file);
        if (obj_file[0]) remove(obj_file);
    }
    if (report->count > 0 || exit_code != 0) {
        if (json_errors) diag_render_json(report);
        else diag_render_terminal(report);
    }
    verify_result_free(&vres);
    if (smod) surface_mod_free(smod);
    if (mod) il_mod_free(mod);
    il_ctx_destroy(&il_ctx);
    if (report) diag_report_destroy(report);
    for (uint32_t i = 0; i < loaded_file_count; i++) free(loaded_files[i]);
    free(loaded_files);
    for (uint32_t i = 0; i < include_path_count; i++) free(include_paths[i]);
    free(include_paths);
    return exit_code;
}

