# Native zsh completion template

Replace `mycmd` with `<CMD>`, `install`/`status` with real `<SUB>` values, and
the actions with the appropriate `<ACTION>`.

## Parameters

| Placeholder | Meaning |
| --- | --- |
| `<CMD>` | command name; matches the `_CMD` file and `#compdef` |
| `<SUB>` | subcommand |
| `<OPT>` | option (`-x`, `--xxx`) |
| `<ARG>` | metavar or positional argument |
| `<TAG>` | match group tag (`commands`, `packages`, `refs`) |
| `<ACTION>` | `_files`, `_directories`, `(a b c)`, `->state`, helper |

## File header

```zsh
#compdef mycmd

# GWZCS-Schema: 1
# GWZCS-Program: mycmd
# GWZCS-Program-Version: 1.2.3
# GWZCS-Completion-Source: ai
#
# Local Variables:
# mode: Shell-Script
# sh-indentation: 2
# indent-tabs-mode: nil
# sh-basic-offset: 2
# End:
# vim: ft=zsh sw=2 ts=2 et
```

GWZCS = GWZ Zsh Completion Schema. The key block is the only header metadata:
there is no prose line (`# Completion for ...`) and no `# Authors:` — the policy
lives in this skill, not in the artifact. Keys appear once each, values are
single tokens; the block must stay parseable with `grep '^# GWZCS-'`.

| Key | Values |
| --- | --- |
| `GWZCS-Schema` | schema revision, currently `1` |
| `GWZCS-Program` | command name, identical to the first word of `#compdef` and to the file name without `_` |
| `GWZCS-Program-Version` | version of the CLI whose help produced the file; strip a leading `v`; `unknown` when undetermined; `n/a` when nothing is baked in (delegating wrapper) |
| `GWZCS-Completion-Source` | `upstream` — the body is the program's own generator output, trusted as generated and **not** body-linted; `ai` — generated from `--help`, man, or sources, fully linted. No other value exists: this catalog has no hand-written completions |

Take the version from `mycmd --version` or the package manager. A delegating
wrapper taken from the tool's own generator (C0) has nothing baked in:
`GWZCS-Completion-Source: upstream` with `GWZCS-Program-Version: n/a`.

For multiple commands:

```zsh
#compdef mycmd mycmd-alt
```

Distinguish them by `$service`. Environment variables use the form
`compdef _mycmd -P -value-,MYCMD_*,-default-`.

## Main dispatcher

```zsh
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
      local cmd="${words[1]//-/_}"
      local func="_mycmd_${cmd}"
      if (( $+functions[$func] )); then
        $func && ret=0
      else
        _default && ret=0
      fi
      ;;
  esac

  return ret
}
```

### Global vs subcommand option collisions

If an option name exists both at the top level and inside a subcommand, do not
parse options after the command at the top level:

```zsh
_arguments -C \
  '--mode=[global mode]:mode:(alpha beta)' \
  '(-): :->command' \
  '(-)*:: :->args' && ret=0
```

Otherwise `mycmd install --mode=<TAB>` may hit the global `--mode` instead of
`_mycmd_install`.

## Command list

```zsh
_mycmd_commands() {
  local -a commands=(
    'install:install packages'
    'status:show status'
    'remove:remove packages'
  )
  _describe -t commands 'mycmd command' commands
}
```

For a dynamic list:

```zsh
_mycmd_commands() {
  local -a commands
  commands=(
    ${(f)"$(_call_program commands mycmd help 2>/dev/null | \
      sed -n 's/^  \([a-z][a-z-]*\)  *# \(.*\)$/\1:\2/p')"}
  )
  _describe -t commands 'mycmd command' commands
}
```

## Subcommand function

