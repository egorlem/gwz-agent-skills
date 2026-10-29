#!/usr/bin/env zsh
# Test a native zsh completion through a real interactive TAB.
#
# Usage:
#   test-completion.zsh <fpath-dir> <command> [options] [test-line ...]
#
# Options:
#   --expect TEXT        require TEXT in the output; must not be in the test line
#   --reject TEXT        forbid TEXT in the output; must not be in the test line
#   --expect-exact TEXT  require a line equal to TEXT or ending with " TEXT"
#   --expect-empty    require no completion lines besides prompt redraw
#   --help, -h        show this help
#
# Test-line is sent to the interactive shell as-is. Put a literal TAB with
# $'...' in the calling shell, e.g.:
#
#   test-completion.zsh <fpath-dir> mycmd \
#     --expect --force --expect --repo \
#     $'mycmd install --\t'
#
# Without test-lines, checks: command list, short options, long options.
# Without --expect/--reject/--expect-empty, prints diagnostics and exits 0.
#
# Environment:
#   TEST_COMPLETION_STARTUP_WAIT  seconds after compinit (default: 2)
#
# Each run uses a private compinit dump, so a stale zcompdump in $HOME cannot make a
# case fail after the completion files change.
#   TEST_COMPLETION_CASE_WAIT     seconds after TAB (default: 1)
#   TEST_COMPLETION_CLEANUP_WAIT  seconds after Ctrl-C (default: 0.3)

emulate -L zsh
typeset -g SCRIPT_NAME=${0:t}
source "${0:A:h}/lib.zsh"

__usage() {
  print -u2 "usage: $SCRIPT_NAME <fpath-dir> <command> [options] [test-line ...]"
  print -u2 ""
  print -u2 "options:"
  print -u2 "  --expect TEXT        require TEXT in output; not in the test line"
  print -u2 "  --reject TEXT        forbid TEXT in output; not in the test line"
  print -u2 "  --expect-exact TEXT  require exact line or suffix"
  print -u2 "  --expect-empty    require no completion lines"
  print -u2 "  --help, -h        show this help"
  print -u2 ""
  print -u2 "env:"
  print -u2 "  TEST_COMPLETION_STARTUP_WAIT (default: 2)"
  print -u2 "  TEST_COMPLETION_CASE_WAIT    (default: 1)"
  print -u2 "  TEST_COMPLETION_CLEANUP_WAIT (default: 0.3)"
  return 2
}

