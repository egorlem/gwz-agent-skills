# Native zsh completion patterns

## Reference files

If a copy of
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions) is
available, inspect its `src` directory. Do not hardcode paths. Useful examples:

| File | What it shows |
| --- | --- |
| `_direnv` | `_cmd()` wrapper, helper, state machine |
| `_concourse` | scoped `curcontext`, `'(-): :->command'`, shared arrays |
| `_atach` | `_arguments -C -s -S`, `_describe` by `$state` |
| `_bower` | top-level style, exclusion groups |
| `_cap` | dynamic commands via `_call_program` |
| `_ccache` | multiple `#compdef` entries, `$service`, `_values -s ','` |
| `_kitchen` | cache keyed by `$PWD` |
| `_ghc` | `_retrieve_cache`/`_store_cache` |
| `_mvn` | `_pick_variant` for versions |
| `_age` | multiple commands in one `#compdef`, `$service`, `\*` options |

Rules: `CONTRIBUTING.md` in the
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions)
repository, the `completion-style-guide` shipped with zsh, and
`man zshcompsys`.

## Path and shadowing

- `scripts/collect/fpath.zsh <cmd>` shows the environment `FPATH`, the interactive
  `fpath`, the clean `fpath` without `FPATH`, and every `_cmd` copy.
- `FPATH` may be exported with stale values; `zsh -fc` and `zsh -ic` may show
  different paths. Check the clean variant:
  `env -u FPATH zsh -ic 'print -l $fpath'`.
- If `_cmd` exists in several directories, the first one wins. Writing to a
  shadowed directory has no effect.

## Formatting

- Two spaces for indentation, four for continuations, LF line endings, no tabs.
- Long spec strings may exceed the line limit; do not wrap them.
- Header: `#compdef`, then the `GWZCS-*` key block (`GWZCS-Schema`,
  `GWZCS-Program`, `GWZCS-Program-Version`, `GWZCS-Completion-Source`); no prose
  line and no `# Authors:` (see `template.md`). Version comes from `--version`
  or the package manager (strip a leading `v`); use `unknown` when it cannot be
  determined and `n/a` for a delegating wrapper.
- Modeline:

  ```zsh
  # Local Variables:
  # mode: Shell-Script
  # sh-indentation: 2
  # indent-tabs-mode: nil
  # sh-basic-offset: 2
  # End:
  # vim: ft=zsh sw=2 ts=2 et
  ```

- One file per command or command family.
- Multiple commands: `#compdef cmd1 cmd2`, distinguish with `$service`.
- Environment variables:
  `compdef _cmd -P -value-,VAR*,-default-`.
- Do not copy someone else's completion without permission.

## Two entry-point styles

1. Top-level: `local ...`, `_arguments ...`, `case ...`, `return ret` directly in
   the file (`_bower`, `_cap`).
2. `_cmd() { ... }` wrapper plus `_cmd "$@"` (`_direnv`, `_concourse`).
   Preferred: easier to test, no global variables.

## Naming

- `_cmd` — main function.
- `_cmd_subcommand` — subcommand handler. This name is reserved for dispatch;
  never use it for a helper.
- `__cmd_helper` — internal helper.
- `_cmd_helper_<name>` — helper when a command prefix is needed.
- Overridable helper functions use a guard:

  ```zsh
  (( $+functions[_cmd_packages] )) ||
  _cmd_packages() { ... }
  ```

- For different modes: `_call_function ret _cmd_$subcommand && return ret`.

## State machine

Simple variant:

```zsh
_arguments -C \
  '1: :_cmd_commands' \
  '*::arg:->args' && ret=0

case $state in
  (args)
    case $words[1] in
      (install) _cmd_install && ret=0 ;;
      (status)  _cmd_status  && ret=0 ;;
    esac
    ;;
esac
```

Scoped context:

```zsh
_arguments -C \
  '(-): :->command' \
  '(-)*:: :->arguments' && ret=0

case $state in
  (command)
    _cmd_commands && ret=0
    ;;
  (arguments)
    curcontext=${curcontext%:*:*}:cmd-$words[1]:
    local func="_cmd_${words[1]}"
    if (( $+functions[$func] )); then
      $func && ret=0
    else
      _message "unknown command $words[1]"
    fi
    ;;
esac
```

