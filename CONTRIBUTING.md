# Contributing to Zoril

Thanks for your interest. Zoril is an early alpha, so bug reports, test cases, documentation fixes and small patches are the most useful contributions right now.

## How to contribute

Use whichever you prefer; each one reaches the maintainer, and email works as well as the forges.

- **Report a problem or suggest a change:** email `code@engenforge.com`, or open an issue on [GitHub](https://github.com/engenforge/zoril/issues) or [GitLab](https://gitlab.com/engenforge/zoril/-/issues) (report security vulnerabilities privately; see [Security Policy](SECURITY.md)). Open work is tracked on the `tasks` branch (`active.tm.md`, readable on any forge by switching to that branch, or with `git worktree add doc/tasks tasks`), and a pull request against the `tasks` branch may propose a task.
- **Send a change:** email a patch to `code@engenforge.com` (`git send-email` works well; <https://git-send-email.io/> shows how to set it up), or open a pull request on GitHub or a merge request on GitLab.

A project mailing list will follow; `code@engenforge.com` serves until then.

The primary repository at `git.engenforge.com` (the one the README clones) is read-only, so changes come in through the channels above.

## What a change needs

- Keep it small and focused on one thing. AI-assisted contributions are welcome under the same rule.
- Add a test that fails without the change: a probe under `bench/safety_matrix/probes/` for a safety rule, otherwise a case under `tests/`.
- Run `make test` before sending it. For a typo or other documentation fix, that is the whole check.
- Do not call Zoril "memory-safe" or say it "prevents" a class of bugs without the test behind the claim; [What Zoril Checks](doc/SAFETY.md) says what is checked and how.

Before 1.0 the language and the standard library may change incompatibly, so please open an issue before writing a syntax or semantics change. The [Roadmap](doc/ROADMAP.md) lists the directions already planned.

The rest (formatting, the other gates, safety fixes, the bootstrap directories) is in the [Developer Guide](doc/developer_guide.md#5-rules-for-changes).
