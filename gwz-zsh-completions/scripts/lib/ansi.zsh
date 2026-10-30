# Shared helpers for gwz-zsh-completions scripts.

stripAnsi() {
  emulate -L zsh
  setopt extendedglob
  local text=$1
  text=${text//$'\e'\[[0-9;?]#[A-Za-z~]/}
  print -r -- "$text"
}
