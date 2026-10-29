#!/usr/bin/env zsh
# Safely obtain help output from a command, with fallbacks.
#
# Usage:
#   probe-help.zsh <command> [args...]
#
# Tries: --help, -h, help, --help-all. Accepts a candidate only if it looks
# like help (headings or option lines), even if the command exits non-zero.
# Prints normalized help to stdout; diagnostics go to stderr.
#
# Environment:
#   PROBE_TIMEOUT  seconds per attempt (default: 8)

emulate -L zsh
typeset -g SCRIPT_NAME=${0:t}
source "${0:A:h}/lib.zsh"

__usage() {
  print -u2 "usage: $SCRIPT_NAME <command> [args...]"
  print -u2 "env: PROBE_TIMEOUT (default: 8)"
  return 2
}

__looks_like_help() {
  emulate -L zsh
  setopt extendedglob

  local text=$1
  if [[ $text == *Usage:* || $text == *usage:* || $text == *Options:* ||
        $text == *Commands:* || $text == *"Available Commands:"* ||
        $text == *Arguments:* ]]; then
    return 0
  fi

  if [[ $text == *$'\n'[[:space:]]#--[A-Za-z0-9]* ||
        $text == [[:space:]]#--[A-Za-z0-9]* ]]; then
    return 0
  fi

  return 1
}

__run_candidate() {
  local probe_timeout=${PROBE_TIMEOUT:-8}
  if (( $+commands[timeout] )); then
    LC_ALL=C LANG=C NO_COLOR=1 TERM=dumb COLUMNS=200 PAGER=cat GIT_PAGER=cat \
      timeout "$probe_timeout" "$@" 2>&1
  else
    LC_ALL=C LANG=C NO_COLOR=1 TERM=dumb COLUMNS=200 PAGER=cat GIT_PAGER=cat \
      "$@" 2>&1
  fi
}

__main() {
  if (( ! $# )); then
    __usage
    return 2
  fi

  local -a base=("$@")
  local mode out rc
  for mode in --help -h help --help-all; do
    local -a argv=("${(@)base}")
    if [[ $mode == help ]]; then
      argv+=(help)
    else
      argv+=("$mode")
    fi

    out=$(__run_candidate "${(@)argv}")
    rc=$?
    (( rc == 124 || rc == 137 )) && continue

    out=${out//$'\r'/}
    out=${out//$'\b'/}
    out=${out//$'\a'/}
    out=$(stripAnsi "$out")

    if __looks_like_help "$out"; then
      print -r -- "$out"
      return 0
    fi
  done

  print -u2 "no help-like output for: ${(j: :)base}"
  print -u2 "try: man ${base[1]} or the project's native completion"
  return 1
}

__main "$@"
