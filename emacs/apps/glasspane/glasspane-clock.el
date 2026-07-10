;;; glasspane-clock.el --- org-clock chronometer notification -*- lexical-binding: t; -*-

;; Tier 1 org integration: mirrors the running org clock to the companion
;; as an ongoing chronometer notification with Clock out / Switch task
;; buttons, and re-asserts it on reconnect so the phone's cache matches
;; reality after an Emacs restart.
;;
;; This is app-layer code — the core (jetpacs-surfaces) knows nothing about
;; org; it only carries the `notification:org-clock' surface this module
;; pushes through the generic senders.

;;; Code:

(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'org-clock)

(defun glasspane-clock-in-notification ()
  "Push the org-clock chronometer notification surface."
  (when (and (boundp 'org-clock-current-task) org-clock-current-task)
    (jetpacs-surface-push
     "notification:org-clock"
     (jetpacs-notification-spec
      :channel "clocking" :ongoing t :category "stopwatch"
      :chronometer `((base_ms . ,(truncate (* (float-time org-clock-start-time) 1000))))
      :body (list
             (jetpacs-text (format "Clocked in: %s" org-clock-current-task) 'title)
             (jetpacs-row
              (jetpacs-button "Clock out"
                           (jetpacs-action "org.clock.out" :when-offline "wake"))
              (jetpacs-button "Switch task"
                           (jetpacs-action "org.clock.switch" :when-offline "wake"))))))))

(defun glasspane-clock-out-notification ()
  "Remove the org-clock notification surface."
  (jetpacs-surface-remove "notification:org-clock"))

;; Closing the loop: a tap on "Clock out" arrives here as an event.action.
(jetpacs-defaction "org.clock.out"
                (lambda (&rest _) (when (org-clock-is-active) (org-clock-out))))
(jetpacs-defaction "org.clock.switch"
                ;; Placeholder: jump to the running task. Swap for a real
                ;; task-picker (e.g. org-clock-in to a recent task) when ready.
                (lambda (&rest _) (org-clock-goto)))
(jetpacs-defaction "org.clock.in-last"
                ;; The home-screen widget's "Clock In (Last)" button.
                (lambda (&rest _)
                  (condition-case err
                      (org-clock-in-last)
                    (error (message "Jetpacs clock-in-last failed: %s"
                                    (error-message-string err))))))

(add-hook 'org-clock-in-hook  #'glasspane-clock-in-notification)
(add-hook 'org-clock-out-hook #'glasspane-clock-out-notification)

;; On (re)connect, re-assert current clock state so the companion's cache
;; matches reality after an Emacs restart. (Runs after the revision snapshot
;; has been absorbed — see the -50 depth in jetpacs-surfaces.)
(add-hook 'jetpacs-connected-hook
          (lambda (_welcome)
            (when (and (fboundp 'org-clock-is-active) (org-clock-is-active))
              (glasspane-clock-in-notification))))

(provide 'glasspane-clock)
;;; glasspane-clock.el ends here
