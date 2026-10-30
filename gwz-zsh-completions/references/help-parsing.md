# Parsing `--help` for completion generation

## Formats

| Format | Markers | Example | Pitfall |
| --- | --- | --- | --- |
| GNU getopt | `Usage: cmd [OPTION]...`, columns, `-f, --file=FILE` | `ls`, `grep` | A capitalized description (`PATTERNS are...`) looks like a metavar |
| GLib GOption | `Help Options:`, `Application Options:`, `Builtin Commands:`, `--opt=VALUE` | `rpm-ostree`, `flatpak` | Commands appear only in sections; nested `Builtin "x" Commands:` |
| clap (Rust) | `Usage:`, `Arguments:`, `Options:`, description on the next line, `Possible values:`, `[default: ...]` | `rpm-ostree apply-live` | Option and description on separate lines; values after a blank line |
| Cobra/pflag (Go) | `Usage:`, `Available Commands:`, `Flags:`, `Global Flags:`, types `string`, `stringArray`, `uint`, `list` | `podman`, `docker` | Multi-line descriptions; metavar without `<>`; `buildx*` plugins |
| argparse (Python) | `usage:`, `Commands:`, `Options:`/`General Options:`, `-f, --file <file>` | `pip` | Wrapped lines; option groups; `{a,b,c}` in usage |
| custom | any headings | `systemctl`, `docker` | No single `Commands:` section |

## Safe invocation

```bash
LC_ALL=C LANG=C NO_COLOR=1 TERM=dumb COLUMNS=200 \
  PAGER=cat GIT_PAGER=cat timeout 8 <cmd> <sub> --help 2>&1
```

- `LC_ALL=C` — stable language and format.
- `COLUMNS=200` — fewer wraps, but not every tool honors it.
- `NO_COLOR=1`, `TERM=dumb` — no ANSI; strip `\x1b\[...m` and `\r` anyway.
- `timeout` — help may wait for a daemon or socket.
- `2>&1` — usage is sometimes printed to stderr.
- Do not run through `sudo`; do not execute commands that may change state
  before argument parsing.
- Do not probe option arity by running a mutating command. Use `--help`, man,
  source, or a documented `--dry-run` only.
- Do not scan `/` or the entire `$HOME` for help or config; work with `fpath`,
  `.zshrc`, and the target directories.

Do not collect help manually: use the required helper:

```bash
scripts/collect/help.zsh <cmd> <sub>
```

The script tries `--help`, `-h`, `help`, `--help-all`, checks for help markers,
and normalizes the output. The timeout is set by `PROBE_TIMEOUT` (default: 8
seconds).

## Return code and fallback

`--help` does not guarantee success:

- the command may not support `--help`;
- `--help` may return a non-zero code but still print normal usage;
- instead of help you may get `error: unknown option '--help'`;
- the output may be empty;
- help may require authorization or start a daemon.

Therefore check both the return code and the content. Help markers:

- `Usage:` / `usage:` / `USAGE:`;
- `Options:` / `OPTIONS:` / `Commands:` / `COMMANDS:` /
  `Available Commands:` / `Arguments:` / `ARGUMENTS:`;
- lines starting with `-` or `--`.

If `--help` did not produce help-like output, try in order:

1. `cmd -h`;
2. `cmd help`;
3. `cmd help <sub>` or `cmd <sub> help` for a subcommand;
4. `cmd --help-all`;
5. `man cmd`;
6. source, native upstream, or manual specs.

Do not parse an error message as an option list.

## Algorithm

1. Top level: commands and global options.
2. Recurse into subcommands with depth 2–3, a `visited` set, and no loops.
   By default, do not recurse into `help`, `version`, `completion`.
3. Command sections: `Commands:`, `Available Commands:`, `Common Commands:`,
   `Management Commands:`, `Builtin Commands:`, `Builtin "x" Commands:`,
   `Subcommands:`.
4. Options: the option line, description continuations, aliases, metavar,
   possible values, default.
5. Positional arguments from `Arguments:` and `Usage:`.
6. Merge duplicates and check for short-alias conflicts.
7. Generate `_arguments` specs and verify with `zsh -n` + `zpty`.

## Option line

