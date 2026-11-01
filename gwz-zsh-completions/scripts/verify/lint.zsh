#!/usr/bin/env zsh
# Lint a generated native zsh completion file.
#
# Usage:
#   verify/lint.zsh <path-to-_command>
#
# Checks:
# - first line starts with #compdef;
# - filename matches a command in #compdef;
# - GWZCS metadata block: Schema/Program/Program-Version/Completion-Source
#   present exactly once, values in the closed vocabulary, consistent with the
#   body (upstream <=> __complete) and with #compdef;
# - body checks (bash markers, functions, --qf, short `=`) apply to `ai` files
#   only: an `upstream` body is the vendor's own code and is trusted as
#   generated, so only `zsh -n` is run on it;
# - no prose header (# Completion for ..., # Authors: ...);
# - zsh -n passes;
# - no bash-compatibility markers (BASH_COMP_DEBUG_FILE is allowed only for
#   debug logging next to native completion calls);
# - no duplicate function definitions;
# - no single-backslash \n in _call_program --qf;
# - no `=` inside a quoted brace group and no `-x=[...]` spec (both break
#   option aliases; `{-x,--xxx}'=[...]'` with braces outside quotes is valid);
# - no interpreter dependency (node/python/perl/ruby/php/jq/deno/bun);
# - repeatable specs use '*--opt[...]' or '*'{-x,--xxx}'[...]', not '\*...'.

emulate -L zsh
typeset -g SCRIPT_NAME=${0:t}

__usage() {
  print -u2 "usage: $SCRIPT_NAME <path-to-_command>"
  return 2
}

__check() {
  local label=$1
  shift
  if "$@"; then
    print -r -- "ok: $label"
    return 0
  fi
  print -r -- "FAIL: $label"
  return 1
}