```zsh
_mycmd_install() {
  local ret=1
  _arguments \
    '(-C --cache-only)'{-C,--cache-only}'[do not download data]' \
    '(-r --reboot)'{-r,--reboot}'[reboot after operation]' \
    '--stateroot=[operate on STATEROOT]:stateroot:' \
    '--enablerepo=[enable repository]:repoid:' \
    '*:package:_mycmd_packages' && ret=0
  return ret
}
```

If a command accepts several independent argument sets, use
`*::arg:->state` and `case $state`.

## Nested subcommands

```zsh
_mycmd_remote() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local ret=1

  _arguments -C \
    '1:command:_mycmd_remote_commands' \
    '*::arg:->args' && ret=0

  case $state in
    (args)
      local func="_mycmd_remote_${words[1]//-/_}"
      if (( $+functions[$func] )); then
        $func && ret=0
      else
        _default && ret=0
      fi
      ;;
  esac

  return ret
}

_mycmd_remote_commands() {
  local -a commands=(
    'add:add remote'
    'remove:remove remote'
  )
  _describe -t commands 'mycmd remote command' commands
}
```

## Scoped context

If a subcommand has its own styles and cache:

```zsh
_arguments -C \
  '(-h --help)'{-h,--help}'[show help]' \
  '(-): :->command' \
  '(-)*:: :->arguments' && ret=0

case $state in
  (command)
    _mycmd_commands && ret=0
    ;;
  (arguments)
    curcontext=${curcontext%:*:*}:mycmd-$words[1]:
    local func="_mycmd_${words[1]}"
    if (( $+functions[$func] )); then
      $func && ret=0
    else
      _message "unknown command $words[1]"
    fi
    ;;
esac
```

## Options

```zsh
_arguments \
  '--json[output JSON]' \
  '--repo=[path to repository]:path:_directories' \
  '(-r --reboot)'{-r,--reboot}'[reboot after operation]' \
  '(-b --branch)'{-b,--branch}'[rebase to branch]:branch:_mycmd_refs' \
  '--target=[target commit]:target:_mycmd_refs' \
  '(- *)'{-h,--help}'[show help]' \
  '(- *)--version[print version]'
```

Rules:

- `=` means the argument may also be given in the same word as
  `--opt=value`; the separate-word form keeps working (`zshcompsys`:
  `-optname=`). Confirm the CLI accepts `--opt=value` before using it; some
  parsers treat it as an unknown/extension flag (for example, `pi`).
- Braces must stay **outside** quotes so the alias expands:
  `'(-t --tools)'{-t,--tools}'[desc]:tools:...'`.
- Do not add `=` to a brace alias: `{-t,--tools}'=[...]'` produces `-t=` and
  breaks the short form. `'{-t,--tools}=[desc]:tools:...'` with the whole spec
  quoted is invalid: zsh fails with `invalid argument`.
  `'-t=[desc]:tools:...'` makes `-t=` the option name.
- Required argument: `:message:action`.
- Optional argument: `::message:action`.
- Repeatable option: `\*{-r,--recipient=}`.
- Mutually exclusive options: `'(--no-pub --pub)--pub[run pub]'`.
- `help`/`version`: `'(- *)'`.
- Put every spec string in single quotes.

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

Sets for different modes:

```zsh
_arguments - set1 \
    -c \
  - set2 \
    -d \
    ':arg:(x2 y2)'
```

Groups are cheaper than sets. If an option from a group is present, the key in
`opt_args` is `group-option` (for example, `operation--c`).

## Positional arguments

```zsh
_arguments \
  '1:treefile:_files' \
  '2:rootfs:_directories' \
  '3::optional:_files' \
  '*:extra:_files'
```

- `1:`, `2:` — required.
- `::` — optional.
- `*:` — repeatable.
- `->state` — jump to `case $state`.

## Actions

```zsh
_arguments \
  '--file=[input file]:file:_files' \
  '--dir=[output directory]:dir:_directories' \
  '--format=[output format]:format:(json yaml text)' \
  '--config=[config file]:config file:_files -g "*.conf"' \
  '--url=[URL]:url:_urls' \
  '--host=[host]:host:_hosts' \
  '--user=[user]:user:_users' \
  '--port=[port]:port:_ports'
```

