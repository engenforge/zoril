# Zoril Release Checklist

This checklist covers the steps required before cutting a tagged release, generating reproducible source and binary archives, and publishing release assets.

## 1. Pre-Release Code, Security, and Fuzzing

- [ ] Confirm there are no open private security issues blocking the release (check `doc/private/active.tm.md` in the maintainer workspace).
- [ ] Verify the release-bar fuzz record matches the current compiler, standard library, `zilc`, `zbuild`, and runtime sources (`sh scripts/check_fuzz_fresh.sh --strict`). If any of those directories changed since the last record, renew the fuzz record (`make fuzz-release`) or record a short session per the [Developer Guide](developer_guide.md#fuzzing).
- [ ] Verify runtime consistency (`sh scripts/check_runtimes.sh`) so `bootstrap/stage1/rt/runtime.s` matches `rt/runtime.s`, and decide whether a `stage1` re-pin is needed ([Two-Stage Bootstrap](bootstrap/two_stage.md)).

## 2. Version, Changelog, and Documentation

- [ ] Bump `VERSION` to the release version (for example `0.2.0`, without a leading `v`).
- [ ] Update [`CHANGELOG.md`](../CHANGELOG.md) with `## v<version> (YYYY-MM-DD)` and concise entries for language, standard library, and tooling changes, including before/after migration notes for any breaking changes ([Stability Statement](STABILITY.md)).
- [ ] Update release-versioned headers and milestone figures in [`README.md`](../README.md), [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md), [`doc/SAFETY.md`](SAFETY.md), [`doc/STABILITY.md`](STABILITY.md), [`doc/ROADMAP.md`](ROADMAP.md), [`doc/vision/why_zoril.md`](vision/why_zoril.md), `doc/spec/*.md`, and [`bench/safety_matrix/README.md`](../bench/safety_matrix/README.md).
- [ ] Refresh and verify milestone safety figures (`sh scripts/check_safety_figures.sh --milestone`).
- [ ] Check [`NOTICE`](../NOTICE) to ensure all shipped tools and third-party acknowledgments are listed accurately.
- [ ] Regenerate and verify manual pages if any CLI option or standard library documentation changed (`make man-gen`, `make man`, `sh scripts/test_man_pages.sh`).
- [ ] Format Markdown and run all documentation checks:
  ```sh
  make md-fmt
  make md-check
  make test-docs
  make test-readme
  sh scripts/check_safety_model.sh
  sh scripts/test_check_md_links.sh
  ```

## 3. Full Verification on the Development Host

- [ ] Run the full test suite (`make test`) and record the `Total:` summary line.
- [ ] Run the full pre-release gate (`make preflight`) to verify clean-tree bootstrap, 4-generation self-hosting fixpoint, full mutation suite, fuzz calibration, `--checked` build, git scenarios, store grid, benchmark thresholds, and updated `bench/records/` entries.
- [ ] Run `make user-tools` (`scripts/check_user_tools.sh`) to verify that `make` and `make test` succeed with only user-role tools on `PATH`.

## 4. Cross-Distribution Build and Test Matrix

Verify that Zoril builds from source and passes the test suite in clean environments across each target Linux distribution (for example, in clean containers, VMs, or dedicated hosts), installing only the documented dependencies ([Dependencies](dependencies.md)):

- [ ] **Arch Linux** (primary development distribution, glibc): `./scripts/check_deps.sh build`, `make`, and `make test` pass.
- [ ] **Alpine Linux** (musl; official release archive build host): `./scripts/check_deps.sh build`, `make`, and `make test` pass.
- [ ] **Debian or Ubuntu** (glibc; with QBE 1.3 or newer per [Dependencies](dependencies.md)): `./scripts/check_deps.sh build`, `make`, and `make test` pass.
- [ ] If bootstrap sources or scripts changed, also verify the minimal bootstrap stack (`make -C bootstrap/stage0-c minimal && make`).

## 5. Final Release Commit and Tagging

- [ ] Confirm `git status` is clean on `main` and all release-preparation commits are in place.
- [ ] Create an annotated (and preferably signed) git tag on the release commit **before** building release binaries or archives:
  ```sh
  git tag -s v<version> -m "Zoril v<version>"
  # or: git tag -a v<version> -m "Zoril v<version>"
  ```
- [ ] Rebuild the toolchain (`make`) and verify every tool reports the exact release version with no `-dirty` or `-g<sha>` suffix:
  ```sh
  ./build/zoril --version
  ./build/zilc --version
  ./build/zbuild --version
  ```

## 6. Release Archives and Reproducibility (Alpine Linux)

Perform the official archive build on Alpine Linux ([Reproducible Builds](reproducible_builds.md)):

- [ ] Clear any previous archives from `build/dist/` so `SHA256SUMS` and `build-info.txt` include only the current release:
  ```sh
  rm -rf build/dist
  ```
- [ ] Build both archives twice and run the end-to-end user path checks (`dist_user_paths.sh`):
  ```sh
  DIST_REQUIRE_ALPINE=1 RELEASE_TAG=v<version> make dist-check
  ```
  (If `qbe` was built from source rather than installed from a package, also set `QBE_VERSION` and `QBE_COMMIT`.)
- [ ] Generate the release artifacts into `build/dist/`:
  ```sh
  DIST_REQUIRE_ALPINE=1 RELEASE_TAG=v<version> make dist dist-bin
  ```
- [ ] Inspect `build/dist/build-info.txt` and `build/dist/SHA256SUMS` to verify `version`, `release_tag`, `commit`, `tree`, `host_os`, `binutils`, `qbe_*`, and archive hashes contain no unexpected `unknown` or `-dirty` values.
- [ ] Verify the unpacked source tarball in an empty directory outside the repository with no `.git` directory and with `git` removed from `PATH`: `make` and `make test` pass, and the built tools report `<version>`.
- [ ] Run `make repro-check` on the tagged commit to verify two clean source-bootstrap builds produce byte-identical `zoril`, `zilc`, `zbuild`, and `runtime.o`.
- [ ] Sign `build/dist/SHA256SUMS` if publishing signatures for the release (its contents cover every archive and `build-info.txt`).

## 7. Publishing and Post-Upload Verification

- [ ] Push `main` and the `v<version>` tag to the primary repository and mirrors (`git.engenforge.com`, GitLab, GitHub).
- [ ] Push companion branches: `bench/records` (`git -C bench/records push`) and `doc/tasks` (`tm sync --push` after recording the completion note and sweeping the release task).
- [ ] Publish `zoril-<version>.tar.xz`, `zoril-<version>-linux-x86_64.tar.xz`, `SHA256SUMS`, `build-info.txt` (and any signature file) to `https://get.engenforge.com/zoril/<version>/`, GitLab Releases, and GitHub Releases.
- [ ] Download the published files back from the release URL, verify `sha256sum -c SHA256SUMS`, and smoke-test extracting the binary archive into a scratch `PREFIX` per [`README.md`](../README.md#installing-a-prebuilt-release-linux-x86-64).
