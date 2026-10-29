---
name: gwz-zsh-completions
description: Generate, update, and review native zsh completion files (`_command`) for CLI tools. Use when creating or fixing completions from `--help`, subcommands, options, or validating them with compinit/zpty. Native zsh only — never bash-compatibility completions (`bashcompinit`, `COMP_WORDS`).
license: WTFPL
compatibility: Requires zsh with compinit; the test harness uses zpty.
metadata:
  version: "1.0.0"
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
2. `references/help-parsing.md` — `--help` formats, `probe-help`, fallback.

For review or debugging, read `references/zsh-patterns.md` and
`references/anti-patterns.md`. Do not start writing a completion file before
reading template and help-parsing.

## Hard rules

- Use only the native zsh API: `#compdef`, `_arguments`, `_values`, `_describe`,
  `compadd`, `_files`, `_call_program`.
- **Do not use** bash-compatible completions: `bashcompinit`, `COMP_WORDS`,
  `COMP_CWORD`, `BASH_COMP_*`, `_bash_completion`, bash arrays. This is an
  anti-pattern even when the script is shipped upstream.
- Take the target directory from the active `fpath`; do not guess.
  Before choosing it, run `scripts/check-fpath.zsh <cmd>`: it shows the
  environment `FPATH`, the interactive `fpath`, the clean `fpath` without
  `FPATH`, and every `_cmd` copy in priority order. If the target directory is
  not first, explain the shadowing instead of writing silently.
- Do not scan `/` or the entire `$HOME`. Search only `fpath`, `.zshrc`,
  `.zshenv`, and the target directories; use `check-fpath.zsh` to locate copies,
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
- `=` is allowed only on long options. `{-t,--tools}'=[...]'` produces `-t=`
  and breaks the short form.
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

## Workflow

0. Run `scripts/preflight.zsh <cmd>` and read the key=value report. Do not
   generate when `cmd_path` is empty. If `existing_completion` is set, update
   that file (`target`) only when `target_writable=yes`; otherwise stop. With no
   existing file, choose a target deliberately from `target_candidates` (prefer
   a directory that already holds `GWZCS-*` files) or ask the user. If `gate` is
   not `pass`, L3 is unavailable: plan to finish at L1/L2 and report the skip.
   `--fast` skips the gate and compinit probes.
1. Fix `CMD`, aliases, and the target directory from `fpath`:
   `scripts/check-fpath.zsh <cmd>`.
2. Check C1/C2 first: if a native completion is already reachable in `fpath`,
   use it and stop. Otherwise, if the tool ships its own generator (C0),
   materialize its output and verify it; do not rewrite it by hand.
3. Collect help for every subcommand **through** `scripts/probe-help.zsh`.
   Call help manually only if the script is unavailable.
4. Parse options, positional arguments, and values.
5. Choose an action for every argument: `_files`, `_directories`,
   `(a b c)`, `->state`, helper.
6. Generate the file using `references/template.md`.
7. Verify: `zsh -n`, `scripts/check-completion.zsh _cmd`, a real TAB through
   `zpty` + `compinit`, then `scripts/self-check.zsh`.

## Minimal skeleton

```zsh
#compdef mycmd

_mycmd() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local ret=1

  _arguments -C \
    '(-h --help)'{-h,--help}'[show help]' \
    '--version[print version]' \
    '1:command:_mycmd_commands' \
    '*::arg:->args' && ret=0

  case $state in
    (args)
      local func="_mycmd_${words[1]//-/_}"
      if (( $+functions[$func] )); then
        $func && ret=0
      else
        _default && ret=0
      fi
      ;;
  esac

  return ret
}

_mycmd_commands() {
  local -a commands=(
    'install:install packages'
    'status:show status'
  )
  _describe -t commands 'mycmd command' commands
}

_mycmd_install() {
  local ret=1
  _arguments \
    '(-C --cache-only)'{-C,--cache-only}'[do not download data]' \
    '(-r --reboot)'{-r,--reboot}'[reboot after operation]' \
    '--stateroot=[operate on STATEROOT]:stateroot:' \
    '*:package:_mycmd_packages' && ret=0
  return ret
}

_mycmd_packages() {
  local -a pkgs
  pkgs=( ${(f)"$(_call_program packages rpm -qa --qf '%{NAME}\\n' 2>/dev/null)"} )
  _describe -t packages 'package' pkgs
}

_mycmd "$@"
```

## Verification

```zsh
zsh -n _mycmd
scripts/check-completion.zsh _mycmd
```

Then test a real TAB (skill file paths are relative to the skill directory):

```zsh
# from the skill directory
scripts/test-completion.zsh <fpath-dir> mycmd
```

`<fpath-dir>` is any directory from the active `fpath`; do not hardcode it.

Generator output (C0) is a delegating wrapper, not hand-written code: its
metadata block carries `GWZCS-Program-Version: n/a`, it references
`BASH_COMP_DEBUG_FILE` for debugging, and it reads `BASH_REMATCH`. That form is
native zsh, and `check-completion.zsh` accepts it — see
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

With assertions:

```zsh
scripts/test-completion.zsh <fpath-dir> mycmd \
  --expect --help $'mycmd --\t'
```

For slow dynamic completions, increase `TEST_COMPLETION_STARTUP_WAIT` and
`TEST_COMPLETION_CASE_WAIT`.

Check the whole skill (from the skill directory):

```zsh
scripts/self-check.zsh
```

Check at least:

- `mycmd <TAB>` — command list;
- `mycmd <sub> <TAB>`;
- `mycmd <sub> --<TAB>` — options;
- `mycmd <sub> --opt=<TAB>` and `--opt <TAB>` — arguments;
- an ambiguous common prefix;
- a path containing spaces.

`--expect` checks for a substring, so `--expect htop` also passes for
`htop-3.4.1-...`. Use `--expect-exact` for exact checks or inspect the full
output. Do not write “all options verified” in the final report if the harness
only checked `--help`; list what was actually asserted.

An already-open shell keeps the old completion in memory. Open a new terminal
or run:

```zsh
unfunction _mycmd
autoload -U _mycmd
```

## Further reading

- `references/template.md` — full skeleton, subcommands, groups, helpers.
- `references/help-parsing.md` — `--help` formats, safe invocation, parsing
  algorithm, test matrix.
- `references/zsh-patterns.md` — `_arguments`, state machine, primitives, cache,
  descriptions, escaping, debugging.
- `references/anti-patterns.md` — historical mistakes, bash compatibility,
  system examples.
- `scripts/check-fpath.zsh` — `FPATH`, interactive/clean `fpath`, shadowing;
  `--porcelain` prints key=value lines for the preflight.
- `scripts/preflight.zsh` — key=value facts before generation (command,
  fpath, target, help, PTY, gate, compinit); `--fast` skips gate/compinit.
- `scripts/gate.zsh` — harness gate on the `_demo` fixture: 0 pass, 1 fail,
  77 no PTY.
- `scripts/check-completion.zsh` — linter for a generated `_cmd`.
- `scripts/test-completion.zsh` — zpty harness with `--expect`/`--reject`.
- `scripts/probe-help.zsh` — safe help collection with fallback.
- `scripts/self-check.zsh` — skill self-check against the `_demo` fixture.

Reference patterns and examples come from
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions).

## License

WTFPL, full text in `LICENSE`.