`curcontext` matters for subcommand styles and caches.

### `words` and `CURRENT` at each level

`words` is not the same array at every level. Do not assume `words[1]` is the
command name:

| Context | `words` starts at | Notes |
| --- | --- | --- |
| top-level `case $state` (from `*::...:->state`) | the subcommand | the command name is already removed; `words[1]` is the subcommand |
| subcommand `_arguments` | the subcommand | its positional arguments follow; `words[1]` is still the subcommand |
| action helper for `*:...:->state` | the previous normal word | the subcommand is not in `words`; `CURRENT` is relative to this slice |

When a helper indexes `$words[CURRENT-1]`, first log the array:
`print -r -- "CURRENT=$CURRENT words=(${(j: :)words})"`. The values change
between these contexts; guessing them is a common source of off-by-one
completion bugs.

### Global vs subcommand option collisions

If `--mode` exists both at the top level and inside `cmd install`, a plain
`'1:command' '*::arg:->args'` may capture the global option after the command.
Split the states:

```zsh
_arguments -C \
  '--mode=[global mode]:mode:(alpha beta)' \
  '(-): :->command' \
  '(-)*:: :->args' && ret=0
```

`(-)` prevents the top level from parsing options after the command, so
`cmd install --mode=<TAB>` goes to `_cmd_install` instead of the global
`--mode`. The `tests/fixtures/_demo` fixture covers exactly this case.

## `_arguments` flags

| Flag | Meaning |
| --- | --- |
| `-C` | rewrite `curcontext` for `->state`; required for subcommands |
| `-s` | allow stacked short options (`-abc`) |
| `-w` | with `-s`, allow stacking even when an option takes an argument |
| `-W` | complete short options after an argument in the same word |
| `-S` | do not complete options after `--`; ignore `--` |
| `-A pat` | do not complete options after the first non-option argument; `-A "-*"` is typical |
| `-n` | set `NORMARG` (declare `integer NORMARG`) |
| `--` | derive spec forms from `--help` |
| `-O name` | pass an array to action functions |

`-s` enables short-option stacking; `-S` controls behavior after `--`;
`-A "-*"` disables options after the first positional argument.

## Spec forms

- No argument: `'--json[output JSON]'`.
- With an argument: `'--repo=[path to repo]:path:_directories'`.
- Aliases: `'(-r --reboot)'{-r,--reboot}'[reboot]'`.
- Alias plus argument: `'(-b --branch)'{-b,--branch}'[branch]:branch:_refs'`;
  `=` only on the long form. `{-t,--tools}'=[...]'` produces `-t=`; that is a
  bug.
- Positional: `'1:treefile:_files'`, `'2:dest:_directories'`,
  `'*:package:_packages'`, `'3::optional:_files'`.
- Mutually exclusive: `'(--no-pub --pub)--pub[run pub]'`.
- `help`/`version`: `'(- *)'{-h,--help}'[show help]'`.
- Repeatable: `'*'{-r,--recipient=}'[encrypt]:RECIPIENT:'`; never `'\*...'`.
- Optional argument: `'--opt[desc]::arg:_files'`.
- Actions: `(a b c)`, `((a\:"desc a" b\:"desc b"))`, `->state`, `_files`,
  `{_values ...}`.

## Groups and sets

```zsh
_arguments \
  + '(operation)' \
    {-c,--compress}'[compress]' \
    {-d,--decompress}'[decompress]' \
    {-l,--list}'[list]'
```

Named groups:

```zsh
_arguments \
  '(group2--x)-a' \
  + group1 \
    -m \
    '(group2)-n' \
  + group2 \
    -x -y
```

Sets:

```zsh
_arguments - set1 \
    -c \
  - set2 \
    -d \
    ':arg:(x2 y2)'
```

Groups are cheaper than sets. The `opt_args` key is `group-option`.

## Primitives

- `_describe -t tag 'group description' array` — entries are
  `name:description`.
