## What does this PR change?

<!-- A clear, concise description of the change. -->

## Why?

<!-- Context: a runner where the action fails, an input or output that is missing or wrong, an install or checksum problem, a CLI bump. How `vericto check` itself behaves belongs in vericto-cli; a wrong verdict for a statement belongs in vericto-engine. -->

## Type of change

- [ ] Input or output (`action.yml`)
- [ ] Installation, checksum or attestation check
- [ ] Runner support (Linux, macOS, Windows; bash 3.2 / 5.x)
- [ ] Pinned CLI version bump
- [ ] Bug fix
- [ ] Documentation
- [ ] Dependencies or CI

## Tests

- [ ] Added or updated unit tests in `test/`, including rejected and hostile inputs
- [ ] `for t in lib resolve verify-checksum install check; do bash "test/$t-test.sh"; done` passes
- [ ] actionlint and shellcheck (the images CI pins) are clean
- [ ] Every `uses:` is pinned by full commit SHA with a version comment
- [ ] `bash test/checksum-test.sh <pinned CLI version>` passes (if the install or checksum path changed)

## Checklist

- [ ] No `${{ inputs.* }}` interpolated into a `run:` script; inputs go through environment variables and `scripts/lib.sh`
- [ ] Commits follow Conventional Commits
- [ ] `CHANGELOG.md` updated under `[Unreleased]` (if a workflow using the action can see the change)
- [ ] New or changed inputs and outputs documented in `README.md` and `action.yml`
- [ ] CI is green, including the self-test runners
