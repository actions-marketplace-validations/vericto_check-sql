---
name: Bug report
about: Something the action gets wrong on a runner, with its inputs and outputs, the install or the checksum check
title: "[BUG] "
labels: bug
---

<!--
Security vulnerabilities: do not open an issue. Report them privately, see
https://github.com/vericto/check-sql/security/policy

How `vericto check` behaves (flags, report formats, exit codes) lives in
vericto-cli, and verdicts in vericto-engine. If you are not sure where the
problem is, report it here; we move issues to the right repository.
-->

**What happened**
A clear description of what went wrong, and what you expected instead.

**Action version**
The ref in your `uses:` line (`vericto/check-sql@v1`, `@v1.0.2` or a commit SHA):

**Runner**
- [ ] `ubuntu-*` (x86_64)
- [ ] `ubuntu-*-arm` (arm64)
- [ ] `macos-*`
- [ ] `windows-*`
- [ ] Self-hosted (OS, architecture, and whether `gh`, `git` and `jq` are installed):

Runner image and version (from "Set up job" in the log):

**Workflow**
The job that runs the action, with secrets removed.
```yaml
on:
  pull_request:

permissions:
  contents: read
  security-events: write

jobs:
  vericto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
```

**Event**
- [ ] `pull_request` (from a branch of the same repository)
- [ ] `pull_request` from a fork
- [ ] `push`
- [ ] Other:

**Outputs and log**
The `exit-code` and `result` outputs, the CLI version the log reports
(`vericto --version`), and the step log around the failure. Remove anything
sensitive.
```
paste relevant output here
```

**SQL statement (if a query was blocked or allowed when it should not have been)**
```sql
-- the exact statement
```
