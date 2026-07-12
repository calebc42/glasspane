;;; glasspane-capture.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-ui)

(defun glasspane-ui--push-widget ()
  "Push the `widget:agenda' surface backing the home-screen widget.
A multi-view spec: \"today\" (the day agenda) plus one view per
`glasspane-org-custom-agendas' entry. The widget's header selector
switches between them companion-side from cache, so it works offline.
View keys are interned because `json-serialize' requires symbol keys."
  (let ((views
         (cons
          (cons 'today
                `((title . ,(format-time-string "Agenda · %a %b %d"))
                  (items . ,(vconcat (glasspane-ui--widget-items)))))
          (mapcar (lambda (ca)
                    (cons (intern (car ca))
                          `((title . ,(car ca))
                            (items . ,(vconcat (glasspane-ui--widget-query-items
                                                (cdr ca)))))))
                  glasspane-org-custom-agendas))))
    (unless (equal views glasspane-ui--last-widget)
      (setq glasspane-ui--last-widget views)
      (jetpacs-surface-push
       "widget:agenda"
       ;; header_action: the widget header's "+" is server-driven chrome
       ;; (SPEC §4) — the companion hardcodes nothing; this is where the
       ;; org-capture opinion lives now.
       `((views . ,views)
         (initial_view . "today")
         (header_action . ,(jetpacs-action "org.capture.show"
                                        :when-offline "queue")))))))

(defvar glasspane-ui--capture-tile-pushed nil
  "Non-nil once the static capture tile spec has been pushed this session.")

(defun glasspane-ui--push-capture-tile ()
  "Push the `tile:custom1' Quick Settings tile: one-tap org capture.
The foundation's CaptureTileService is gone (it hardcoded an org
action); the tile is now composed here and rendered by the companion's
blank tile slots. Static content — pushed once per session; the
companion persists it, and the user adds the tile to the shade from
the tile picker."
  (unless glasspane-ui--capture-tile-pushed
    (setq glasspane-ui--capture-tile-pushed t)
    (jetpacs-surface-push
     "tile:custom1"
     (jetpacs-tile "Capture" :icon "add" :state "active"
                :on-tap (jetpacs-action "org.capture.show"
                                     :when-offline "queue")
                ;; Capture needs a keyboard, so the tap opens the app.
                :in-app t))))

;; App opinion: dialogs present as bottom sheets (SPEC §7 `dialog_style') —
;; capture templates, pickers, and the whole minibuffer bridge read native
;; on mobile. Per-user override lives in Settings → Appearance; old
;; companions ignore the style and center the dialog.
(setq jetpacs-dialog-style "sheet")

;; Capture is this app's signature affordance: the default FAB on every
;; Glasspane tab view that doesn't define its own — and, registered
;; per-app, never on a coexisting app's views.
(jetpacs-apps-set-default-fab "glasspane"
                           (lambda (_name)
                             (jetpacs-fab "add" :label "Capture"
                                       :on-tap (jetpacs-action "org.capture.show"))))

;; ─── Capture Dialog ──────────────────────────────────────────────────────────

(defvar glasspane-ui--shared-text nil
  "Body text shared from another app, pending the next capture submit.")

(defvar glasspane-ui--shared-subject nil
  "Subject shared from another app; seeds the capture Headline field.")

(defun glasspane-ui-show-capture-dialog ()
  (condition-case err
      (let* ((templates (glasspane-org--capture-templates))
             (template-buttons
              (mapcar (lambda (t-info)
                        (jetpacs-button
                         (alist-get 'description t-info)
                         (jetpacs-action "org.capture.select"
                                      :args `((key . ,(alist-get 'key t-info))))
                         :variant "outlined"))
                      templates))
             (dialog-body
              (apply #'jetpacs-column
                     (jetpacs-text "Quick Capture" 'title)
                     (jetpacs-text "Select a template:" 'caption)
                     (append
                      ;; Shared-in content shows a preview so the user knows
                      ;; what this capture will carry.
                      (when glasspane-ui--shared-text
                        (list (jetpacs-card
                               (list (jetpacs-text
                                      (truncate-string-to-width
                                       glasspane-ui--shared-text 200 nil nil "…")
                                      'caption)))))
                      template-buttons
                      (list (jetpacs-button "Cancel"
                                         (jetpacs-action "org.capture.cancel")
                                         :variant "text"))))))
        (jetpacs-send-dialog dialog-body))
    (error
     (message "Jetpacs capture dialog error: %s" (error-message-string err)))))

(defun glasspane-ui-show-capture-form (template-key)
  ;; Forget values from any previous capture so they can't leak into
  ;; this submit (`jetpacs--ui-state' is global and persistent).
  (jetpacs-ui-state-clear "cap-")
  ;; A shared-in subject pre-fills the Headline field; it must also land
  ;; in UI state, since state.changed only fires for edits the user makes.
  (when glasspane-ui--shared-subject
    (jetpacs-ui-state-put "cap-Headline" glasspane-ui--shared-subject))
  (condition-case err
      (let* ((templates (glasspane-org--capture-templates))
             (tmpl (cl-find-if
                    (lambda (t-info) (equal (alist-get 'key t-info) template-key))
                    templates))
             (prompts (append (alist-get 'prompts tmpl) nil)) ;; coerce vector to list
             (inputs (mapcar (lambda (p)
                               (jetpacs-text-input
                                (format "cap-%s" p) :label p
                                :value (and (equal p "Headline")
                                            glasspane-ui--shared-subject)))
                             prompts))
             (dialog-body
              (apply #'jetpacs-column
                     (jetpacs-text (format "Capture: %s" (alist-get 'description tmpl)) 'title)
                     (append inputs
                             (list
                              (jetpacs-row
                               (jetpacs-button "Cancel"
                                            (jetpacs-action "org.capture.cancel")
                                            :variant "text")
                               (jetpacs-button "Capture"
                                            (jetpacs-action "org.capture.submit"
                                                         :args `((key . ,template-key))))))))))
        (jetpacs-send-dialog dialog-body))
    (error
     (message "Jetpacs capture form error: %s" (error-message-string err)))))

