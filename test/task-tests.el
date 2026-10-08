;;; task-tests.el --- Tests for task.el -*- lexical-binding: t; -*-

;; Run: emacs -Q --batch -L . -l test/task-tests.el -f ert-run-tests-batch-and-exit
;; Each test runs this repository's CLI in a fresh git repository.

;;; Code:

(require 'ert)
(require 'task)

(defconst task-tests--cli
  (expand-file-name "task" (file-name-directory (locate-library "task")))
  "This repository's CLI, tested with the Lisp beside it.")

(defmacro task-tests--with-repo (&rest body)
  "Run BODY in a new git repository with one commit on main."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (file-truename (make-temp-file "task-tests" t))))
          (default-directory root)
          (task-program task-tests--cli)
          (process-environment
           (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
                     "GIT_AUTHOR_NAME=test" "GIT_AUTHOR_EMAIL=test@example.com"
                     "GIT_COMMITTER_NAME=test" "GIT_COMMITTER_EMAIL=test@example.com"
                     "TASK_WORKTREES")
                   process-environment)))
     (unwind-protect
         (progn
           (task-tests--git "init" "-q" "-b" "main")
           (task-tests--git "commit" "-q" "--allow-empty" "-m" "init")
           ,@body)
       (delete-directory (directory-file-name root) t)
       (delete-directory (concat (directory-file-name root) ".worktrees") t))))

(defun task-tests--git (&rest args)
  "Run git with ARGS in `default-directory'; fail the test if it fails."
  (should (eq 0 (apply #'call-process "git" nil nil nil args))))

(defun task-tests--commit-tasks ()
  "Commit the tasks folder, so its tasks can be claimed."
  (task-tests--git "add" "tasks")
  (task-tests--git "commit" "-q" "-m" "tasks"))

(ert-deftest task-tests-tasks ()
  (task-tests--with-repo
    (should (equal (task-add "Login form") "01-login-form"))
    (should (equal (task-add "Validate email" "01-login-form") "01-login-form/01-validate-email"))
    (with-temp-file "tasks/02-blocked.md"
      (insert "---\nstatus: todo\nblocked-by: [01-login-form]\n---\n# Blocked\n"))
    (should (equal (task-tasks)
                   '((:state "ready" :id "01-login-form/01-validate-email"
                             :title "Validate email" :blockers nil)
                     (:state "blocked" :id "02-blocked" :title "Blocked"
                             :blockers ("01-login-form")))))))

(ert-deftest task-tests-no-tasks ()
  (task-tests--with-repo
    (should (equal (task-tasks) nil))))

(ert-deftest task-tests-claim-path-done ()
  (task-tests--with-repo
    (task-add "Login form" nil)
    (task-add "Logout" nil)
    (task-tests--commit-tasks)
    (let ((worktree (task-claim)))
      (should (equal worktree (concat (directory-file-name root) ".worktrees/01-login-form/")))
      (should (equal (plist-get (car (task-tasks)) :state) "claimed"))
      (let ((default-directory worktree))
        (should (equal (task-path) (list (concat worktree "tasks/01-login-form.md"))))
        (should (equal (task-done) "01-login-form"))))
    (should (equal (task-claim "02-logout") (concat (directory-file-name root) ".worktrees/02-logout/")))))

(ert-deftest task-tests-cli-errors ()
  (task-tests--with-repo
    (task-add "Only" nil)
    (task-tests--commit-tasks)
    (task-claim)
    (let ((err (should-error (task-claim) :type 'user-error)))
      (should (equal (cadr err) "task: no ready task. Every todo task is blocked or claimed:")))
    (let ((err (should-error (task-path "nope") :type 'user-error)))
      (should (string-prefix-p "task: no task file for nope at " (cadr err))))))

(ert-deftest task-tests-program-fallback ()
  (let ((task-program "no-such-task-program"))
    (should (equal (task--program) task-tests--cli)))
  (let ((task-program "sh"))
    (should (equal (task--program) (executable-find "sh")))))

(ert-deftest task-tests-list-buffer ()
  (task-tests--with-repo
    (task-add "Login form" nil)
    (task-add "Logout" nil)
    (let ((buffer (save-window-excursion (task-list))))
      (unwind-protect
          (with-current-buffer buffer
            (should (derived-mode-p 'task-list-mode))
            (should (equal (mapcar #'car tabulated-list-entries) '("01-login-form" "02-logout")))
            (goto-char (point-min))
            (should (equal (task--at-point) "01-login-form"))
            (task-add "Third" nil)
            (should (equal (length tabulated-list-entries) 3)))
        (kill-buffer buffer)))))

;;; task-tests.el ends here
