# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [ ] +tests +AI-G @main Isolate hardcoded temp paths in tests/stdlib/ against parallel zbuild-diff collisions id:mnszq
    > **Created:** 2026-11-23
    > **Branch:** `main`

    - **Placed:** before id:bmkh4 (parallel test-isolation race that causes intermittent failures in `make test` and `make test-checked`).
    - **Found by:** Debian 13 (trixie) evaluation on 2026-11-23 (`make test-checked` at `-j 16`): run 1 failed `zbuild-diff` on `tests/stdlib/test_proc_cwd_env.zrl` (exit 12); run 2 passed `zbuild-diff` and failed `tests/stdlib/test_proc_cwd_env.zrl` in `Stdlib` (exit 44).
    - **Cause:** `scripts/test.sh` dispatches scenarios (including `zbuild-diff`) first into the parallel worker pool, so `zbuild-diff` runs concurrently with the `Stdlib` per-file tests, both with `cwd = repo_root`. Seven runnable tests in `tests/stdlib/` write to hardcoded paths instead of per-PID paths (unlike the other 7 file-writing tests in `tests/`, which already use `getpid` via `@syscall(39)`):
      - `tests/stdlib/test_proc_cwd_env.zrl` (`/tmp/zoril_proc_cwd_env.out`, `/tmp/zoril_proc_cwd_env_dir`)
      - `tests/stdlib/test_proc_new_group.zrl` (`/tmp/zoril_proc_group_a.pid`, `/tmp/zoril_proc_group_b.pid`)
      - `tests/stdlib/test_proc_spawn_inherited_stdio.zrl` (`/tmp/zoril_proc_redirect_a.txt`, `/tmp/zoril_proc_redirect_b.txt`)
      - `tests/stdlib/test_proc_kill_reaped.zrl` (`/tmp/zoril_proc_kill_reaped.pid`)
      - `tests/stdlib/test_stdlib_bufio.zrl` (`/tmp/test_zoril_buf_writer_into_inner.tmp`, `/tmp/test_zoril_buf_reader_into_inner.tmp`)
      - `tests/stdlib/test_stdlib_fd.zrl` (`build/test_fd_from_fd.tmp`, `build/test_fd_redirect.tmp`, `build/test_fd_shared_redirect.tmp`, `build/test_fd_err_to_out.tmp`)
      - `tests/stdlib/test_stdlib_small_api_fixes.zrl` (`build/test_small_api_open.tmp`, `build/test_sub.tmp` / `build/test_sub.tmp___`)
    - **Do:** give each of the seven tests above per-PID temp paths using `getpid` (`@syscall(39)`), matching the `format_temp_path` pattern already used in `tests/stdlib/test_stdlib_read_write.zrl`, and clean up all temp files (`unlink`, `@syscall(87)` or `fsys::unlink_path`) and temp directories (`rmdir`, `@syscall(84)`) before returning:
      - In `test_proc_new_group.zrl` and `test_proc_kill_reaped.zrl`, pass the per-PID path to `sh -c` as `$1` (`cmd.arg("-c"); cmd.arg("sleep 30 & echo $! > \"$1\"; wait"); cmd.arg("_"); cmd.arg(path);`) instead of formatting a shell command string.
      - In `test_stdlib_small_api_fixes.zrl`, preserve the non-NUL-terminated subslice check by formatting `build/test_sub_<pid>.tmp___\0` and taking `.sub(0, len - 3)`.
      - Do not print temp paths to stdout (so `zbuild-diff`'s stdout comparison remains deterministic across PIDs).
    - **Checks:** C1 deterministic parallel stress check: build each of the 7 tests and run two copies concurrently in a loop (e.g., 20 iterations of `bin & bin & wait`) — confirm `test_proc_cwd_env` fails before the fix and all 7 pass 20/20 iterations after. C2 `make test-checked` passes twice in a row with `0 failed` under parallel execution, quoting `Total:`. C3 `make test` passes with `0 failed`, quoting `Total:`. C4 running all 7 tests leaves no leftover `/tmp/zoril_proc_*`, `/tmp/test_zoril_buf_*`, `build/test_fd_*`, `build/test_small_api_*`, or `build/test_sub*` files or directories.

- [ ] +release +AI-D @main Cut v0.2.0 release: build/verify dist tarballs, final release commit, and tag id:bmkh4
    > **Created:** 2026-11-23
    > **Branch:** `main`
    > **Depends:** id:jtk00

    - **Placed:** directly after id:jtk00 (split from id:jtk00 per the maintainer's request on 2026-11-23).
    - **Do:** finalize and publish the `v0.2.0` release on `main` (maintainer):
      1. Make any final release commit if needed.
      2. Build and verify the release source/binary tarballs (`make dist`, unpack into an empty directory, build and run `make test` from the tarball with no `.git` and `git` off `PATH`).
      3. Tag `v0.2.0` and publish the release (never push tags from an agent session).
    - **Checks:** C1 `make dist` produces the release tarball, and building + running `make test` from the unpacked tarball (with no `.git` and `git` off `PATH`) passes, quoting `Total:`. C2 `v0.2.0` release tag created and published by the maintainer.
