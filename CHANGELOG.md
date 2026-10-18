# Changelog

All notable changes to the Vericto SQL Check action are documented here. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/vericto/check-sql/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/vericto/check-sql/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vericto/check-sql/releases/tag/v1.0.0
