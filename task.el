;;; task.el --- Emacs front end for the task CLI -*- lexical-binding: t; -*-

;; Author: Xiaoxing Hu <hi@xiaoxing.dev>
;; URL: https://github.com/xiaoxinghu/task
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, vc

;;; Commentary:

;; Lists, adds, claims and completes the tasks of a git repository by
;; running the task CLI, which keeps every rule: which tasks are ready, how
;; claiming works and where task files live.  Run `task help' for its
;; manual.
;;
;; `task-list' shows the tasks of the repository `default-directory' is in.
;; `task-add', `task-claim', `task-done' and `task-visit' act on the task at
;; point there, or else ask the CLI what to act on.  `task-claim' and
;; `task-path' return what they print, so other code can build on them, for
;; example to start an agent in a claimed task's worktree.
;;
;; The CLI is `task-program' on `exec-path', or else the copy of the script
;; installed with this package.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

(defgroup task nil
  "Front end for the task CLI."
  :group 'tools
  :prefix "task-")

(defcustom task-program "task"
  "The task CLI: a program name or an absolute file name.
A name is looked up on the variable `exec-path'.  When the CLI can't be
found, the script installed with this package is used."
  :type 'string)

(defconst task--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "The directory this package was loaded from, which holds its copy of the CLI.")

(defun task--program ()
  "Return the task CLI to run."
  (or (executable-find task-program)
      (let ((bundled (expand-file-name "task" task--directory)))
        (and (file-executable-p bundled) bundled))
      (user-error "Can't find the task CLI: set `task-program'")))

(defun task--run (&rest args)
  "Run the task CLI with ARGS in `default-directory'; return its output.
Trailing newlines are removed.  When the CLI fails, signal a `user-error'
with its message."
  (when (file-remote-p default-directory)
    (user-error "The task CLI works in local repositories only"))
  (let ((program (task--program))
        (stderr (make-temp-file "task-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (apply #'call-process program nil (list t stderr) nil args)))
            (unless (eq status 0)
              (user-error "%s" (task--error stderr)))
            (string-trim-right (buffer-string) "\n+")))
      (delete-file stderr))))

(defun task--error (file)
  "Return the error the CLI wrote to FILE.
That is its last \"task: \" line, as the CLI may also print its manual or
the task list."
  (let* ((text (with-temp-buffer
                 (insert-file-contents file)
                 (string-trim (buffer-string))))
         (lines (seq-filter (lambda (line) (string-prefix-p "task: " line))
                            (split-string text "\n"))))
    (or (car (last lines)) text)))

;;; Reading tasks

(defun task-tasks ()
  "Return the tasks of the repository `default-directory' is in, in order.
Each task is a plist with :state, :id, :title and :blockers, the IDs of the
blockers that aren't done.  State is one of \"ready\", \"blocked\",
\"claimed\", \"done\" and \"wontfix\"."
  (mapcar (lambda (line)
            (pcase-let ((`(,state ,id ,title ,blockers) (split-string line "\t")))
              (list :state state :id id :title title
                    :blockers (split-string (or blockers "") " " t))))
          (split-string (task--run "list" "--tsv") "\n" t)))

(defun task-path (&optional id)
  "Return the files of task ID in this worktree.
The first is the task file; the rest are the README.md of each folder above
it, from the top down.  Without ID, use the task of the current task/<id>
branch."
  (split-string (apply #'task--run "path" (and id (list id))) "\n" t))

(defun task--read (prompt &optional any)
  "Read a task ID with PROMPT, offering every task.
With ANY non-nil, accept text that is not a task's ID, such as a folder."
  (completing-read prompt (mapcar (lambda (task) (plist-get task :id)) (task-tasks))
                   nil (not any)))

(defun task--at-point ()
  "Return the ID of the task on this line of a task list, or nil."
  (and (derived-mode-p 'task-list-mode) (tabulated-list-get-id)))

;;; Commands

;;;###autoload
(defun task-visit (id)
  "Visit the file of task ID.
Interactively, the task on this line of a task list, or else one read in
the minibuffer."
  (interactive (list (or (task--at-point) (task--read "Visit task: "))))
  (find-file (car (task-path id))))

;;;###autoload
(defun task-add (title &optional parent)
  "Add a task called TITLE, under the task or folder PARENT if non-nil.
Visit the new task's file to write its body, and return its ID.
Interactively, with a prefix argument, read PARENT too."
  (interactive
   (list (read-string "New task: ")
         (and current-prefix-arg (task--read "Under task or folder: " t))))
  (when (string-empty-p (string-trim title))
    (user-error "A task needs a title"))
  (let ((id (apply #'task--run "add" (append (and parent (list "-p" parent)) (list title)))))
    (task--refresh-lists)
    (when (called-interactively-p 'any)
      (task-visit id))
    id))

;;;###autoload
(defun task-claim (&optional id)
  "Claim task ID, or the next ready task; return its worktree.
Claiming creates the branch task/<id> and its worktree.  Interactively, claim
the task on this line of a task list, or else the next ready one."
  (interactive (list (task--at-point)))
  (let ((worktree (file-name-as-directory (apply #'task--run "claim" (and id (list id))))))
    (task--refresh-lists)
    (when (called-interactively-p 'any)
      (message "Claimed; its worktree is %s" (abbreviate-file-name worktree)))
    worktree))

;;;###autoload
(defun task-done (&optional id)
  "Mark task ID done in this worktree, and return its ID.
Without ID, use the task of the current task/<id> branch.  Interactively,
the task on this line of a task list, or else the current branch's task."
  (interactive (list (task--at-point)))
  (let ((done (apply #'task--run "done" (and id (list id)))))
    (task--refresh-lists)
    (when (called-interactively-p 'any)
      (message "Marked %s done" done))
    done))

;;; The task list

(defface task-ready '((t :inherit success))
  "Face for the state of a ready task.")

(defface task-claimed '((t :inherit warning))
  "Face for the state of a claimed task.")

(defface task-inactive '((t :inherit shadow))
  "Face for the state of a blocked, done or wontfix task.")

(defvar-keymap task-list-mode-map
  :doc "Keymap for `task-list-mode'."
  "RET" #'task-visit
  "a" #'task-add
  "c" #'task-claim
  "d" #'task-done)

(define-derived-mode task-list-mode tabulated-list-mode "Tasks"
  "Major mode for the tasks of a repository, in the CLI's order.
\\<task-list-mode-map>\\[task-visit] visits a task, \\[task-add] adds one, \
\\[task-claim] claims one and \\[task-done] marks one done.
\\<tabulated-list-mode-map>\\[revert-buffer] reloads the list.

\\{task-list-mode-map}"
  (setq tabulated-list-format [("State" 8 nil) ("Task" 36 nil) ("Title" 40 nil)
                               ("Blocked by" 0 nil)])
  (setq tabulated-list-padding 1)
  (add-hook 'tabulated-list-revert-hook #'task--list-entries nil t)
  (tabulated-list-init-header))

(defun task--list-entries ()
  "Read this buffer's tasks into `tabulated-list-entries'."
  (setq tabulated-list-entries
        (mapcar (lambda (task)
                  (let ((state (plist-get task :state)))
                    (list (plist-get task :id)
                          (vector (propertize state 'face
                                              (pcase state
                                                ("ready" 'task-ready)
                                                ("claimed" 'task-claimed)
                                                (_ 'task-inactive)))
                                  (plist-get task :id)
                                  (plist-get task :title)
                                  (string-join (plist-get task :blockers) ", ")))))
                (task-tasks))))

(defun task--repository ()
  "Return the root of the repository `default-directory' is in, or it."
  (expand-file-name (or (locate-dominating-file default-directory ".git")
                        default-directory)))

;;;###autoload
(defun task-list ()
  "List the tasks of the repository `default-directory' is in.
Each repository has one list buffer; listing it again reloads it."
  (interactive)
  (let* ((root (task--repository))
         (buffer (get-buffer-create (format "*tasks: %s*" (abbreviate-file-name root)))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'task-list-mode) (task-list-mode))
      (setq default-directory root)
      (revert-buffer))
    (pop-to-buffer buffer)))

(defun task--refresh-lists ()
  "Reload every task list buffer, as a command changed its tasks."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'task-list-mode)
        (with-demoted-errors "Could not reload the task list: %S"
          (revert-buffer))))))

(provide 'task)
;;; task.el ends here