- An option line starts with `-` or `--` after indentation.
- Split on **two or more spaces**, not single spaces: that is the only reliable
  way to separate the description column.
- Do not assume the CLI accepts `--opt=value`; confirm via help, source, or a
  harmless invocation. If it is rejected or treated as an extension flag, use
  the separate-word form in the specs.
- Error example: `grep --help`:

  ```text
    -E, --extended-regexp     PATTERNS are extended regular expressions
  ```

  If you `strip` first, `PATTERNS` looks like a metavar even though it is the
  start of the description.
- The head contains aliases and possibly a metavar. The tail is the description.
- Description continuations are subsequent indented lines that do not start a
  new option. Append them to the previous option.
- With clap, the description may be on the next line; `Possible values:` and
  `[default: ...]` also belong to the previous option.

## Argument or not

Metavar markers in the head:

- `=ARG`, `=<ARG>`, `=[ARG]`.
- `<ARG>`, `[ARG]`, `[=ARG]`; `[]` means optional.
- Cobra/pflag types: `string`, `strings`, `stringArray`, `int`, `uint`,
  `uint16`, `float`, `bool`, `duration`, `list`, `map`, `Pathname`,
  `credentials`.
- An ALL-CAPS token (`PKG`, `STATEROOT`, `DEVICE_NAME:WEIGHT`) is a likely
  metavar, but only if it is in the head, not in the description.

When unsure:

```bash
<cmd> <sub> --opt
```

`Missing argument for --opt` means the argument is required. For an optional
argument in `_arguments`, use `::message:action`, for example
`--opt[desc]::arg:_files`.

## Commands

- Find headings with a regex, not just the word `Commands:`.
- A command line: `^\s{2,}([A-Za-z0-9][\w.:+-]*)\*?\s{2,}(.*)$`.
- `*` in docker means a plugin; the command may not be installed.
- Deduplicate commands from `Common`, `Management`, and `Commands`.
- Do not trust the program name in `Usage:`:
  - `rpm-ostree compose image --help` → `Usage: baseimage ...`;
  - `rpm-ostree usroverlay --help` → `Usage: ostree admin unlock ...`;
  - `rpm-ostree compose build-chunked-oci --help` → `Usage: rpm-ostree ...`.
  Always take the subcommand path from the actual invocation.

## Positional arguments

- `Arguments:` (clap) is the most reliable source.
- `Usage:` is a fallback: remove `[OPTIONS]`, `[options]`, `COMMAND`, `--`,
  and flags; `...` means variadic, `[...]` means optional.
- `{a,b,c}` in argparse means choices; do not confuse it with `[a-Z]` from a
  description.
- Do not turn `COMMAND` from usage into a required argument if it is actually a
  subcommand.

## Possible values and default

- clap: `Possible values:` with `- value: description` lines, or
  `[possible values: a, b, c]`.
- Cobra: values are often only in the description (`(host|private)`); do not
  parse them by guessing.
- argparse: `choices` are not always visible.
- Put defaults and units into the description: `[default: ...]`,
  `timeout (ms)`.

## Limitations

- Hidden, deprecated, and experimental options are not visible.
- Descriptions may lag behind the code.
- `--foo`/`--no-foo` and mutually exclusive modes are usually not shown in help.
- Localization breaks heuristics; always use `LC_ALL=C`.
- Plugins may be missing; do not recurse into them.
- Do not go deeper than 2–3 levels even for long help.
- If `--help` is missing or empty/uninformative, try `--help-all`, `help`,
  `man`, source, or native upstream. Do not invent options.

## Parser test matrix

| Command | What it tests |
| --- | --- |
| `rpm-ostree`, `rpm-ostree install`, `rpm-ostree compose image` | GLib + clap, nesting, usage with a different program name |
| `podman`, `docker` | Cobra, `Available Commands:`, `Global Flags:`, types, plugins |
| `python3 -m pip install` | argparse, wrapped lines, `Install Options:` groups |
| `ls`, `grep` | GNU getopt, columns, false ALL-CAPS metavars |
| `systemctl` | custom headings, options without a `Commands:` section |

Criteria: description continuations are not lost; boolean options do not get an
argument; options with `<ARG>`/`=ARG` get an argument; commands are not
duplicated; positional arguments do not become commands.
