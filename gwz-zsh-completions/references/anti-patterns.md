# Anti-patterns and boundaries

The examples and reference patterns come from
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions).

## Native zsh only

Do not use bash completions that run in zsh through compatibility mode:

- `bashcompinit`;
- `COMP_WORDS`, `COMP_CWORD`, `COMP_LINE`, `COMP_POINT`;
- `BASH_COMP_*`, `PIP_AUTO_COMPLETE`;
- `_bash_completion` and functions that read bash arrays;
- mixing bash-compatible and native zsh code in one file.

This is an anti-pattern even when the script is shipped upstream. Example:
`pip completion --zsh` is bash-compatible output using `COMP_WORDS`; do not use
it.

Generated output can look bash-like without being bash-driven. A cobra-style
wrapper calls `cmd __complete` and adds matches with `compadd`/`_describe`; it
also references `BASH_COMP_DEBUG_FILE` for optional debug logging and uses
`BASH_REMATCH` under `setopt local_options`. Neither is a compatibility driver,
so the file is native zsh and may be used as generated. `BASH_COMP_*` other than
`BASH_COMP_DEBUG_FILE` stays forbidden, and that one must come with native
completion calls — not instead of them. Judge by the API a file uses, not by the
wording it ships with.

Use `#compdef`, `_arguments`, `_values`, `_describe`, `compadd`, `_files`,
`_call_program`.

## Source priority

Check `$fpath` before generating anything: run `scripts/collect/fpath.zsh <cmd>`.
If `_cmd` is already reachable, use it and stop (C1/C2 in `SKILL.md`). A second
copy is not an improvement: `#compdef` and function names collide, and the copy
in an earlier directory silently shadows the maintained one.

When nothing is installed, take the sources in this order:

1. Native upstream generator: `cmd completion zsh`, `cmd completions zsh`,
   `cmd --generate-shell-completion zsh`.
   Examples: `podman completion zsh`, `docker completion zsh`.
   A dynamic variant using `__complete` is allowed, but account for its cost.
   The output is not hand-maintained: regenerate it after a version bump instead
   of patching it, and add the `GWZCS-*` block with
   `GWZCS-Completion-Source: upstream` and `GWZCS-Program-Version: n/a`
   (see `template.md`). The body itself is trusted as generated: the linter
   checks only the markup, and a body complaint means the markup is wrong.
2. Native system completion in `$fpath`.
3. Community completions from
   [zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions)
   (the `src` directory).
4. Generation from `--help`.
5. `_gnu_generic` — simple GNU options only.

If a source requires bash mode, discard it and generate native zsh. Do not
duplicate a native upstream completion: `#compdef` and function names collide.

## Common mistakes

Examples are collected from the fix history of
[zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions)
(commits with `fix` in the subject). Do not pin specific hashes: they depend on
the clone and time.

