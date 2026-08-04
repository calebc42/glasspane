;;; jetpacs-chrome.el --- Chrome kit + per-surface screen stack -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-2 of docs/PLAN-jetpacs-apps.md (B6, reduced): composition over the
;; smoke-verified scaffold/multi_view/view.switched machinery — not a
;; framework.  `jetpacs-chrome-screen' is a titled scaffold with an
;; optional back arrow; `jetpacs-chrome-row' is the hub list-row the poc
;; screens all shared; the per-surface SCREEN STACK renders as ONE
;; multi_view surface whose views are the stacked screens (decision:
;; representation A — back is then the `view.switch' BUILTIN,
;; companion-local, zero-latency, works offline, REQUIRED in every app
;; profile; and SPEC 13.4's preserve-current-view rule applies for
;; free: background refreshes omit `current_view' and never yank the
;; user; only push/pop/reset name one).
;;
;; Stack↔device sync rides `jetpacs-shell-view-change-functions' — the
;; shell's own view.switched registration; the kit must NEVER
;; `jetpacs-defaction' that name (it would REPLACE the shell's global
;; handler).  A back-arrow tap truncates the Emacs stack silently: the
;; device already shows the right screen, dead upper views leave the
;; snapshot at the next natural push.  Offline back drift is BENIGN by
;; design — do not "fix" it by forcing current_view on reconnect.
;;
;; Snackbar note (H10): `jetpacs-shell-push' injects a queued snackbar
;; only into a scaffold ROOT; a multi-view spec has no :t, so
;; `jetpacs-shell-notify' on a stack surface degrades to the gated
;; toast.  Extending the shell to inject into the current view's
;; scaffold is out of scope here.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)

