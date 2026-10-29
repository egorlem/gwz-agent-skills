#!/usr/bin/env zsh
# Show where a zsh completion file comes from and which copy wins.
#
# Usage:
#   check-fpath.zsh <command>
#
# Prints FPATH from the environment, interactive fpath, clean fpath with
# FPATH unset, and the first _command found in interactive fpath order.

emulate -L zsh
typeset -g SCRIPT_NAME=${0:t}

__usage() {
  print -u2 "usage: $SCRIPT_NAME <command>"
  return 2
}

__main() {
  if (( $# != 1 )); then
    __usage
    return 2
  fi

  local cmd=$1
  local file="_$cmd"

  print -r -- 'FPATH environment:'
  if [[ -n ${FPATH:-} ]]; then
    print -r -- "$FPATH"
  else
    print -r -- '(unset)'
  fi

  print -r -- ''
  print -r -- 'Interactive fpath:'
  zsh -ic 'print -l $fpath' 2>/dev/null || print -r -- '(failed)'

  print -r -- ''
  print -r -- 'Clean fpath (FPATH unset):'
  env -u FPATH zsh -ic 'print -l $fpath' 2>/dev/null || print -r -- '(failed)'

  print -r -- ''
  print -r -- "Candidates for $file in interactive fpath order:"
  zsh -ic "for d in \$fpath; do [[ -f \$d/${(q)file} ]] && print -r -- \"\$d\"; done" 2>/dev/null || true

  print -r -- ''
  print -r -- 'First match wins. If the target directory is not first, a later copy is shadowed.'
  return 0
}

__main "$@"
