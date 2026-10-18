# Changelog

All notable changes to the Vericto SQL Check action are documented here. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] - 2026-10-18

### Fixed
- Multi-line inputs no longer pass validation. The validators matched with
  `grep`, which works line by line, so a `cli-version`, `dialect`, `timeout`,
  `api-url`, `workspace` or `since` with a line break passed as long as one of
  its lines was valid; `check.sh` then handed the CLI one argument with a
  newline in it (not a shell injection, but validation was defeated), and
  `resolve.sh` stopped with exit 1 at `set_output` instead of the input error.
  A value containing a line feed or a carriage return, including a trailing
  one, is now an input error (exit 2) with the input's usual message. All
  validators share one whole-value helper, `matches` in `scripts/lib.sh`
  (bash `=~`, bash 3.2 and 5.x). If a workflow passes one of these inputs as a
  YAML block scalar (`dialect: |`), which adds a trailing newline, write it on
  one line instead.
- `check.sh` no longer aborts with "VA_FILES: unbound variable" (exit 1) on
  bash 4+ when `VA_FILES` is unset. Only direct runs of the script were
  affected; `action.yml` always sets it.

### Added
- Offline unit tests for every script (`test/lib-test.sh`,
  `test/resolve-test.sh`, `test/verify-checksum-test.sh`,
  `test/install-test.sh`, `test/check-test.sh`), with a stand-in CLI and a
  `file://` release fixture, run in CI on Linux and macOS and covered by
  shellcheck. Line coverage of `scripts/` measured with kcov: 21% to 97%. No
  behaviour change.

## [1.0.1] - 2026-10-12

### Changed
- Shorter `description` in `action.yml` (under 125 characters), as the GitHub
  Marketplace requires. No behaviour change.

## [1.0.0] - 2026-10-12

### Added
- Composite action wrapping `vericto check` from the Vericto CLI, pinned to
  CLI **1.7.1**, on Linux (x64, arm64), macOS (x64, arm64) and Windows (x64)
  runners.
- Install step that downloads the release asset for the runner, verifies its
  SHA-256 against the release's `.sha256` before extracting it, runs
  `gh attestation verify` when it can (advisory), and caches the verified
  download with `actions/cache`.
- Inputs: `api-key`, `oidc`, `workspace`, `files`, `changed`, `since`,
  `dialect`, `baseline`, `format`, `upload-sarif`, `api-url`, `timeout`,
  `cli-version` and `working-directory`.
- Outputs: `exit-code`, `result`, `sarif-file`, `report-file` and the finding
  counts `blocked`, `flagged`, `monitored` and `parse-errors`.
- Changed-files base for `pull_request`, `merge_group`, `push` and other
  events; glob patterns (including `**`) and directories in `files`.
- SARIF upload to Code Scanning, with paths made relative to the repository
  root, and a job summary.

[Unreleased]: https://github.com/vericto/check-sql/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/vericto/check-sql/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/vericto/check-sql/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vericto/check-sql/releases/tag/v1.0.0
