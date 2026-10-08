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

## Development

Run the checks before opening a pull request:

```sh
shellcheck task test/run.sh
bash test/run.sh
```
