---
name: gwz-zsh-completions
description: Generate, update, and review native zsh completion files (`_command`) for CLI tools. Use when creating, fixing, or auditing a completion — reuse an existing or upstream completion, materialize the tool's own generator, or build from `--help`/man/source; verify with lint, compinit, and a real TAB through zpty. Native zsh only — never bash-compatibility completions (`bashcompinit`, `COMP_WORDS`).
license: WTFPL
compatibility: Requires zsh with compinit; the test harness uses zpty.
metadata:
  version: "1.2.1"
---

# Generating zsh completions

Use this skill when you need to create or fix a native zsh completion for an
arbitrary CLI tool: parse `--help`, collect subcommands and options, generate the
`_command` file, and verify it with a real TAB.

Do not use it for bash completions and do not run bash scripts through zsh
compatibility mode.

## Required reading

Before generating, read the following after this file:

1. `references/template.md` — skeleton, helper functions, option groups.
2. `references/help-parsing.md` — `--help` formats, safe help probing, fallback.

For review or debugging, read `references/zsh-patterns.md` and
`references/anti-patterns.md`. Do not start writing a completion file before
reading template and help-parsing.

## Hard rules

- Use only the native zsh API: `#compdef`, `_arguments`, `_values`, `_describe`,
  `compadd`, `_files`, `_call_program`.
- **Do not use** bash-compatible completions: `bashcompinit`, `COMP_WORDS`,
  `COMP_CWORD`, `BASH_COMP_*`, `_bash_completion`, bash arrays. This is an
  anti-pattern even when the script is shipped upstream.
- Do not call interpreter runtimes from the completion: `node`, `python`/
  `python3`, `perl`, `ruby`, `php`, `jq`, `deno`, `bun`, or similar. The
  completion must work with zsh alone; use parameter expansion and
  `_call_program` only for the target CLI. Do not add such a dependency to the
  skill's scripts either.
- Take the target directory from the active `fpath`; do not guess.
  `scripts/preflight.zsh <cmd>` reports the interactive and clean `fpath`, the
  winning `_cmd`, `shadowed`, and `target_candidates`; use
  `scripts/collect/fpath.zsh <cmd>` for a human-readable list of every copy when
  diagnosing shadowing. If the target directory is not first, explain the
  shadowing instead of writing silently.
- Do not scan `/` or the entire `$HOME`. Search only `fpath`, `.zshrc`,
  `.zshenv`, and the target directories; use `scripts/collect/fpath.zsh` to locate copies,
  not `find /`.
- Do not probe option arity by running a mutating command. Use `--help`, man,
  source, or a documented `--dry-run` only. For `install`, `rebase`, `deploy`,
  `upgrade`, and similar commands, never probe without dry-run.
- The file name and `#compdef` must match: `_cmd` ↔ `#compdef cmd`.
- Put the metadata block in the header — `GWZCS-*` keys, no prose:
  `GWZCS-Schema`, `GWZCS-Program`, `GWZCS-Program-Version`,
  `GWZCS-Completion-Source` (`upstream` or `ai`; see `references/template.md`).
  Take the version from `<cmd> --version`; write `unknown` when it cannot be
  determined and `n/a` when nothing is baked in (a delegating wrapper).
- A helper must not be named `_cmd_<subcommand>` — that name belongs to the
  dispatch function. Use `__cmd_<name>` or `_cmd_helper_<name>`.
- `=` is allowed only on long options, and only after confirming the CLI
  accepts `--opt=value`; otherwise use the separate-word form.
  `{-t,--tools}'=[...]'` produces `-t=` and breaks the short form.
- Repeatable option: `'*--foo[...]'` or `'*'{-f,--foo}'[...]'`. Never
  `'\*...'` — inside single quotes the backslash is literal and `_arguments`
  rejects the spec.
- If global and subcommand options share a name, parse the top level with
  `'(-): :->command'` and `'(-)*:: :->args'`; otherwise the global option
  captures the subcommand option.
- Do not duplicate a native upstream completion. Check `fpath` first: taking
  the tool's own generator output is the opposite case — when nothing is
  installed yet, it is source #1 (`references/anti-patterns.md` → Source
  priority), and its output is materialized once, not rewritten by hand.
- Do not invent anything: the source is `--help`, man, source code, an existing
  native completion, or the tool's own generator.

## Conditional generation