__main() {
  if (( $# != 1 )); then
    __usage
    return 2
  fi

  local file=$1
  if [[ ! -f $file ]]; then
    print -u2 "not a file: $file"
    print -u2 "pass a path to a generated _cmd, not a command name"
    return 2
  fi

  local -i failed=0
  local first_line
  first_line=$(head -n 1 "$file")
  local base=${file:t}
  local cmd=${base#_}

  if [[ $first_line == '#compdef '* ]]; then
    print -r -- 'ok: #compdef'
  else
    print -r -- 'FAIL: #compdef'
    failed=1
  fi

  if [[ " $first_line " == *" $cmd "* ]]; then
    print -r -- "ok: compdef contains $cmd"
  else
    print -r -- "FAIL: compdef does not contain $cmd"
    failed=1
  fi

  local -A meta
  local key value
  local -a required
  required=( Schema Program Program-Version Completion-Source )
  local -i count
  for key in $required; do
    count=$(grep -cE "^# GWZCS-$key: " "$file")
    if (( count == 1 )); then
      meta[$key]=$(sed -nE "s/^# GWZCS-$key: (.*)$/\1/p" "$file")
    else
      print -r -- "FAIL: # GWZCS-$key must appear exactly once (found $count)"
      failed=1
    fi
  done

  local -i meta_problem=0
  if [[ ${meta[Schema]} != 1 ]]; then
    print -r -- "FAIL: GWZCS-Schema must be 1 (got '${meta[Schema]}')"
    meta_problem=1
  fi

  if [[ ${meta[Program]} != $cmd ]]; then
    print -r -- "FAIL: GWZCS-Program must be '$cmd' (got '${meta[Program]}')"
    meta_problem=1
  fi

  local version=${meta[Program-Version]}
  if [[ $version != (n/a|unknown) ]] &&
     ! print -r -- "$version" | grep -qE '^[A-Za-z0-9][A-Za-z0-9.+~_-]*$'; then
    print -r -- "FAIL: GWZCS-Program-Version must be one token, n/a, or unknown (got '$version')"
    meta_problem=1
  fi

  local source=${meta[Completion-Source]}
  case $source in
    (upstream)
      if [[ $version == unknown ]]; then
        print -r -- 'FAIL: source upstream needs a concrete version or n/a, not unknown'
        meta_problem=1
      fi
      ;;
    (ai)
      if grep -q '__complete' "$file"; then
        print -r -- 'FAIL: source ai but the body delegates to __complete; use upstream'
        meta_problem=1
      fi
      ;;
    (hand)
      print -r -- 'FAIL: hand-written completions are not part of this catalog; use ai'
      meta_problem=1
      ;;
    (*)
      print -r -- "FAIL: GWZCS-Completion-Source must be upstream or ai (got '$source')"
      meta_problem=1
      ;;
  esac

  if grep -qE '^# (Completion for|Built from|Authors:)' "$file"; then
    print -r -- 'FAIL: prose header; keep only the GWZCS-* key block'
    meta_problem=1
  fi

  if (( meta_problem )); then
    failed=1
  else
    print -r -- "ok: GWZCS metadata ($source, $version)"
  fi

  __check 'zsh -n' zsh -n "$file" || failed=1

  if [[ $source == upstream ]]; then
    print -r -- 'ok: body not linted (upstream: trusted as generated)'
    grep -qE '__complete|-\*- shell-script -\*-' "$file" ||
      print -r -- 'warn: upstream without a generator marker; the body is taken on trust'
    if (( failed )); then
      print -r -- 'FAILED'
      return 1
    fi
    print -r -- 'PASSED'
    return 0
  fi

  local -a bash_vars
  bash_vars=(
    ${(f)"$(grep -oE 'BASH_COMP_[A-Za-z0-9_]+' "$file" 2>/dev/null | sort -u)"}
  )
  bash_vars=( ${bash_vars:#BASH_COMP_DEBUG_FILE} )

  if grep -Eq 'bashcompinit|COMP_WORDS|COMP_CWORD|COMP_LINE|COMP_POINT|PIP_AUTO_COMPLETE|_bash_completion' "$file"; then
    print -r -- 'FAIL: bash-compatibility marker'
    failed=1
  elif (( ${#bash_vars} )); then
    print -r -- "FAIL: bash-compatibility marker: ${bash_vars[*]}"
    failed=1
  elif grep -q 'BASH_COMP_DEBUG_FILE' "$file" &&
       ! grep -qE 'compadd|_describe|_arguments|_values' "$file"; then
    print -r -- 'FAIL: bash-compatibility marker: debug variable without native completion calls'
    failed=1
  else
    print -r -- 'ok: no bash-compatibility markers'
  fi

  if grep -qF "'\*" "$file"; then
    print -r -- "FAIL: escaped repeatable star; use '*--opt[...]' or '*'{-x,--xxx}'[...]'"
    failed=1
  else
    print -r -- 'ok: repeatable specs'
  fi

  if grep -nE '(_call_program[^#]*|\$\(|`)[[:space:]]*(node|python3?|perl|ruby|php|jq|deno|bun)([[:space:]]|$)' "$file" >/dev/null; then
    print -r -- 'FAIL: interpreter dependency; use native zsh'
    failed=1
  else
    print -r -- 'ok: no interpreter dependencies'
  fi

  local -a funcs
  funcs=(
    ${(f)"$(grep -oE '^[_a-zA-Z][-_a-zA-Z0-9]*\(\)( \{)?' "$file" | sed -e 's/() {$//' -e 's/()$//')"}
  )
  if (( ${#funcs} == 0 )); then
    print -r -- 'FAIL: no function definitions found'
    failed=1
  else
    local -a uniq dupes
    uniq=( ${(u)funcs} )
    local func candidate
    local -i count=0
    for func in $uniq; do
      count=0
      for candidate in $funcs; do
        [[ $candidate == $func ]] && (( count++ ))
      done
      (( count > 1 )) && dupes+=("$func")
    done
    if (( ${#dupes} )); then
      print -r -- "FAIL: duplicate functions: ${dupes[*]}"
      failed=1
    else
      print -r -- "ok: ${#funcs} functions, no duplicates"
    fi
  fi

  if grep -nE '_call_program.*--qf.*[^\\]\\n' "$file" >/dev/null; then
    print -r -- 'FAIL: _call_program --qf has single-backslash \n; use \\n or no --qf'
    failed=1
  else
    print -r -- 'ok: _call_program --qf quoting'
  fi

  if grep -nE "('\{-[^']*\}=|'-[A-Za-z0-9?]=\[)" "$file" >/dev/null; then
    print -r -- "FAIL: bad '=' in a spec: '{-x,--xxx}=...' (braces inside quotes) or '-x=[...]'"
    failed=1
  else
    print -r -- 'ok: brace aliases and short options are formatted correctly'
  fi

  if (( failed )); then
    print -r -- 'FAILED'
    return 1
  fi

  print -r -- 'PASSED'
  return 0
}

__main "$@"