(defcustom jetpacs-chrome-max-screens 3
  "Screens one surface's stack renders (SPEC 22.3 bounds module work).
Every push re-renders EVERY screen — font-lock and a full render per
rendered-buffer screen — so an unbounded stack makes each refresh
O(depth) heavy work before one frame leaves.  The ROOT is pinned (it is
the registered fallback); eviction removes the screen ABOVE it, and the
lowest surviving screen back-targets the root.

Default 3, NOT the audit's 8, for a measured reason: `--build' renders
bottom-first so the ROOT spends the shared SPEC 4.5 budget first, and
the TOP screen — the one the user is looking at — gets the leftovers.
A two-pass top-first render would fix that but inverts the claim order
`jetpacs-claim-node-id' depends on (the first claimant keeps the stable
id, and today that is the root's literal, which later mints route
around).  Until that lands, a small bound is what keeps the starvation
bounded too."
  :type 'natnum :group 'jetpacs)

(defvar jetpacs-chrome--stacks (make-hash-table :test #'equal)
  "SURFACE id -> screen stack, a list of (ID . BUILDER), TOP FIRST.
BUILDER takes one argument BACK — a `view.switch' descriptor, or nil at
the stack bottom — and returns a root Node.")

(defvar jetpacs-chrome-dock-function nil
  "Function (SURFACE) -> Node or nil: a DOCKED bottom bar for SURFACE.
The docs/CHROME-VOCABULARY.md view switcher is chrome that persists —
authored on one root screen it vanishes on every drill and every other
surface.  When this is non-nil, `jetpacs-chrome--build' calls it once
per build and injects the returned node as the `bottom_bar' of every
stacked scaffold screen that does not author its own (a screen's own
bar always wins).  Returning nil docks nothing for that surface; a
signal or a non-node degrades the same way and never fails the build.
Every descriptor the dock ships must be a GLOBAL VERB or scoped to the
surfaces it appears on — it renders on every chrome surface.")

(defvar jetpacs-chrome-dock-items-function nil
  "Function (SURFACE) -> the dock's destinations as DATA, or nil.
The window-class-adaptive alternative to `jetpacs-chrome-dock-function\':
each item is a plist (:label STR :icon STR :on-tap DESCRIPTOR
\[:selected BOOL]), and chrome wears the SAME destinations as a
weighted bottom-bar row on compact and medium widths and as a
`jetpacs-navigation-rail\' in the scaffold\'s start-edge rail slot when
the width class is \"expanded\" (SPEC 20.1.1) — the
NavigationSuiteScaffold swap, driven by data instead of two authorings.
`jetpacs-chrome-dock-function\' (a finished node, always the bottom
bar) WINS when both are set — it is the raw-node override.  Degrades
like the node dock: a signal or malformed items cost the dock, never
the surface.")

;;;; Composition

(cl-defun jetpacs-chrome-screen (title body &key back actions fab drawer
                                       bottom-bar on-refresh floating-toolbar
                                       scaffold)
  "A titled scaffold screen.  BACK, when given, is the tap descriptor
of a leading arrow_back button (canonically `jetpacs-view-switch' of
the screen below).  The weight-1 title is what keeps trailing ACTIONS
at intrinsic width — the poc flex-trap lesson.  Validation rides the
builders: bad TITLE signals in `jetpacs-text', bad slots in
`jetpacs-scaffold', a bad BACK in `jetpacs-icon-button'.

SCAFFOLD is a plist appended verbatim to the `jetpacs-scaffold' call, for
the §17.6 members this function does not name individually — top-bar
styling, floating-toolbar styling, and whatever §17.6 grows next.
`jetpacs-scaffold' validates it, so an unknown member is an error there
rather than a silently dropped keyword here.

The optional slots follow docs/CHROME-VOCABULARY.md: DRAWER holds
app-level destinations (the Companion adds the opening hamburger on
the left by itself); BOTTOM-BAR is canonically a view switcher —
three to five sibling places, never document actions."
  (apply
   #'jetpacs-scaffold
   :top-bar (apply #'jetpacs-row
                   (append
                    (when back
                      (list (jetpacs-icon-button "arrow_back" back
                                                 :content-description "back")))
                    (list (jetpacs-with-attrs
                           (jetpacs-text title :style "title")
                           :weight 1))
                    actions
                    (list :align "center" :spacing 4)))
   :body body :fab fab :drawer drawer :bottom-bar bottom-bar
   :on-refresh on-refresh :floating-toolbar floating-toolbar
   ;; The M3-catalog sprint proved the styled bars end to end, so chrome
   ;; wears the REAL M3 small top bar by default now — proper insets,
   ;; the drawer hamburger as its navigationIcon, and a scroll behavior
   ;; one :scaffold keyword away.  cl-defun keeps the FIRST duplicate
   ;; keyword, so an explicit :top-bar-style in SCAFFOLD still wins.
   (append scaffold (list :top-bar-style "small"))))

(cl-defun jetpacs-chrome-row (title &key subtitle icon leading trailing
                                    on-tap on-long-tap key)
  "The hub list-row: card > row > [leading, weighted column, trailing].
TITLE/SUBTITLE are strings; ICON is a convenience when LEADING is nil;
TRAILING is one node or a list.  KEY (a SPEC 4.4 identifier) rides
`jetpacs-with-attrs' — like :weight, it is a universal attr the
container builders silently DROP as a trailing option, the exact poc
bug this port fixes."
  (let* ((middle (jetpacs-with-attrs
                  (apply #'jetpacs-column
                         (append (list (jetpacs-text title))
                                 (when subtitle
                                   (list (jetpacs-text subtitle
                                                       :style "caption")))
                                 (list :spacing 2)))
                  :weight 1))
         (lead (or leading (and icon (jetpacs-icon icon))))
         (trail (cond ((null trailing) nil)
                      ((jetpacs--root-node-p trailing) (list trailing))
                      (t trailing)))
         (card (jetpacs-card
                (list (apply #'jetpacs-row
                             (append (when lead (list lead))
                                     (list middle)
                                     trail
                                     (list :align "center" :spacing 12))))
                :on-tap on-tap :on-long-tap on-long-tap)))
    (if key (jetpacs-with-attrs card :key key) card)))

;;;; The per-surface screen stack (representation A: one multi_view)

(defun jetpacs-chrome--dock (surface)
  "SURFACE's dock node from `jetpacs-chrome-dock-function', or nil.
A signal or a non-node return degrades to nil — a broken dock builder
must cost the dock, never every chrome surface in the process."
  (when jetpacs-chrome-dock-function
    (condition-case err
        (let ((n (funcall jetpacs-chrome-dock-function surface)))
          (and (jetpacs--root-node-p n) n))
      (error (message "jetpacs-chrome: dock builder failed: %s"
                      (jetpacs--error-label err))
             nil))))

(defun jetpacs-chrome--dock-tab (item)
  "One bottom-bar destination from a dock ITEM plist.
The weighted text/tonal button row is the form the hub proved on
device; selection is the tonal fill."
  (jetpacs-with-attrs
   (jetpacs-button (plist-get item :label) (plist-get item :on-tap)
                   :icon (plist-get item :icon)
                   :variant (if (plist-get item :selected) "tonal" "text"))
   :weight 1))

(defun jetpacs-chrome--dock-slot (surface)
  "SURFACE\'s dock as (SLOT . NODE), or nil.
SLOT is `:bottom_bar\' — or `:rail\' when the destinations come from
`jetpacs-chrome-dock-items-function\' and the width class is expanded
\(SPEC 20.1.1): same places, worn on the start edge where M3 puts
navigation on a wide window.  The raw-node dock stays a bottom bar
unconditionally; only the data form can swap, because only data can be
re-authored into a rail."
  (if-let* ((node (jetpacs-chrome--dock surface)))
      (cons :bottom_bar node)
    (when jetpacs-chrome-dock-items-function
      (condition-case err
          (when-let* ((items (funcall jetpacs-chrome-dock-items-function
                                      surface))
                      ((consp items)))
            (if (equal (jetpacs-window-class :width) "expanded")
                (cons :rail
                      (jetpacs-navigation-rail
                       (mapcar (lambda (item)
                                 (jetpacs-rail-item
                                  (plist-get item :label)
                                  (plist-get item :icon)
                                  (plist-get item :on-tap)
                                  :selected (plist-get item :selected)))
                               items)
                       :arrangement "center"))
              (cons :bottom_bar
                    (apply #'jetpacs-row
                           (append (mapcar #'jetpacs-chrome--dock-tab items)
                                   (list :spacing 4))))))
        (error (message "jetpacs-chrome: dock items failed: %s"
                        (jetpacs--error-label err))
               nil)))))

(defvar jetpacs-chrome--window-classes nil
  "The (WIDTH-CLASS . HEIGHT-CLASS) chrome last authored for.")

(defun jetpacs-chrome--on-window-changed (_client _window)
  "Re-push every chrome surface when the size CLASS flips (SPEC 20.1.1).
Geometry ticks inside one class cost nothing; a flip re-pushes each
chrome surface (debounced by the shell) so the dock swaps forms and
every screen re-authors for the new class."
  (let ((classes (cons (jetpacs-window-class :width)
                       (jetpacs-window-class :height))))
    (unless (equal classes jetpacs-chrome--window-classes)
      (setq jetpacs-chrome--window-classes classes)
      (maphash (lambda (surface _stack)
                 (jetpacs-shell--schedule-repush surface))
               jetpacs-chrome--stacks))))

(defun jetpacs-chrome--on-ready (client)
  "Seed the class memo and attach the window hook.
The welcome mirrors the geometry before ready runs (SPEC 20.1.1), so
seeding here means the first `window.changed\' re-pushes only on a REAL
class flip — not on the notification that merely repeats the welcome."
  (setq jetpacs-chrome--window-classes
        (cons (jetpacs-window-class :width) (jetpacs-window-class :height)))
  (cl-pushnew #'jetpacs-chrome--on-window-changed
              (ebp-client-window-changed-functions client)))

(defun jetpacs-chrome--error-screen (surface id back err)
  "A Core-Node-Set stand-in for screen ID whose builder failed with ERR.
ERR is a signal object or a bare error SYMBOL.  Core Node Set ONLY:
SPEC 16.2 makes `text', `column' and `button' types every `app' profile
MUST carry (SPEC 10.2), and every builder called here is total for
these arguments — the degrade path must not be able to fail the gate it
exists to survive.  Keeps BACK whenever a screen is below: the broken
screen is normally the one just pushed, hence on display, and
`view.switch' is companion-local — the one escape that does not need
the crashed Emacs side to answer.  The finished card is run through the
per-view gate and retried WITHOUT the button if it fails: SPEC.md
requires `view.switch' of every conforming app profile, but GATE 1
checks the LIVE one, and the degrade path must not out-fail the failure
it degrades.  SPEC 23.3: the body is the error SYMBOL, never
`error-message-string' — that embeds the offending datum, and SPEC 13.2
has the Companion PERSIST this text on the device."
  (let ((card (lambda (b)
                (apply #'jetpacs-column
                       (append
                        (list (jetpacs-text
                               (format "Screen %s failed to build" id)
                               :style "title")
                              (jetpacs-text (jetpacs--error-label err)
                                            :style "body"))
                        (when b (list (jetpacs-button "Back" b)))
                        (list :spacing 8))))))
    (or (ignore-errors
          (let ((n (funcall card back)))
            (jetpacs-chrome--gate-view surface n)
            n))
        (funcall card nil))))

(defun jetpacs-chrome--gate-view (surface node)
  "Signal when NODE uses what SURFACE's LIVE session does not allow.
A per-view pre-run of the shell's GATE 1 (node types, builtins,
features) and GATE 4 (the ratified amendments — an ungranted `wake'
descriptor or synchronized editor), so the failure costs its own screen
instead of making the whole surface unpushable for the process
lifetime.  No client (offline render, tests) is a no-op; a missing
profile skips only GATE 1 — `--gate-spec' would signal its own
\='no profile\=' error for every view, strictly worse than one
push-level failure.  The authority remains the shell's gates on the
assembled spec; this is the same check run earlier, per screen."
  (when-let* ((client (jetpacs-client)))
    (when (plist-get (ebp-client-profiles client)
                     (jetpacs-shell--surface-target surface))
      (jetpacs-shell--gate-spec client surface node nil))
    (jetpacs-shell--gate-amendments client node)))

(defun jetpacs-chrome--claim-screen-ids (node seen)
  "Check NODE's ids against SEEN (prior screens) and record them.
Signals `jetpacs-duplicate-node-id' when NODE repeats an id an earlier
screen emitted, or repeats one within itself — SPEC 16.1 scopes
uniqueness to the whole document and the Companion answers a duplicate
with 1201 for the ENTIRE update.  On success the ids are added to SEEN
and SEEDED into `jetpacs-node-id-claims' (as t, never clobbering a
minter's count), so a LATER screen's minted id routes around an earlier
screen's literal.  Minted ids are already unique by construction — the
signal here means a LITERAL authored id collided, and the caller turns
it into that screen's error card."
  (let ((ids (jetpacs--collect-node-ids node nil))
        (mine (make-hash-table :test #'equal)))
    (dolist (id ids)
      (when (or (gethash id seen) (gethash id mine))
        (signal 'jetpacs-duplicate-node-id (list id)))
      (puthash id t mine))
    (dolist (id ids)
      (puthash id t seen)
      (when jetpacs-node-id-claims
        (unless (gethash id jetpacs-node-id-claims)
          (puthash id t jetpacs-node-id-claims))))))

(defun jetpacs-chrome--build (surface)
  "The registered root builder: the stack as one multi_view.
Walks bottom-first so each screen's BACK targets the one below it;
`initial_view' is the stack TOP, so SPEC 13.4's new-surface and
vanished-view fallbacks land where Emacs believes the user is.  Signals
on an empty/missing stack — the shell degrades that to its error spec.

A screen whose builder signals, returns a non-node, or emits what the
session does not allow costs ITS OWN view and nothing else.  Degrading
the whole spec instead would drop `views', which nils `current_view' at
the shell's GATE 2 and makes the Companion clear the retained view
\(SPEC 13.4): the back affordance and the navigation state would die
together, on every rebuild."
  (let ((stack (gethash surface jetpacs-chrome--stacks)))
    (unless stack
      (error "jetpacs-chrome: no chrome stack for %s" surface))
    (jetpacs-buffer-with-budget
     (let ((seen (make-hash-table :test #'equal))
           (dock (jetpacs-chrome--dock-slot surface))
           views prev-id)
      (dolist (entry (reverse stack))
        (let* ((id (car entry))
               (back (and prev-id (jetpacs-view-switch prev-id)))
               (budget jetpacs-buffer-budget)
               (spans (car-safe budget))
               (bytes (cdr-safe budget))
               (fail nil)
               (node (condition-case err
                         (let ((n (funcall (cdr entry) back)))
                           ;; The dock joins BEFORE the gates so what is
                           ;; checked is what ships; `append' copies, so
                           ;; the builder's own node is never mutated.
                           (when (and dock (jetpacs--root-node-p n)
                                      (equal (plist-get n :t) "scaffold")
                                      (not (plist-member n (car dock))))
                             (setq n (append n (list (car dock) (cdr dock)))))
                           (jetpacs-chrome--gate-view surface n)
                           (jetpacs-chrome--claim-screen-ids n seen)
                           n)
                       (error (setq fail err) nil))))
          (unless (or fail (jetpacs--root-node-p node))
            (setq fail 'wrong-type-argument))
          (when fail
            ;; The dead screen SPENT budget it never ships; hand it back,
            ;; or one broken screen silently truncates the healthy ones
            ;; built after it (SPEC 4.5 counts per SurfaceSpec).
            (when (consp budget)
              (setcar budget spans)
              (setcdr budget bytes))
            (message "jetpacs-chrome: screen %s failed to build: %s"
                     id (jetpacs--error-label fail))
            (setq node (jetpacs-chrome--error-screen surface id back fail)))
          (push (cons id node) views)
          (setq prev-id id)))
      (jetpacs-multi-view (nreverse views) (caar stack))))))

(cl-defun jetpacs-chrome-define-root (surface-or-owner id builder
                                                       &key required)
  "Define SURFACE's chrome root screen; re-evaluation RESETS the stack.
Call under `with-jetpacs-owner' — the shell records the owner and
re-binds it around every build.  Returns the surface id."
  (let ((surface (jetpacs-shell--resolve-surface surface-or-owner)))
    (jetpacs--check-identifier id "screen id")
    (puthash surface (list (cons id builder)) jetpacs-chrome--stacks)
    (jetpacs-shell-define-root surface
                               (lambda () (jetpacs-chrome--build surface))
                               :required required)
    (jetpacs-chrome--claim-drill-host surface)
    surface))

(defun jetpacs-chrome--stack-insert (surface id builder)
  "Validate and insert (ID . BUILDER) at SURFACE's stack top.
An ID already on the stack TRUNCATES to that entry and replaces its
builder — re-entrant navigation; without this `jetpacs-multi-view'
signals a duplicate view id and the surface degrades to the error
screen.  Pure stack mutation: no push.

Returns a nullary UNDO thunk restoring the prior stack.  Two rules make
the undo exact.  (a) The replace branch CONSES a fresh entry instead of
`setcdr'-ing the found one in place: that cons is SHARED with the saved
stack, so an in-place replace would survive any restore of it and a
rolled-back entry would keep poisoning every later build.  (b) The undo
restores only while the stored stack is still `eq' to the one this
insert produced — a deferred rollback must never discard a navigation
that happened in between."
  (let ((stack (gethash surface jetpacs-chrome--stacks)))
    (unless stack
      (error "jetpacs-chrome: no chrome stack for %s" surface))
    (jetpacs--check-identifier id "screen id")
    (let* ((tail (cl-member id stack :key #'car :test #'equal))
           (new (cons (cons id builder) (if tail (cdr tail) stack)))
           ;; The bound applies HERE, before the single puthash, so the
           ;; undo thunk's `eq' guard sees the same object it stored — an
           ;; eviction done as a second write would defeat every rollback.
           (new (if (> (length new) jetpacs-chrome-max-screens)
                    (append (seq-take new (1- jetpacs-chrome-max-screens))
                            (last new))
                  new)))
      (puthash surface new jetpacs-chrome--stacks)
      (lambda ()
        (when (eq new (gethash surface jetpacs-chrome--stacks))
          (puthash surface stack jetpacs-chrome--stacks))))))

(defun jetpacs-chrome--push-or-undo (surface view undo)
  "Push SURFACE forcing VIEW; a signalling push runs UNDO and re-raises.
The transactional half of the kit's design rule: the reply must
describe the MODEL mutation, and an ADDITION is committed only if the
surface stays renderable — `jetpacs-chrome--build' rebuilds the whole
stack on every push, so an entry that failed a gate would otherwise
refuse every later push of the surface for the process lifetime."
  (condition-case err
      (jetpacs-shell-push surface :current-view view)
    (error
     (funcall undo)
     ;; `jetpacs-shell-push' consumed SURFACE's queued repush entry
     ;; (--drop-pending) BEFORE the gate signalled; without this line a
     ;; rolled-back navigation also silently costs an unrelated pending
     ;; re-render.  No-op while disconnected, which is correct.
     (jetpacs-shell--schedule-repush surface)
     (signal (car err) (cdr err)))))

(defun jetpacs-chrome--push-quietly (surface view)
  "Push SURFACE forcing VIEW; a signalling push logs and returns nil.
The commit-unconditionally half of the design rule: a REMOVAL (pop,
reset) can only shrink the stack, so it cannot make the surface less
renderable than it was — the mutation is kept, the presentation loss is
logged, and the requeued push renders the truncated stack."
  (condition-case err
      (jetpacs-shell-push surface :current-view view)
    (error
     (jetpacs-shell--schedule-repush surface)
     ;; VIEW and SURFACE are app-minted wire ids already on the wire —
     ;; naming them is not a SPEC 23.3 exposure, and a bare error label
     ;; alone ("error") locates nothing.
     (message "jetpacs-chrome: push of %s (view %s) failed: %s"
              surface view (jetpacs--error-label err))
     nil)))

(defun jetpacs-chrome-push-screen (surface-or-owner id builder)
  "Push screen ID onto SURFACE's stack and navigate to it.
ID is a SPEC 4.4 identifier, validated BEFORE any mutation — mint
dynamic ids from buffer names/paths through `jetpacs-wire-id'.  The
only navigation-forcing push shape (`:current-view').  From an action
handler pass (plist-get params :surface): the wire names the surface the
user actually tapped, which is not necessarily this owner's primary one.
\(`jetpacs--dispatch' binds the registering owner now, so the zero-arg
default is no longer simply wrong — it is merely a different surface.)

TRANSACTIONAL: a push the gates refuse rolls the stack back and
re-signals, so a screen that cannot render never enters the model — an
entry that failed a gate would otherwise refuse EVERY later push of the
surface (`jetpacs-chrome--build' rebuilds the stack each time).  A
deferred caller (`jetpacs-flow-continue') must wrap in `condition-case'
or the re-signal dies in a timer.  Returns the claimed revision, or nil
while disconnected — nil is NOT failure: the mutation is kept and the
next successful push renders it.  Never retry-loop on nil.  (The W10
sender ceiling does NOT yield nil here: `ebp-client--surface-request'
claims and returns the revision before the ceiling can refuse; the
refused frame is retried by the B8 repush.)"
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (undo (jetpacs-chrome--stack-insert surface id builder)))
    (jetpacs-chrome--push-or-undo surface id undo)))

(defun jetpacs-chrome-pop-screen (surface-or-owner)
  "Pop SURFACE's stack and navigate to the screen below (Emacs-side
back — a completed flow returning to its hub; the on-screen arrow never
calls this).  At the root: idempotent no-op returning nil."
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (stack (gethash surface jetpacs-chrome--stacks)))
    (when (cdr stack)
      (puthash surface (cdr stack) jetpacs-chrome--stacks)
      (jetpacs-chrome--push-quietly surface (caar (cdr stack))))))

(defun jetpacs-chrome-reset-screens (surface-or-owner)
  "Truncate SURFACE's stack to its root and navigate there.
Keeps the root cons, so the registered builder survives; the push
doubles as a hub refresh."
  (let* ((surface (jetpacs-shell--resolve-surface surface-or-owner))
         (stack (gethash surface jetpacs-chrome--stacks)))
    (when stack
      (let ((root (last stack)))
        (puthash surface root jetpacs-chrome--stacks)
        (jetpacs-chrome--push-quietly surface (caar root))))))

(defun jetpacs-chrome-stack (surface-or-owner)
  "SURFACE's screen ids, top first, or nil (read-only)."
  (mapcar #'car (gethash (jetpacs-shell--resolve-surface surface-or-owner)
                         jetpacs-chrome--stacks)))

(defun jetpacs-chrome-remove (surface-or-owner)
  "Drop SURFACE's stack and tombstone the surface."
  (let ((surface (jetpacs-shell--resolve-surface surface-or-owner)))
    (remhash surface jetpacs-chrome--stacks)
    (jetpacs-shell-remove-root surface)))

;;;; Stack <-> device sync (the shell's view.switched, subscribed)

(defun jetpacs-chrome--on-view-switched (surface view)
  "Truncate SURFACE's stack to VIEW (a Companion-local back).
Runs INSIDE the dispatch extent under the no-prompts regime, so it is
two when-lets and nothing else — an error here would flip the whole
view.switched reply to rejected.  NO push: the device already shows the
right screen; dead upper views leave the snapshot at the next natural
push."
  (when-let* ((stack (gethash surface jetpacs-chrome--stacks)))
    (when-let* ((tail (cl-member view stack :key #'car :test #'equal)))
      (puthash surface tail jetpacs-chrome--stacks))))

(add-hook 'jetpacs-shell-view-change-functions
          #'jetpacs-chrome--on-view-switched)

;;;; The navigate drill seam (integration C7) and teardown (C8)

(defun jetpacs-chrome--drill (surface builder label)
  "The `jetpacs-navigate-drill-function' implementation.
LABEL is display text (a hostile buffer name) — the wire id is minted
\(B5), so an identical LABEL mints an identical id and the stack-insert
truncate-and-replace gives repeat-drill replace-top semantics for free.
The presenting push is DEFERRED: `jetpacs-shell-push' signals on gate
failure, and a synchronous signal inside a handler after the stack
mutated would answer rejected for an effect that happened."
  (if (null (gethash surface jetpacs-chrome--stacks))
      ;; A stackless surface — torn down, or never chrome's.  This is an
      ;; already-live signal for the PRIMARY surface after any teardown;
      ;; the corrected sweep extends it to secondaries.  The seam
      ;; contract says the host never signals: refuse with nil and let
      ;; the navigator run its documented degrade.
      (progn (message "jetpacs-chrome: no chrome stack for %s; drill \
refused" surface)
             nil)
    (jetpacs-chrome--drill-1 surface builder label)))

(defun jetpacs-chrome--drill-1 (surface builder label)
  "The live half of `jetpacs-chrome--drill' — SURFACE has a stack."
  (let* ((id (jetpacs-wire-id "drill" label))
         (undo (jetpacs-chrome--stack-insert
                surface id
                (lambda (back)
                  ;; No budget wrap HERE: `jetpacs-chrome--build' wraps the
                  ;; whole multi_view once, because SPEC 4.5 counts across
                  ;; the SurfaceSpec and the stack puts N screens in one.
                  (jetpacs-chrome-screen
                   label
                   (apply #'jetpacs-column (funcall builder))
                   :back back)))))
    (run-at-time 0 nil
                 (lambda ()
                   (condition-case err
                       (jetpacs-shell-push surface :current-view id)
                     (error
                      ;; Deferring dodged the rejected-flattening; it does
                      ;; NOT dodge the poison — the failed entry would be
                      ;; rebuilt by every later push.  Roll it back (the
                      ;; undo no-ops if navigation moved the stack since)
                      ;; and let the requeued push render the prior state.
                      (funcall undo)
                      (jetpacs-shell--schedule-repush surface)
                      (message "jetpacs-chrome: drill push of %s (view %s) \
failed: %s" surface id (jetpacs--error-label err))))))
    t))

(defvar jetpacs-navigate-drill-function)
(declare-function jetpacs-navigate-register-drill-host "jetpacs-navigate"
                  (surface fn))
(declare-function jetpacs-navigate-drill-host "jetpacs-navigate" (surface))
(defvar jetpacs-navigate--drill-hosts)

(defun jetpacs-chrome--claim-drill-host (surface)
  "Claim SURFACE's drill host for the chrome stack — ONLY when the slot
is free or already chrome's.  Re-evaluating a chrome root (the
documented live-reload path) must not clobber a Tier-1's registered
host: the guard is what makes per-surface registration deterministic
under re-evaluation, not just under require order."
  (when (fboundp 'jetpacs-navigate-register-drill-host)
    (let ((cur (gethash surface jetpacs-navigate--drill-hosts)))
      (when (or (null cur) (eq cur #'jetpacs-chrome--drill))
        (jetpacs-navigate-register-drill-host
         surface #'jetpacs-chrome--drill)))))

(with-eval-after-load 'jetpacs-navigate
  ;; The GLOBAL seam stays as the backfill for chrome roots defined
  ;; before navigate loaded — sentinel-guarded so a Tier-1's own global
  ;; host survives require order.
  (unless jetpacs-navigate-drill-function
    (setq jetpacs-navigate-drill-function #'jetpacs-chrome--drill)))

(defun jetpacs-chrome--on-teardown (_owner)
  "Drop the stack of every surface the teardown swept — stacks ONLY:
`jetpacs-teardown-owner' already tombstones via remove-root, so calling
`jetpacs-chrome-remove' here would double-tombstone.  Reads
`jetpacs-teardown-surfaces', NOT `jetpacs-shell--owner-surfaces': the
owner's claims are gone by now and recomputing sees only the D1
primary, leaking every secondary surface's stack — the leaked stack
pins builder closures and answers a later drill with false success."
  (dolist (surface jetpacs-teardown-surfaces)
    (remhash surface jetpacs-chrome--stacks)))

(add-hook 'jetpacs-teardown-functions #'jetpacs-chrome--on-teardown)

(provide 'jetpacs-chrome)
;;; jetpacs-chrome.el ends here