Built-in helpers: `_files`, `_path_files`, `_directories`, `_users`, `_groups`,
`_hosts`, `_urls`, `_ports`, `_command_names`, `_parameters`,
`_net_interfaces`, `_pids`.

Prefer `_files` over `_path_files`: it respects the `list-dirs-first` and
`file-patterns` styles.

## Helper functions

```zsh
(( $+functions[_mycmd_packages] )) ||
_mycmd_packages() {
  local -a pkgs
  pkgs=( ${(f)"$(_call_program packages rpm -qa --qf '%{NAME}\\n' 2>/dev/null)"} )
  _describe -t packages 'package' pkgs
}

(( $+functions[_mycmd_refs] )) ||
_mycmd_refs() {
  local -a refs
  refs=( ${(f)"$(_call_program refs ostree refs 2>/dev/null)"} )
  _describe -t refs 'ref' refs
}
```

The `(( $+functions[...] )) ||` guard lets users override the helper.

**Helper naming:** do not name a helper `_mycmd_<subcommand>` — that name belongs
to the subcommand dispatcher. Use `__mycmd_<name>` or `_mycmd_helper_<name>`.
After renames, check for duplicates:

```bash
grep -oE '^[_a-zA-Z][-_a-zA-Z0-9]*\(\) \{' _mycmd | sort | uniq -d
```

**External dependencies:** check them with `$+commands[...]`, or the completion
will silently be empty:

```zsh
if (( $+commands[ostree] )); then
  refs=( ${(f)"$(_call_program refs ostree refs 2>/dev/null)"} )
fi

if (( $+commands[jq] )); then
  revs+=(
    ${(f)"$(print -r -- "$status_json" | jq -r '.deployments[].checksum // empty' 2>/dev/null)"}
  )
fi
```

## Shared options via `reply`

If the same options repeat across several subcommands:

```zsh
_mycmd_common_opts() {
  reply+=(
    '--sysroot=[use system root SYSROOT]:path:_directories'
    '(-q --quiet)'{-q,--quiet}'[avoid informational messages]'
  )
}

_mycmd_install() {
  local -a reply
  _mycmd_common_opts
  _arguments \
    '--force[force operation]' \
    "${reply[@]}"
}
```

`reply` must be declared `local -a` in the calling function.

## Dynamic values and cache

```zsh
_mycmd_sessions() {
  local -a sessions
  sessions=( ${(f)"$(_call_program sessions mycmd list-sessions 2>/dev/null)"} )
  _describe -t sessions 'session' sessions
}
```

- `_call_program` uses `eval`: quote user data with `${(q-)...}`.
- Double `\n` inside `--qf`: `'%{NAME}\\n'`; otherwise `eval` turns it into `n`
  and joins the names. Check the `_call_program` output after adding it.
- In-memory cache: `typeset -g _cache_...`.
- Directory-scoped cache: keep `$PWD` next to it.
- Persistent cache: `_cache_invalid`, `_retrieve_cache`, `_store_cache`,
  `zstyle ':completion:${curcontext}:' cache-policy`.
- Always use `2>/dev/null`.

## Return status

```zsh
_mycmd_sub() {
  local ret=1
  _arguments ... && ret=0
  return ret
}
```

- `0` means matches were added; otherwise return non-zero.
- Do not use `exit`.
- Declare `curcontext`, `state`, `line`, `opt_args` locally; with `-n`, also
  `NORMARG`.

## Final verification

Run the levels in `SKILL.md` → Verification. L3 only when
`scripts/preflight.zsh <cmd>` reports `verification` with `l3`; otherwise stop
at L2 and report the skip.

At L3, check at least: commands, subcommands, `--<TAB>`, `--opt=<TAB>`,
`--opt <TAB>`, an ambiguous prefix, and a path with spaces.
