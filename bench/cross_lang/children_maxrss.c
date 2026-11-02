/*
 * bench/cross_lang/children_maxrss.c - report the peak resident memory of the largest process a
 * shell command ran, for scripts/bench_cross_lang.sh.
 *
 * Usage, from a subshell that has just run the command:
 *     ( set +e; cmd ...; exec children_maxrss "$?" OUT_FILE )
 *
 * The subshell waited for every process the command started, and the kernel folds each waited-for
 * child's peak (and its own children's) into the waiter's RUSAGE_CHILDREN; exec keeps that
 * accounting. So this reports the largest single process anywhere in the command's tree - a
 * compiler a build driver started, not just the driver - exactly, with no polling. It is the peak
 * of one process, not the sum of processes that ran at the same time.
 *
 * Writes the peak in KB to OUT_FILE and exits with the status passed in, so the caller still sees
 * the command's own exit code. POSIX getrusage; ru_maxrss is in KB on Linux and the BSDs and in
 * bytes on macOS.
 */
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
    struct rusage ru;
    long kb;
    FILE *out;

    if (argc != 3) {
        fprintf(stderr, "usage: children_maxrss <exit status> <out file>\n");
        return 2;
    }
    if (getrusage(RUSAGE_CHILDREN, &ru) != 0) {
        perror("children_maxrss: getrusage");
        return 2;
    }
    kb = ru.ru_maxrss;
#ifdef __APPLE__
    kb /= 1024;
#endif
    out = fopen(argv[2], "w");
    if (out == NULL) {
        perror("children_maxrss: open");
        return 2;
    }
    fprintf(out, "%ld\n", kb);
    if (fclose(out) != 0) {
        perror("children_maxrss: write");
        return 2;
    }
    return atoi(argv[1]);
}