| Symptom | Example | Correct |
| --- | --- | --- |
| Prose header instead of metadata | `# Completion for cmd 1.2.3` | the `GWZCS-*` key block |
| Hand-written completion | a file written manually on the side | `ai` from help, or `upstream` from the tool |
| Metadata that disagrees with the file | `GWZCS-Program: foo` in `_bar` | must equal the file name and the first word of `#compdef` |
| Bash-compatible completion | `bashcompinit`, `COMP_WORDS`, `PIP_AUTO_COMPLETE` | native `#compdef`/`_arguments` |
| Missing version in the metadata block | no `GWZCS-Program-Version` | `# GWZCS-Program-Version: 1.2.3`, `unknown`, or `n/a` for a wrapper |
| Writing into a shadowed directory | a file in a later `fpath`, with an earlier `_cmd` already present | `collect/fpath.zsh`, update the first one or ask |
| Broad scan | `find /`, `grep -R $HOME` | `collect/fpath.zsh`, `fpath`, `.zshrc` |
| Probing an argument with a mutating command | `rebase --opt` without dry-run | `--help`, man, source, `--dry-run` |
| Helper named like a subcommand | helper `_cmd_kargs` and subcommand `_cmd_kargs` | `__cmd_kernel_args` |
| `_call_program --qf` with a single `\n` | `'%{NAME}\n'` | `'%{NAME}\\n'` or no `--qf` |
| Escaped repeatable star | `'\*--opt[desc]'` | `'*--opt[desc]'`; `'\*{-x,--xxx}'[...]'` → `'*'{-x,--xxx}'[...]'` |
| Interpreter dependency | `node -e`, `python -c`, `jq` in `_call_program` | native zsh; see [Hard rules](../SKILL.md#hard-rules) |
| Target CLI without a guard | `ostree` without `$+commands[ostree]` | guard + fallback |
| Overstated verification | “all options verified” after `--help` | list the assertions that were made |
| Success marked as an error | `_arguments ... && ret=1` | `&& ret=0` |
| `_arguments` flags after specs | `_arguments -C "$args[@]" -A "-*"` | `_arguments -C -A "-*" "$args[@]"` |
| Missing `:message:` before an action | `'--logtarget[desc]:(a b)'`, `'--syslogsocket:_files'` | `'--logtarget[desc]:target:(a b)'`, `'--syslogsocket[desc]:file:_files'` |
| `=` on a boolean option | `--silent=[Silences output]` | `--silent[Silences output]` |
| Quoted brace group in a spec | `'{-t,--tools}=[desc]:tools: '` (zsh: `invalid argument`) | braces outside quotes: `'(-t --tools)'{-t,--tools}'=[desc]:tools: '` |
| `=` inside the option name | `'-t=[desc]:tools: '` (option becomes `-t=`) | `'-t[desc]:tools: '` |
| Global option captures a subcommand option | `cmd install --mode` with a global `--mode` | `(-): :->command` / `(-)*:: :->args` |
| One helper for different contexts | `remove` and `update` share one source helper | separate installed sources from update targets |
| Wrong or extra parentheses | `:format:(($format))` | `:format:($format)` |
| Square brackets outside quotes | `'(- *)--version'[display version]'` | `'(- *)--version[display version]'` |
| Typo in an option name | `--profile:apply` instead of `--profile:all` | check with `--help` |
| Copy-paste in an exclusion group | `--proxy-server` excluded together with `--password-store` | audit groups |
| Global options inside a subcommand state | top-level options inside `cmds)` | shared `_arguments` before `case $state` |
| Global variables | `_cmd_options=(...)` at the top level | `local -a cmd_options=(...)` inside a function |
| Missing `-C` for subcommands | `_arguments $opts` | `_arguments -C $opts` + `$state` |
| Wrong `ret` in a helper | helper without `return ret` | `local ret=1; ...; return ret` |
| Wrong array name | `_cmd2_options` vs `cmd_options` | check the names |
| Unquoted variables | `[ ! -z $second ]` | `[[ -n $second ]]` |
| Cache without context | `_store_cache` without `_cache_invalid` | key + `cache-policy` |

Rule: after copying an option block, re-read the names, aliases, `ret`, and
exclusion lists. Most bugs are copy-paste errors, not complex logic.

Process anti-patterns:

- writing into a directory without checking `FPATH` and shadowing;
- searching for config with `find /` or `grep -R $HOME`;
- determining option arity by running `rebase`/`install`/`deploy`;
- treating `--expect substring` as proof of an exact value;
- reporting “all options verified” when only `--help` was checked.

## System examples

- `_rpm` — state machine with `_call_function ret _rpm_<state>`, local option
  arrays.
- `_dnf` — `zparseopts` in helpers, `_wanted`, `_sequence`, a sqlite3 cache,
  `+ '(pkg_filter)'` groups, `_dnf5` selection via `$commands[dnf]:P`.
- `_git` — a large state machine; inspect selectively.
- `_apt` — `_regex_arguments` for complex grammar.
- `_ztodo` — a compact `_regex_words` + `_regex_arguments` example:

  ```zsh
  local -a args reply
  args=( /$'[^\0]#\0'/ )
  _regex_words commands "ztodo command" \
    'add:add entry' \
    'del:delete entry' \
    'list:show list'
  args+=("$reply[@]")
  _regex_arguments _ztodo "${args[@]}"
  _ztodo "$@"
  ```

- System `_arguments` changes with zsh; check `man zshcompsys` for new features.

## Final checklist

- [ ] No bash-compatible code.
- [ ] Native upstream and `$fpath` checked.
- [ ] Help collected with `LC_ALL=C` and `timeout`; ANSI/CR stripped.
- [ ] Commands collected from all sections and deduplicated.
- [ ] Description continuations and `Possible values` are not lost.
- [ ] Boolean options have no `=`/metavar; options with arguments got them.
- [ ] Positional arguments come from `Arguments:`/`Usage:`.
- [ ] Exclusion groups and negation pairs checked.
- [ ] `ret` is correct, variables are local, `_arguments` flags precede specs.
- [ ] L1/L2 pass; L3 only with `gate=pass` (see `SKILL.md` → Verification).
