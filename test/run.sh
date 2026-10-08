#!/usr/bin/env bash
# Tests for task. Each test runs the script in a fresh git repo.
# Usage: bash test/run.sh
set -uo pipefail

task=$(cd "$(dirname "$0")/.." && pwd -P)/task
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Keep the user's git config (signing, hooks, default branch) out of the tests.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset TASK_WORKTREES

# A new repo with one commit on main; prints its physical path.
repo() {
  local dir
  dir=$(mktemp -d "$tmp/repo.XXXXXX")
  dir=$(cd "$dir" && pwd -P)
  git -C "$dir" init -q -b main
  git -C "$dir" commit -q --allow-empty -m init
  echo "$dir"
}

commit_tasks() { git -C "$1" add tasks && git -C "$1" commit -q -m tasks; }

# check <name> <expected> <actual>
check() {
  if [[ "$2" != "$3" ]]; then
    printf 'FAIL %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"
  fi
}

# fails <name> <command...>: the command must exit non-zero.
fails() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL $name: expected a non-zero exit"
  fi
}

t_list_tsv() {
  local r; r=$(repo); cd "$r" || return
  "$task" add "Login form" >/dev/null
  "$task" add -b 01-login-form "Logout button" >/dev/null
  printf -- '---\nstatus: done\n---\n# Old\tthing\n' > tasks/03-old.md
  check "list --tsv" "$(printf 'ready\t01-login-form\tLogin form\t\nblocked\t02-logout-button\tLogout button\t01-login-form\ndone\t03-old\tOld thing\t')" \
    "$("$task" list --tsv)"
  fails "list rejects other arguments" "$task" list --json
  fails "list --tsv takes nothing more" "$task" list --tsv extra
}

t_list_tsv_empty() {
  local r; r=$(repo); cd "$r" || return
  check "list --tsv with no tasks" "" "$("$task" list --tsv)"
}

t_path() {
  local r; r=$(repo); cd "$r" || return
  "$task" add "Root task" >/dev/null
  "$task" add -p auth "Login form" >/dev/null
  "$task" add -p auth/01-login-form "Validate email" >/dev/null
  echo "# Shared" > tasks/README.md
  commit_tasks "$r"
  check "path of a top-level task" "$(printf '%s\n%s' "$r/tasks/01-root-task.md" "$r/tasks/README.md")" \
    "$("$task" path 01-root-task)"
  # auth/ has no README.md; auth/01-login-form/ got one when it was split.
  check "path of a nested task" \
    "$(printf '%s\n%s\n%s' "$r/tasks/auth/01-login-form/01-validate-email.md" "$r/tasks/README.md" \
       "$r/tasks/auth/01-login-form/README.md")" \
    "$("$task" path auth/01-login-form/01-validate-email)"
  fails "path of an unknown task" "$task" path nope
  fails "path of a folder" "$task" path auth
  fails "path of a README" "$task" path auth/01-login-form/README
  fails "path without an id off a task branch" "$task" path
  fails "path takes at most one id" "$task" path 01-root-task auth
}

t_claim_path_done() {
  local r wt; r=$(repo); cd "$r" || return
  "$task" add -p auth "Login form" >/dev/null
  echo "# Auth" > tasks/auth/README.md
  commit_tasks "$r"
  wt=$("$task" claim)
  check "claim prints the worktree" "$r.worktrees/auth/01-login-form" "$wt"
  check "claimed in list --tsv" "$(printf 'claimed\tauth/01-login-form\tLogin form\t')" "$("$task" list --tsv)"
  cd "$wt" || return
  check "path in the task's worktree" \
    "$(printf '%s\n%s' "$wt/tasks/auth/01-login-form.md" "$wt/tasks/auth/README.md")" "$("$task" path)"
  check "done prints the id" "auth/01-login-form" "$("$task" "done")"
  check "done edits the worktree's copy" "status: done" "$(sed -n 2p "$wt/tasks/auth/01-login-form.md")"
  check "done leaves main's copy" "status: todo" "$(sed -n 2p "$r/tasks/auth/01-login-form.md")"
}

t_next() {
  local r; r=$(repo); cd "$r" || return
  "$task" add "First" >/dev/null
  "$task" add -b 01-first "Second" >/dev/null
  check "next" "01-first" "$("$task" next)"
  fails "next takes no arguments" "$task" next 01-first
}

for t in $(declare -F | awk '$3 ~ /^t_/ { print $3 }'); do
  (cd "$tmp" && "$t") || echo "FAIL $t stopped early"
done 2>&1 | tee "$tmp/out"
failed=$(grep -c '^FAIL' "$tmp/out")
if ((failed)); then echo "$failed failed"; exit 1; fi
echo ok