- `_values -s ',' 'group description' 'value[desc]' ...`.
- `_wanted tag expl 'description' compadd -a array`.
- `_alternative 'tag:description:action' ...`.
- `_files`, `_path_files`, `_directories`:
  `_files -/`, `_files -g '*.json'`, `_path_files -W dir -/`,
  `_files -P './'`, `_files -S '/'`, `_files -r ':'`.
- `_users`, `_groups`, `_hosts`, `_urls`, `_ports`, `_command_names`,
  `_parameters`, `_net_interfaces`, `_pids`.
- `_guard pattern description` — validate the input format.
- `_message 'text'` — no candidates, but an explanation is needed.
- `_tags` + `_requested` — several match types.
- Prefer `_files` over `_path_files`.

## Dynamic values and cache

A static file should avoid external commands when possible.

```zsh
local -a pkgs
pkgs=( ${(f)"$(_call_program packages rpm -qa --qf '%{NAME}\\n' 2>/dev/null)"} )
_describe -t packages 'package' pkgs
```

- `_call_program` uses `eval`; quote user data with `${(q-)...}`.
- Double `\n` in `--qf`: `'%{NAME}\\n'`, otherwise `eval` turns it into `n`.
- Only the target CLI is external; guard it with `(( $+commands[ostree] ))`.
  No interpreter dependencies; see [Hard rules](../SKILL.md#hard-rules).
- In-memory cache: `typeset -g _cache_...`.
- Cache keyed by `$PWD`: keep the directory next to the cache.
- Persistent cache: `_cache_invalid`, `_retrieve_cache`, `_store_cache`,
  `zstyle ':completion:${curcontext}:' cache-policy`.
- Always use `2>/dev/null`; do not run expensive commands unnecessarily.

## Descriptions

- No trailing period, lowercase first letter, imperative mood.
- Units: `timeout (ms)`.
- Defaults: `timeout (ms) [5000]`.
- Group description is singular; tags are plural.
- A description is mandatory; `compadd` without `"$expl[@]"` is a bug.
- The caller's description wins:
  `_wanted directories expl directory _files -/ "$@" -`.
- For `compadd`, use `_description tag expl '...'`.
- Do not copy `--help` verbatim: remove `(this one)` and `NAME`, move
  units/defaults into parentheses/brackets.

## Escaping

- Single quotes when there are no expansions, double quotes when `$var` is
  needed.
- `\:` inside spec strings and `_describe`.
- `\[`, `\]` inside descriptions.
- Spaces in array elements: `value\ with\ spaces`.
- Use different quotes for nested descriptions.
- `$words`/`$opt_args` contain text as the user typed it; do not naively split.

## Return status and local variables

- `local ret=1`; on success set `ret=0`; then `return ret`.
- Declare locally: `curcontext`, `state`, `line`, `context`, `opt_args`,
  `NORMARG`.
- Do not use `exit`.
- For glob patterns: `emulate -L zsh`, `setopt localoptions extendedglob`.
- No global side effects except an explicit `_cache_*`.

## Debugging

```zsh
unfunction _mycmd
autoload -U _mycmd
```

- `Ctrl+x h` (`_complete_help`) — contexts, tags, functions.
- `Alt+2 Ctrl+x h` — more detail.
- `Ctrl+x ?` (`_complete_debug`) — completion trace.
- `compdef _gnu_generic cmd`, then `cmd -<TAB>` — draft from `--help`.
- `_arguments --` caches specs in `_args_cache_cmd`:

  ```zsh
  print -r -- ${(F)${(@qqq)_args_cache_cmd}} > _cmd
  ```

  Long options only; no subcommands or positional arguments.

## Checklist

- [ ] File name = `#compdef`.
- [ ] Top level, global options, all subcommands.
- [ ] Options with arguments have `:message:action`.
- [ ] Positional arguments are described.
- [ ] Exclusions and groups do not conflict.
- [ ] Descriptions contain no stray `:`, `[`, `]`.
- [ ] `ret` is correct.
- [ ] L1 (syntax + lint) and L2 (registration + dispatch) pass.
- [ ] L3 only when `preflight.verification` includes `l3`; otherwise reported
  as skipped.
- [ ] `self-check.zsh` passes.
- [ ] Shell restarted or the function reloaded.
