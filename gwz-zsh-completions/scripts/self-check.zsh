#!/usr/bin/env zsh
# Self-check for the gwz-zsh-completions skill.
#
# Validates:
# - syntax of the scripts and demo fixture;
# - frontmatter basics;
# - harness assertions on the bundled fixture;
# - linter behaviour on generator output (C0 form) and bash-compat negatives;
# - probe-help fallback on a real command;
# - absence of commit hashes and machine-specific paths.

emulate -L zsh
typeset -g SKILL_DIR=${0:A:h:h}

__check() {
  local label=$1
  shift
  print -r -- "== $label"
  if "$@"; then
    return 0
  fi
  print -r -- "FAIL: $label"
  return 1
}

__check_frontmatter() {
  local skill_md=$1
  [[ $(head -n 1 "$skill_md") == '---' ]] || return 1
  grep -q '^name: gwz-zsh-completions$' "$skill_md" || return 1
  grep -q '^description: ' "$skill_md" || return 1
  return 0
}

__check_probe() {
  local probe=$1
  local out
  out=$("$probe" ls 2>/dev/null) || return 1
  [[ $out == *Usage:* ]]
}

__check_fpath_tool() {
  local tool=$1
  local out
  out=$("$tool" demo 2>/dev/null) || return 1
  [[ $out == *'First match wins'* ]]
}

__lint_case() {
  local checker=$1
  local want=$2
  local label=$3
  local header=$4
  local body=$5
  local tmpdir tmp rc

  tmpdir=$(mktemp -d) || return 1
  tmp=$tmpdir/_demo
  print -r -- '#compdef demo' > "$tmp"
  print -r -- '' >> "$tmp"
  print -r -- "$header" >> "$tmp"
  print -r -- '' >> "$tmp"
  print -r -- "$body" >> "$tmp"

  "$checker" "$tmp" >/dev/null 2>&1
  rc=$?
  rm -rf "$tmpdir"

  if [[ $want == pass ]]; then
    (( rc == 0 )) && return 0
    print -r -- "FAIL: $label (linter rejected)"
  else
    (( rc != 0 )) && return 0
    print -r -- "FAIL: $label (linter accepted)"
  fi
  return 1
}

__check_completion_tool() {
  local checker=$1
  local fixture=$2
  local tmpdir tmp

  "$checker" "$fixture" >/dev/null 2>&1 || return 1

  tmpdir=$(mktemp -d) || return 1
  tmp=$tmpdir/_demo
  print -r -- '#compdef demo' > "$tmp"
  print -r -- '_demo() { :; }' >> "$tmp"
  print -r -- '_demo() { :; }' >> "$tmp"
  if "$checker" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi
  rm -rf "$tmpdir"

  tmpdir=$(mktemp -d) || return 1
  tmp=$tmpdir/_demo
  cat > "$tmp" <<'EOF'
#compdef demo
_demo() {
  _arguments '{-t,--tools}=[set tools]:tools: '
}
_demo "$@"
EOF
  if "$checker" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi
  rm -rf "$tmpdir"

  tmpdir=$(mktemp -d) || return 1
  tmp=$tmpdir/_demo
  cat > "$tmp" <<'EOF'
#compdef demo

_demo() { :; }
_demo "$@"
EOF
  if "$checker" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi
  rm -rf "$tmpdir"

  return 0
}

__check_metadata_rules() {
  local checker=$1
  local -i failed=0

  local keys=$'# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: 1.0\n# GWZCS-Completion-Source: ai'
  local plain=$'_demo() {\n  _arguments \'--flag[desc]\'\n}\n\n_demo "$@"'
  local gen=$'_demo() {\n  local -a c\n  c=( ${(f)"$(demo __complete "${words[2,-1]}" 2>/dev/null)"} )\n  _describe \'c\' c\n}\n\n_demo "$@"'

  __lint_case "$checker" pass 'ai file' "$keys" "$plain" || failed=1
  __lint_case "$checker" pass 'upstream wrapper' \
    $'# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: n/a\n# GWZCS-Completion-Source: upstream' \
    "$gen" || failed=1

  __lint_case "$checker" fail 'hand source' \
    $'# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: 1.0\n# GWZCS-Completion-Source: hand' \
    "$plain" || failed=1
  __lint_case "$checker" fail 'prose header' \
    $'# Completion for demo 1.0.\n# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: 1.0\n# GWZCS-Completion-Source: ai' \
    "$plain" || failed=1
  __lint_case "$checker" fail 'program mismatches file name' \
    $'# GWZCS-Schema: 1\n# GWZCS-Program: other\n# GWZCS-Program-Version: 1.0\n# GWZCS-Completion-Source: ai' \
    "$plain" || failed=1
  __lint_case "$checker" fail 'missing completion-source' \
    $'# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: 1.0' \
    "$plain" || failed=1
  __lint_case "$checker" fail 'ai source with __complete body' \
    "$keys" "$gen" || failed=1

  local bad_gen=$'_demo() {\n  _arguments \'{-t,--tools}=[set tools]:tools: \'\n  local -a c=( ${(f)"$(demo __complete "${words[2,-1]}" 2>/dev/null)"} )\n  _describe \'c\' c\n}\n\n_demo "$@"'
  local up_keys=$'# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: n/a\n# GWZCS-Completion-Source: upstream'

  __lint_case "$checker" pass 'upstream body is trusted (bad = spec)' \
    "$up_keys" "$bad_gen" || failed=1
  __lint_case "$checker" fail 'upstream with prose header' \
    $'# Completion for demo 1.0.\n# GWZCS-Schema: 1\n# GWZCS-Program: demo\n# GWZCS-Program-Version: n/a\n# GWZCS-Completion-Source: upstream' \
    "$gen" || failed=1

  # `=` on a brace alias is valid when the braces are outside quotes.
  __lint_case "$checker" pass 'brace alias with = and separate words' "$keys" \
    $'_demo() {\n  _arguments \'(-t --tools)\'{-t,--tools}\'=[set tools]:tools: \'\n}\n\n_demo "$@"' || failed=1
  # `'-t=[...]'` makes `-t=` the option name.
  __lint_case "$checker" fail 'short option with = inside the name' "$keys" \
    $'_demo() {\n  _arguments \'-t=[set tools]:tools: \'\n}\n\n_demo "$@"' || failed=1

  return failed
}