(jetpacs-defaction "org.capture.show"
  (lambda (_ _)
    (glasspane-ui-show-capture-dialog)))

(jetpacs-defaction "org.capture.select"
  (lambda (args _)
    (glasspane-ui-show-capture-form (alist-get 'key args))))

(jetpacs-defaction "org.capture.cancel"
  (lambda (_ _)
    (setq glasspane-ui--shared-text nil
          glasspane-ui--shared-subject nil)
    (jetpacs-dismiss-dialog)))

(defun glasspane-ui--on-share (args _payload)
  "Android share sheet → capture: stash the text/subject, open the picker.
Queued offline, so sharing works with Emacs dead — the capture dialog
appears on the next replay."
  (let ((text (alist-get 'text args))
        (subject (alist-get 'subject args)))
    (setq glasspane-ui--shared-text
          (and (stringp text) (not (string-empty-p (string-trim text)))
               (string-trim text))
          glasspane-ui--shared-subject
          (and (stringp subject) (not (string-empty-p (string-trim subject)))
               (string-trim subject)))
    ;; A share with only a subject still captures: use it as the text too.
    (unless glasspane-ui--shared-text
      (setq glasspane-ui--shared-text glasspane-ui--shared-subject))
    (glasspane-ui-show-capture-dialog)))

;; The companion's share sheet emits the app-agnostic `share.text'; this
;; app answers it with org capture.  The old app-specific id stays
;; registered so shares queued by a pre-rename companion still replay.
(jetpacs-defaction "share.text" #'glasspane-ui--on-share)

(jetpacs-defaction "org.capture.share" #'glasspane-ui--on-share)

(jetpacs-defaction "org.capture.submit"
  (lambda (args _)
    (let ((key (alist-get 'key args)))
      (condition-case err
          (let* ((templates (glasspane-org--capture-templates))
                 (tmpl (cl-find-if
                        (lambda (t-info) (equal (alist-get 'key t-info) key))
                        templates))
                 (prompts (append (alist-get 'prompts tmpl) nil))
                 ;; Field values arrived earlier as state.changed events and
                 ;; were recorded into `jetpacs--ui-state' by jetpacs-surfaces.
                 (values (mapcar
                          (lambda (p)
                            (let ((v (jetpacs-ui-state (format "cap-%s" p))))
                              (cons p (if (stringp v) v ""))))
                          prompts)))
            (glasspane-org--do-capture key values glasspane-ui--shared-text)
            (setq glasspane-ui--shared-text nil
                  glasspane-ui--shared-subject nil)
            (glasspane-org-cache-invalidate)
            (jetpacs-ui-state-clear "cap-")
            (jetpacs-shell-notify "Captured ✓")
            (jetpacs-dismiss-dialog)
            (jetpacs-shell-push))
        (error
         (message "Jetpacs capture submit error: %s" (error-message-string err))
         (setq glasspane-ui--shared-text nil
               glasspane-ui--shared-subject nil)
         (jetpacs-ui-state-clear "cap-")
         (jetpacs-dismiss-dialog))))))

(provide 'glasspane-capture)