| # | Condition | Action |
| --- | --- | --- |
| C0 | The tool ships its own generator (`cmd completion zsh`) and no `_cmd` is reachable in `fpath` | take the generator output as the body, add the `GWZCS-*` block with `GWZCS-Completion-Source: upstream` and `GWZCS-Program-Version: n/a`; do not rewrite the body by hand |
| C1 | A native upstream zsh completion exists | use it, do not duplicate |
| C2 | A native system/community completion exists | use it as a base |
| C3 | Subcommands and structured `--help` exist | static generation + state machine |
| C4 | One command with GNU options only | `_gnu_generic`/`_arguments --` as a draft |
| C5 | Complex grammar, modes, word order | `_regex_arguments` + `_regex_words` |
| C6 | Only values are needed | helper + `_files`/`_call_program` |
| C7 | Only a bash-compatible source exists | discard it, generate native zsh |
| C8 | `--help` is missing or uninformative | man, `--help-all`, `help`, source, native upstream, manual specs |

Generator spellings vary: `completion zsh`, `completion -s zsh`,
`completions zsh`, `--generate-shell-completion zsh`. Check `--help` and use
the spelling the tool documents.

## Workflow

0. Run `scripts/preflight.zsh <cmd>` once per task and read `decision`,
   `target`, `target_candidates`, and `verification`. Use `cmd_version` for
   `GWZCS-Program-Version`; when `shadowed=yes`, mention the other copy even if
   `existing_completion` wins. Do not generate until the decision is
   `try-generator`, `generate-from-help`, or `fallback-help` after a writable
   target has been chosen. `--fast` skips gate and compinit, so it reports
   `verification=unknown`; run the full preflight before claiming L3.