__check_no_hashes() {
  local dir=$1
  local -a files
  files=(${(f)"$(find "$dir" -type f ! -path '*/.git/*' ! -name 'self-check.zsh' -print)"})
  (( ${#files} )) || return 0
  ! grep -Eq '(^|[^0-9a-fA-F])[0-9a-fA-F]{7,40}([^0-9a-fA-F]|$)' "${(@)files}" 2>/dev/null
}

__check_no_paths() {
  local dir=$1
  local -a files
  files=(${(f)"$(find "$dir" -type f ! -path '*/.git/*' ! -name 'self-check.zsh' -print)"})
  (( ${#files} )) || return 0
  ! grep -Eq '(~/\.|/usr/share/|/home/|/var/)' "${(@)files}" 2>/dev/null
}

__main() {
  local skill_dir=$SKILL_DIR
  local fixtures=$skill_dir/tests/fixtures
  local harness=$skill_dir/scripts/test-completion.zsh
  local probe=$skill_dir/scripts/probe-help.zsh
  local fpath_tool=$skill_dir/scripts/check-fpath.zsh
  local checker=$skill_dir/scripts/check-completion.zsh
  local -i failed=0

  local -x TEST_COMPLETION_STARTUP_WAIT=${TEST_COMPLETION_STARTUP_WAIT:-1.5}
  local -x TEST_COMPLETION_CASE_WAIT=${TEST_COMPLETION_CASE_WAIT:-1}

  __check "zsh -n _demo" zsh -n "$fixtures/_demo" || failed=1
  __check "zsh -n test-completion.zsh" zsh -n "$harness" || failed=1
  __check "zsh -n probe-help.zsh" zsh -n "$probe" || failed=1
  __check "zsh -n check-fpath.zsh" zsh -n "$fpath_tool" || failed=1
  __check "zsh -n check-completion.zsh" zsh -n "$checker" || failed=1
  __check "check-completion fixture" __check_completion_tool "$checker" "$fixtures/_demo" || failed=1
  __check "check-completion linter rules" __check_metadata_rules "$checker" || failed=1
  __check "check-fpath output" __check_fpath_tool "$fpath_tool" || failed=1

  __check "frontmatter" __check_frontmatter "$skill_dir/SKILL.md" || failed=1

  __check "demo commands" "$harness" "$fixtures" demo \
    --expect install --expect remote --expect status \
    $'demo \t' || failed=1

  __check "demo global option" "$harness" "$fixtures" demo \
    --expect alpha --expect beta \
    $'demo --mode=\t' || failed=1

  __check "demo option collision" "$harness" "$fixtures" demo \
    --expect xray --expect yankee --reject alpha --reject beta \
    $'demo install --mode=\t' || failed=1

  __check "demo install options" "$harness" "$fixtures" demo \
    --expect --force --expect --repo --reject --json \
    $'demo install --\t' || failed=1

  __check "demo remote subcommands" "$harness" "$fixtures" demo \
    --expect add --expect remove \
    $'demo remote \t' || failed=1

  __check "demo-alt service switch" "$harness" "$fixtures" demo-alt \
    --expect alt --reject install \
    $'demo-alt \t' || failed=1

  __check "demo-alt option" "$harness" "$fixtures" demo-alt \
    --expect --alt-flag \
    $'demo-alt alt --\t' || failed=1

  __check "demo empty completion" "$harness" "$fixtures" demo \
    --expect-empty \
    $'demo install --nope\t' || failed=1

  __check "probe-help fallback" __check_probe "$probe" || failed=1
  __check "no commit hashes" __check_no_hashes "$skill_dir" || failed=1
  __check "no machine paths" __check_no_paths "$skill_dir" || failed=1

  if (( failed )); then
    print -r -- "FAILED"
    return 1
  fi

  print -r -- "ALL CHECKS PASSED"
  return 0
}

__main "$@"
