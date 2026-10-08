# task

A git-native task tracker for humans and coding agents. Tasks are plain markdown files in your repo. Claiming a task creates the branch `task/<id>`, which every git worktree sees at once, so parallel agents never claim the same task. No server, no database, no third-party service.

```sh
task add -p auth "Login form"                          # tasks/auth/01-login-form.md
task add -p auth -b auth/01-login-form "Logout button" # blocked until the first is done
task list                                              # every task with its state
cd "$(task claim)"                                     # claim the next ready task, enter its worktree
task done                                              # mark it done on its branch
```

Run `task help` for the full manual: file format, dependencies, nested tasks, the agent workflow and more examples.

## Install

Needs `bash`, `git` and `awk`.

```sh
curl -fsSL https://raw.githubusercontent.com/xiaoxinghu/task/main/task -o ~/.local/bin/task
chmod +x ~/.local/bin/task
```

## Use with agents

Add one line to your `AGENTS.md`:

```markdown
Tasks are tracked with the `task` CLI. Run `task help` before picking up, adding or claiming a task.
```

## Emacs

`task.el` lists, adds, claims and completes tasks by running the CLI. Install it with `use-package` (Emacs 30 or later):

```elisp
(use-package task
  :vc (:url "https://github.com/xiaoxinghu/task" :rev :newest))
```

`M-x task-list` shows the tasks of the current repository. On a task: `RET` visits it, `c` claims it, `d` marks it done, `a` adds a task and `g` reloads. `task-add`, `task-claim`, `task-done` and `task-visit` also work from any buffer in the repository, and `task-claim` and `task-path` return the worktree and the task's files for your own commands.

It runs `task` from your `exec-path`, or else the copy installed with the package. Set `task-program` to use another.

## Development

Run the checks before opening a pull request:

```sh
shellcheck task test/run.sh
bash test/run.sh
emacs -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile task.el
emacs -Q --batch -L . -l test/task-tests.el -f ert-run-tests-batch-and-exit
```