1. Act on `decision`: `stop` ends the task; when the reason is
   `command-not-found`, ask whether to install the tool (install only when the
   user or the project's `AGENTS.md` allows it) and rerun preflight.
   `use-existing` means the native file already wins — use it, update only on
   an explicit request, and do not copy or lint a package-manager file.
   `choose-target` requires a writable directory from `target_candidates` or a
   question; its reason distinguishes `target-not-selected`,
   `no-writable-target`, and `target-not-writable`. `try-generator` means check
   C0 (`cmd completion zsh`) and use its output when it exists;
   `generate-from-help` is C3; `fallback-help` is C8. `scripts/collect/fpath.zsh` remains
   available for manual diagnosis; preflight already ran it.
2. Collect help for every subcommand **through** `scripts/collect/help.zsh`.
   If it cannot produce help-like output for a subcommand (for example,
   `--help` is taken as a positional), try `cmd help <sub>` or
   `cmd <sub> help`, then man. For `fallback-help`, use C8 sources (man,
   `--help-all`, source, native completion, manual specs) instead of guessing.
3. Parse options, positional arguments, values, and aliases (`#compdef`).
4. Choose an action for every argument: `_files`, `_directories`,
   `(a b c)`, `->state`, helper.
5. Generate the file using `references/template.md`.
6. Verify in levels (see Verification): L1 syntax + lint, L2 registration +
   dispatch, L3 a real TAB only when `preflight.verification` includes `l3`.
   Stop at the highest level the environment supports and report it.

## Verification

Verification has three levels. Run them in order, stop at the highest level the
environment supports, and report that level.

| Level | Check | Passes when |
| --- | --- | --- |
| L1 | `zsh -n _cmd`, `scripts/verify/lint.zsh _cmd` | both exit 0 |
| L2 | registration and dispatch (below) | `_comps[cmd] == _cmd`; every dispatched `_cmd_<sub>` is defined |
| L3 | a real TAB through `zpty` (below) | every asserted case passes |

### Gate

L3 needs a working harness. `preflight.zsh` reports it as `gate` and
`verification`: run L3 only when `verification` includes `l3` (`gate=pass`). If
the gate failed or was skipped (`--fast`), do not run L3 and do not change
`_cmd` because of it. Finish at L2 and report
`L3 skipped (gate failed)` or `L3 skipped (not probed)`.

`scripts/verify/gate.zsh` reproduces the result directly: 0 pass, 1 fail, 77 no PTY.
It exercises `tests/fixtures/_demo`, not the target file.

### L1: syntax and lint

```zsh
zsh -n _mycmd
scripts/verify/lint.zsh _mycmd
```

Generator output (C0) is a delegating wrapper, not hand-written code: its
metadata block carries `GWZCS-Program-Version: n/a`, it references
`BASH_COMP_DEBUG_FILE` for debugging, and it reads `BASH_REMATCH`. That form is
native zsh, and `scripts/verify/lint.zsh` accepts it — see
`references/anti-patterns.md` → Native zsh only. The TAB assertions below still
apply, because the wrapper inherits the CLI's own completion logic; also note
the per-invocation process cost.

Trust rules by source (see `references/template.md`):

- `GWZCS-Completion-Source: upstream` — the body is the vendor's generated
  code. Only the metadata block and `zsh -n` are checked; body checks (bash
  markers, functions, `--qf`, short `=`) are skipped. Never patch such a body:
  regenerate it.
- `GWZCS-Completion-Source: ai` — full body lint applies, because the body is
  ours to fix.

So a failing body check on an `upstream` file is a signal that the metadata is
wrong (the file is not what its header claims), not an invitation to edit it.

Package-manager completions (Homebrew `site-functions`, a distro zsh directory)
are C1/C2 sources. They do not carry `GWZCS-*` metadata and are not ours to
lint: `scripts/verify/lint.zsh` expects a path to a file we materialize. A
metadata failure on a vendor file is expected, not a completion bug.

### L2: registration and dispatch

```zsh
zsh -f -c 'fpath=(<dir> $fpath); autoload -Uz compinit; compinit -u -d <tmp>;
  print -r -- "comp=${_comps[cmd]}"; whence -v _cmd'
```

`comp` must be `_cmd`. Then check the dispatch statically: every label in
`case $words[1]` maps to a defined `_cmd_<sub>` (or falls back to `_default`),
and every helper the file calls is defined. L2 does not execute `_arguments`
and does not verify matches.

### L3: behavior

Test a real TAB (skill file paths are relative to the skill directory):

```zsh
# from the skill directory
scripts/verify/harness.zsh <fpath-dir> mycmd
```

`<fpath-dir>` is any directory from the active `fpath`; do not hardcode it.

With assertions:

```zsh
scripts/verify/harness.zsh <fpath-dir> mycmd \
  --expect --help $'mycmd --\t'
```

For slow dynamic completions, increase `TEST_COMPLETION_STARTUP_WAIT` and
`TEST_COMPLETION_CASE_WAIT`.

Check at least:

- `mycmd <TAB>` — command list;
- `mycmd <sub> <TAB>`;
- `mycmd <sub> --<TAB>` — options;
- `mycmd <sub> --opt=<TAB>` and `--opt <TAB>` — arguments;
- an ambiguous common prefix;
- a path containing spaces.

`--expect` checks for a substring, so `--expect htop` also passes for
`htop-3.4.1-...`. Use `--expect-exact` for exact checks or inspect the full
output. Assertion flags apply to every test line in one invocation; use
separate invocations for different expectations. The captured text includes
the echoed command line, so `--expect`, `--reject`, and `--expect-exact` must
not use a value that is itself part of the test line; the harness rejects such
an assertion instead of passing on the echo.

### Stop rules

- Do not run L3 when `verification` does not include `l3`.
- Two failed attempts on the same L3 case: stop editing the completion. Fix the
  harness (or report the skip) instead of trying another spec variant.
- If verification takes longer than generation, stop at the level reached.
- A skipped level is a valid result; an unverified claim is not.

### Report

State the level reached and the cases actually asserted:

- `L1 pass; L2 pass (registration _cmd, dispatch 8/8); L3 pass (mycmd <TAB>, mycmd install --, mycmd --mode)`
- `L1 pass; L2 pass; L3 skipped (gate failed)`
- `L1 pass; L2 skipped (compinit failed); L3 skipped (not probed)`

Do not write “all options verified” unless every option was asserted; list the
cases instead.

An already-open shell keeps the old completion in memory. Open a new terminal
or run:

```zsh
unfunction _mycmd
autoload -U _mycmd
```

## Maintenance

Check the whole skill after changing a script or reference:

```zsh
scripts/self-check.zsh
```

On a platform where the harness gate fails, self-check's TAB (and possibly
probe) checks fail; treat that as the gate and check the static sections, not
as a completion bug.

## Further reading

- `references/template.md` — full skeleton, subcommands, groups, helpers.
- `references/help-parsing.md` — `--help` formats, safe invocation, parsing
  algorithm, test matrix.
- `references/zsh-patterns.md` — `_arguments`, state machine, primitives, cache,
  descriptions, escaping, debugging.
- `references/anti-patterns.md` — historical mistakes, bash compatibility,
  system examples.
- `scripts/collect/fpath.zsh` — `FPATH`, interactive/clean `fpath`, shadowing;
  `--porcelain` prints key=value lines for the preflight.
- `scripts/preflight.zsh` — key=value facts and the `decision`/
  `verification` fields; `--fast` skips gate/compinit.
- `scripts/verify/gate.zsh` — harness gate on the `_demo` fixture: 0 pass, 1 fail,
  77 no PTY.
- `scripts/verify/lint.zsh` — linter for a generated `_cmd`.
- `scripts/verify/harness.zsh` — zpty harness with `--expect`/`--reject`.
- `scripts/collect/help.zsh` — safe help collection with fallback.
- `scripts/self-check.zsh` — skill self-check against the `_demo` fixture.

Reference patterns and examples come from
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions).

## License

WTFPL, full text in `LICENSE`.