__main() {
  if (( $# < 2 )); then
    __usage
    return 2
  fi

  local fpath_dir=$1
  local cmd=$2
  shift 2

  local -a expects rejects exacts test_lines
  local expect_empty=0
  setopt localoptions extendedglob
  while (( $# )); do
    case $1 in
      (--expect)
        shift
        if (( ! $# )); then
          print -u2 "missing value for --expect"
          __usage
          return 2
        fi
        expects+=("$1")
        shift
        ;;
      (--reject)
        shift
        if (( ! $# )); then
          print -u2 "missing value for --reject"
          __usage
          return 2
        fi
        rejects+=("$1")
        shift
        ;;
      (--expect-exact)
        shift
        if (( ! $# )); then
          print -u2 "missing value for --expect-exact"
          __usage
          return 2
        fi
        exacts+=("$1")
        shift
        ;;
      (--expect-empty)
        expect_empty=1
        shift
        ;;
      (--help|-h)
        __usage
        return 0
        ;;
      (--)
        shift
        test_lines+=("$@")
        break
        ;;
      (-*)
        print -u2 "unknown option: $1"
        __usage
        return 2
        ;;
      (*)
        test_lines+=("$1")
        shift
        ;;
    esac
  done

  if [[ ! -d $fpath_dir ]]; then
    print -u2 "not a directory: $fpath_dir"
    return 2
  fi

  if (( ! ${#test_lines} )); then
    test_lines=(
      "${cmd} "$'\t'
      "${cmd} -"$'\t'
      "${cmd} --"$'\t'
    )
  fi

  local -i assert=0
  (( ${#expects} || ${#rejects} || ${#exacts} || expect_empty )) && assert=1

  zmodload zsh/zpty || return 1

  local session="zshcomp$$"
  local dumpdir dumpfile
  dumpdir=$(mktemp -d 2>/dev/null) || return 1
  dumpfile=$dumpdir/zcompdump
  zpty "$session" zsh -f -i || return 1
  trap "zpty -d ${(q)session} 2>/dev/null; rm -rf ${(q)dumpdir}" EXIT INT TERM

  zpty -w "$session" \
    "stty rows 40 columns 160 2>/dev/null; LISTMAX=10000; fpath=(${(q)fpath_dir} \$fpath); autoload -Uz compinit; compinit -u -d ${(q)dumpfile}; PROMPT='READY> '; unsetopt zle_bracketed_paste 2>/dev/null"

  local startup_wait=${TEST_COMPLETION_STARTUP_WAIT:-2}
  local case_wait=${TEST_COMPLETION_CASE_WAIT:-1}
  local cleanup_wait=${TEST_COMPLETION_CLEANUP_WAIT:-0.3}
  sleep "$startup_wait"

  local chunk
  while zpty -r -t "$session" chunk; do :; done

  local test_line out clean prefix line
  local -a lines leftovers
  local -i failed=0 case_failed=0
  for test_line in "${test_lines[@]}"; do
    print -r -- "=== ${(q)test_line}"
    zpty -n -w "$session" "$test_line"
    sleep "$case_wait"

    out=''
    while zpty -r -t "$session" chunk; do out+=$chunk; done

    out=${out//$'\r'/$'\n'}
    out=${out//$'\b'/}
    out=${out//$'\a'/}
    clean=$(stripAnsi "$out")
    lines=(${(f)clean})

    if (( ! assert )); then
      if [[ $out == *$'\a'* ]]; then
        print -r -- '[bell]'
      fi
      print -rl -- "${(@)lines[1,80]}"
      (( ${#lines} > 80 )) && print -r -- '... (truncated)'
    else
      case_failed=0

      local expected
      for expected in "${(@)expects}"; do
        if [[ $test_line == *"$expected"* ]]; then
          print -r -- "  invalid: '$expected' is part of the test line; assert the completion output, not the echo"
          case_failed=1
          continue
        fi
        if [[ $clean == *"$expected"* ]]; then
          print -r -- "  ok: $expected"
        else
          print -r -- "  missing: $expected"
          case_failed=1
        fi
      done

      local rejected
      for rejected in "${(@)rejects}"; do
        if [[ $test_line == *"$rejected"* ]]; then
          print -r -- "  invalid: rejected '$rejected' is part of the test line"
          case_failed=1
          continue
        fi
        if [[ $clean == *"$rejected"* ]]; then
          print -r -- "  unexpected: $rejected"
          case_failed=1
        fi
      done

      local exact found
      for exact in "${(@)exacts}"; do
        if [[ $test_line == *"$exact"* ]]; then
          print -r -- "  invalid: '$exact' is part of the test line"
          case_failed=1
          continue
        fi
        found=0
        for line in "${(@)lines}"; do
          line=${line%%[[:space:]]#}
          if [[ $line == "$exact" || $line == *" $exact" ]]; then
            found=1
            break
          fi
        done
        if (( found )); then
          print -r -- "  ok exact: $exact"
        else
          print -r -- "  missing exact: $exact"
          case_failed=1
        fi
      done

      if (( expect_empty )); then
        leftovers=()
        prefix=${test_line%%$'\t'*}
        for line in "${(@)lines}"; do
          [[ -z $line ]] && continue
          [[ $line == '[bell]' ]] && continue
          [[ $line == *"$prefix"* ]] && continue
          leftovers+=("$line")
        done
        if (( ${#leftovers} )); then
          print -r -- "  expected empty, got:"
          print -rl -- "${(@)leftovers[1,20]}"
          case_failed=1
        fi
      fi

      if (( case_failed )); then
        print -r -- 'FAIL'
        failed=1
        print -r -- '--- output ---'
        print -rl -- "${(@)lines[1,80]}"
        (( ${#lines} > 80 )) && print -r -- '... (truncated)'
      else
        print -r -- 'PASS'
      fi
    fi

    zpty -n -w "$session" $'\C-c'
    sleep "$cleanup_wait"
    while zpty -r -t "$session" chunk; do :; done
  done

  zpty -d "$session" 2>/dev/null
  trap - EXIT INT TERM

  (( failed )) && return 1
  return 0
}

__main "$@"
