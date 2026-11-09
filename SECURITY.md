# Security Policy

Zoril is an early alpha. Its checks are a goal under active work, not a guarantee ([What Zoril Checks](doc/SAFETY.md)), and they are not a sandbox: do not compile and run Zoril source you do not trust and expect the checker to contain it.

## Supported versions

Before 1.0, fixes go into `main` and the next release. Only the latest release and `main` are supported; older releases get no fixes.

## What to report privately, and what to report in public

The line is who has to control what. If a flaw needs the attacker to write the program, only programs that contain that shape are affected, and the report is public. If a correct program can be attacked through the data it reads, or the machine that builds it can be attacked through what it builds, every user is exposed until a fix ships, and the report is private.

### Private: email `code@engenforge.com`

Or use the forge's private vulnerability report where it is enabled. Do not open a public issue, pull request or task for these.

1. **Data-driven memory corruption in the standard library.** A safe standard-library API, used as documented, lets input data (a length, an index, the contents of a file or an argument) write or read memory outside what it owns instead of trapping. Example, fixed before the first release: `Vec.with_capacity_in` multiplied the element count by the element size without a check, so a count of `1 << 61` wrapped to a zero-byte allocation, the next allocation aliased it, and pushes overwrote that other data without a fault ([probe 163](bench/safety_matrix/probes/163_vec_capacity_overflow.zrl), now a trap). A program that took the count from its input gave the input a heap write.
2. **A missing run-time check.** The compiler emits code without a check that [What Zoril Checks](doc/SAFETY.md) §3 says is there, so an index that comes from input reads or writes past an array or slice instead of ending the process with exit status 134.
3. **Compromise of the build machine.** Compiling or building a source file or a `zbuild` project makes `zoril`, `zilc` or `zbuild` write outside its output, run a command, or corrupt its own memory in a way the input controls. A compiler that only crashes or rejects the input is an ordinary bug (below).
4. **Release and bootstrap integrity.** A published archive or checksum that does not match the source it names, a reproducible build that differs in a way that suggests tampering ([Reproducible Builds](doc/reproducible_builds.md)), or code in the bootstrap seeds (`bootstrap/stage0-c/`, `bootstrap/stage1/`) that does something the source does not show.

Include a minimal program or input, what you expected and what happened, and the release or commit you tested. If you are not sure which side of the line a report is on, send it privately.

### Public: an issue, or a pull request on any forge

1. **A soundness hole that needs the program to take a particular shape.** Checked code (outside `unsafe`) that the compiler should reject but accepts, and that then reads freed or out-of-frame memory, faults, or runs a destructor on the wrong value. These are the project's ordinary work: each becomes a `known_gap` probe under [`bench/safety_matrix/probes/`](bench/safety_matrix/probes) until its fix lands, and a pull request that adds the probe is welcome. Examples: `struct Arena { x: i64 }` in a program that imports `mem.zrl` is dropped with the standard library's `Arena` destructor and faults ([`gap_68`](bench/safety_matrix/probes/gap_68_drop_glue_by_type_name.zrl)); `Vec.extend_from_slice` copies views of the caller's stack frame into a longer-lived `Vec`, which later reads stale stack memory ([`gap_56`](bench/safety_matrix/probes/gap_56_extern_copy_extend_from_slice.zrl)). A new route into a class already listed under [Known gaps](doc/spec/safety_model.md#known-gaps) is reported the same way.
2. **A gap already listed** under Known gaps. It is public and tracked; a smaller reproduction or a real program that meets it is still useful.
3. **Memory errors inside `unsafe` blocks you wrote.** There the programmer is the checker ([What Zoril Checks](doc/SAFETY.md) §4).
4. **A run-time trap** (exit status 134 at an out-of-range index), a compiler crash or internal error on bad input, a wrong diagnostic, or a program the compiler rejects that it should accept.

## What happens after a private report

1. The report is acknowledged.
2. The fix is written and tested privately, with a test or safety probe that fails without it.
3. When the fix is published, the report is written into a task on the public `tasks` branch with the fix's commit, and into `CHANGELOG.md`. If the reporter agrees, they are credited.
