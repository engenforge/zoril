#include "il_cfg.h"
#include "surface_lower.h"
#include "surface_lower_internal.h"
#include "surface_parser.h"
#include "surface_ast.h"
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "test_harness.h"
#include "il_read.h"
#include "il_type.h"
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>

int tests_run = 0;
int tests_passed = 0;

static bool test_trigger_ice(void) {
    // Capture stderr to verify message
    int pipe_fds[2];
    if (pipe(pipe_fds) == -1) return false;

    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        close(pipe_fds[0]);
        dup2(pipe_fds[1], 2); // Redirect stderr to pipe
        
        DiagnosticReport* report = diag_report_create();
        LowerContext lctx = { .module = il_mod_create(), .report = report, .current_block = il_block_create(1) };
        
        // Trigger ICE via unhandled expression kind
        Expression expr = { .kind = 999 }; // Invalid kind
        lower_expression(&lctx, &expr, NULL, (ILValue){0});
        
        exit(0);
    } else if (pid > 0) {
        // Parent process
        close(pipe_fds[1]);
        char buffer[4096];
        size_t total_read = 0;
        ssize_t n;
        while ((n = read(pipe_fds[0], buffer + total_read, sizeof(buffer) - total_read - 1)) > 0) {
            total_read += (size_t)n;
            if (total_read >= sizeof(buffer) - 1) break;
        }
        buffer[total_read] = '\0';
        close(pipe_fds[0]);

        int status;
        int wait_ret;
        int timeout_ms = 2000;
        while (timeout_ms > 0) {
            wait_ret = waitpid(pid, &status, WNOHANG);
            if (wait_ret != 0) break;
            usleep(10000); // 10ms
            timeout_ms -= 10;
        }

        if (wait_ret == 0) {
            // Timeout - kill the child
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            return false;
        }
        
        bool aborted = WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
        bool message_ok = strstr(buffer, "Internal Compiler Error") != NULL &&
                          strstr(buffer, "surface_lower_expr.c") != NULL;
        
        if (!aborted || !message_ok) {
            if (!aborted) fprintf(stderr, "ICE test failed: child did not abort (status=%d)\n", status);
            if (!message_ok) fprintf(stderr, "ICE test failed: message mismatch. Got: %s\n", buffer);
        }

        return aborted && message_ok;
    } else {
        perror("fork");
        return false;
    }
}

int main(void) {
    RUN_TEST(test_trigger_ice);
    printf("[%2d/%2d] ICE trigger test\n", tests_passed, tests_run);
    return (tests_run == tests_passed) ? 0 : 1;
}
