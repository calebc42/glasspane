#!/usr/bin/env bash
# The ONE desktop command that re-provisions the tablet after any wipe.
#
#   tools/onboard-tablet.sh [SERIAL]
#
# SERIAL defaults to $ANDROID_SERIAL, then the tablet this tree has been
# developed against. Every phase is idempotent: re-running after a
# partial failure, or with nothing changed at all, is safe and cheap on
# the parts that already succeeded.
#
# See device/MANIFEST.md for the deploy contract (which repo path lands
# at which device path, by which transport) and device/emacs-init.el's
# header for what runs once org.gnu.emacs boots against it.
#
#   PHASE ssh-bootstrap (skipped once ssh already answers): launches
#     Termux, waits until Termux really is the FOCUSED app (checked with
#     dumpsys, not by asking a human to promise), then types ONE chained
#     command line into it:
#
#       pkg install -y openssh rsync && mkdir -p ~/.ssh && chmod 700 ...
#         && echo "<pubkey>" > ~/.ssh/authorized_keys && chmod 600 ...
#         && sshd
#
#     One line on purpose. The obvious alternative -- type `pkg install`,
#     sleep a fixed number of seconds, then type the rest -- races apt's
#     stdin: anything typed while the install is still running is eaten
#     by apt/dpkg instead of by the shell, and the bootstrap then fails
#     silently with no way to see it from here. A single `&&` chain has
#     no timing dependency at all: bash reads the whole line before
#     `pkg` ever starts, and each step only runs if the previous one
#     succeeded. The desktop then just polls ssh until it answers.
#
#   PHASE provision (over ssh, batch/key auth only -- no interactive
#     password ever): rsyncs the emacs/ elisp tree and the device/py/
#     fixtures into Termux's home (com.termux and org.gnu.emacs share a
#     uid on this device, so a Termux shell can read AND write
#     org.gnu.emacs's app-private storage directly -- no /sdcard, no
#     storage permission dialog anywhere in this flow), verifies pylsp
#     is on Termux's PATH (installing python-lsp-server if not), and
#     installs device/emacs-init.el as a HARNESS FILE next to
#     org.gnu.emacs's init.el plus a one-line `load' appended to that
#     init.el -- it never overwrites an init.el that already exists (see
#     tools/onboard-provision-remote.sh for why: the /sdcard daily
#     driver documented in docs/ONBOARDING-device.md lives in that exact
#     file, and clobbering it would silently uninstall it).
#
#   PHASE verify: prints what landed, where, and the on-device human
#     steps this flow cannot remove (launch the Companion, launch Emacs).
#
# Transport note: rsync -- not scp -- moves every file, including the
# two single ones. scp on OpenSSH 9+ speaks SFTP by default, which adds
# a dependency on Termux's sftp-server being present and configured for
# no benefit; rsync is already a hard requirement for the tree sync.
set -euo pipefail

# ---------------------------------------------------------------------
# 0. Args, paths, constants
# ---------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

usage() {
  cat >&2 <<EOF
usage: tools/onboard-tablet.sh [-h] [SERIAL]

  SERIAL   adb device serial (default: \$ANDROID_SERIAL, else
           192.168.1.181:42553 -- the tablet this tree targets)

Environment:
  ONBOARD_SSH_USER   ssh login name (default: \$(id -un); Termux's sshd
                     ignores the name, so this is cosmetic)
  ONBOARD_SSH_WAIT   seconds to wait for sshd after the typed bootstrap
                     (default 420 -- a cold 'pkg install' on a slow link
                     genuinely takes minutes)

Re-provisions the tablet from a clean wipe: Termux + sshd + this
desktop's ssh key, the elisp tree, the pylsp fixtures, and the device
Emacs's onboarding harness. Safe to re-run at any point.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

SERIAL="${1:-${ANDROID_SERIAL:-192.168.1.181:42553}}"
SSH_PORT=8022
SSH_USER="${ONBOARD_SSH_USER:-$(id -un)}"
SSH_WAIT_SECONDS="${ONBOARD_SSH_WAIT:-420}"

SCRATCH_DIR="$REPO_ROOT/tools/onboard-scratch"
DEFAULT_KEY="$HOME/.ssh/id_ed25519"
DEDICATED_KEY="$SCRATCH_DIR/onboard_ed25519"

log()  { printf '[onboard] %s\n' "$*" >&2; }
die()  { printf '[onboard] ERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\n[onboard] === %s ===\n' "$*" >&2; }

adbs() { adb -s "$SERIAL" "$@"; }

# ---------------------------------------------------------------------
# Preflight: local tools, device visible, the tree's own invariants
# ---------------------------------------------------------------------

for cmd in adb ssh rsync ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 \
    || die "'$cmd' not found on this desktop -- install it first"
done

adb -s "$SERIAL" get-state >/dev/null 2>&1 \
  || die "device '$SERIAL' not visible to adb (check: adb devices -l; or \
pass a serial: tools/onboard-tablet.sh <serial>)"

# device/MANIFEST.md's load-path design (one load-path entry for the
# tree root plus one per emacs/apps/*/) depends on no two .el files
# under emacs/ sharing a basename. It is a property of whatever the repo
# looks like right now, not something the manifest can freeze -- so
# re-check every run, before anything is copied.
dupes="$(cd "$REPO_ROOT" && find emacs -name '*.el' -exec basename {} \; \
         | sort | uniq -d)"
if [ -n "$dupes" ]; then
  die "duplicate .el basenames under emacs/ -- the device's load-path \
would silently shadow one of these; fix before onboarding: $dupes"
fi

# A stale .elc silently shadows the .el it was built from (the repo's own
# .gitignore says so). They are excluded from the sync below, but a
# .elc sitting in the worktree usually means an interactive session left
# one behind and the DESKTOP is loading it too -- worth saying out loud.
# `|| true' is load-bearing: `find | head -5' SIGPIPEs find once there
# are more than five hits, and under `set -o pipefail' that aborts the
# whole script at an assignment that was only ever meant to warn.
strays="$(cd "$REPO_ROOT" && find emacs -name '*.elc' | head -5 || true)"
[ -z "$strays" ] || log "note: .elc files present in emacs/ (NOT synced, \
excluded below), but they shadow their .el locally: $strays"

# ---------------------------------------------------------------------
# ssh key: this desktop's own id_ed25519, or a dedicated one generated
# under the repo's gitignored scratch dir. ed25519 specifically: its
# public key is one short line, and that line has to survive being TYPED
# through `adb shell input text'.
# ---------------------------------------------------------------------

resolve_ssh_key() {
  if [ -f "$DEFAULT_KEY" ] && [ -f "$DEFAULT_KEY.pub" ]; then
    SSH_KEY="$DEFAULT_KEY"
    log "using this desktop's existing key: $SSH_KEY.pub"
  else
    mkdir -p "$SCRATCH_DIR"
    chmod 700 "$SCRATCH_DIR"
    if [ ! -f "$DEDICATED_KEY" ]; then
      log "no ~/.ssh/id_ed25519 on this desktop -- generating a dedicated \
key under $SCRATCH_DIR for tablet onboarding only"
      ssh-keygen -t ed25519 -N '' -C "onboard-tablet" -f "$DEDICATED_KEY" -q
    fi
    SSH_KEY="$DEDICATED_KEY"
    log "using dedicated onboarding key: $SSH_KEY.pub"
  fi
  SSH_PUBKEY="$(tr -d '\r\n' < "$SSH_KEY.pub")"
  # The typed-bootstrap path cannot carry either of these: a single
  # quote breaks the device-shell quoting `type_text' relies on, and a
  # literal % is destroyed by Android's `input text' (it rewrites the
  # two-character sequence %s to a space, which is exactly how spaces
  # get through in the first place).
  case "$SSH_PUBKEY" in
    *"'"*) die "public key $SSH_KEY.pub contains a single quote -- the \
typed bootstrap cannot carry it; use a different key" ;;
    *'%'*) die "public key $SSH_KEY.pub contains a '%' -- Android's \
'input text' mangles it; use a different key or comment" ;;
    ssh-*) : ;;
    *) die "public key $SSH_KEY.pub does not look like an OpenSSH public \
key line" ;;
  esac
}

# ServerAliveInterval matters: PHASE provision's remote script may spend
# minutes inside `pip install python-lsp-server' with nothing on the
# wire, and adb's forwarded loopback is not a patient path.
SSH_OPTS=(-p "$SSH_PORT" -l "$SSH_USER"
          -o BatchMode=yes -o ConnectTimeout=5
          -o ServerAliveInterval=30 -o ServerAliveCountMax=20
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR)
RSYNC_RSH=""   # filled in once SSH_KEY is known

ssh_ready() {
  if [ -f "$PASS_FILE" ]; then
    ssh_auth_env ssh -o BatchMode=no -o PreferredAuthentications=password \
        "${SSH_OPTS[@]}" 127.0.0.1 true 2>/dev/null
  else
    ssh -i "$SSH_KEY" "${SSH_OPTS[@]}" 127.0.0.1 true 2>/dev/null
  fi
}
# Termux's openssh 10.5p1 ACCEPTED this desktop's ed25519 in the
# authorized_keys exchange and then denied the signed auth anyway
# (observed live 2026-08-13; byte-identical key file, correct modes,
# nothing in logcat).  The fallback: a generated password stored in the
# gitignored scratch dir, set once via the same typed-bootstrap channel
# (`passwd` + two typed lines), served to ssh through SSH_ASKPASS.
PASS_FILE="$SCRATCH_DIR/tablet-ssh-pass"
ASKPASS_FILE="$SCRATCH_DIR/askpass.sh"
ssh_auth_env() {
  if [ -f "$PASS_FILE" ]; then
    if [ ! -x "$ASKPASS_FILE" ]; then
      printf '#!/bin/sh\ncat "%s"\n' "$PASS_FILE" > "$ASKPASS_FILE"
      chmod 700 "$ASKPASS_FILE"
    fi
    SSH_ASKPASS="$ASKPASS_FILE" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}" "$@"
  else
    "$@"
  fi
}
# ssh takes the FIRST occurrence of an option, so the password arm's
# overrides go BEFORE SSH_OPTS (whose BatchMode=yes must lose there).
ssh_run() {
  if [ -f "$PASS_FILE" ]; then
    ssh_auth_env ssh -o BatchMode=no -o PreferredAuthentications=password \
        "${SSH_OPTS[@]}" 127.0.0.1 "$@"
  else
    ssh -i "$SSH_KEY" "${SSH_OPTS[@]}" 127.0.0.1 "$@"
  fi
}

wait_for_ssh_ready() {
  local budget="$1" delay=5 waited=0
  while [ "$waited" -lt "$budget" ]; do
    ssh_ready && return 0
    sleep "$delay"
    waited=$((waited + delay))
    if [ $((waited % 60)) -eq 0 ]; then
      log "  ...still waiting for sshd (${waited}s of ${budget}s)"
    fi
  done
  return 1
}

ensure_forward() {
  # adb forward does not survive a device reboot or an adb server
  # restart -- always re-establish, never assume a prior run's forward
  # still holds. Re-forwarding the same local port is idempotent.
  adbs forward "tcp:$SSH_PORT" "tcp:$SSH_PORT" >/dev/null
}

# ---------------------------------------------------------------------
# PHASE ssh-bootstrap -- only entered when ssh does not already answer.
#
# Every character typed goes through TWO layers: the device shell adb
# invokes to parse `input text ...', and then Termux's own shell reading
# what got typed. Single-quoting the payload for the FIRST layer makes
# &&, >, ", ~, / literal there; the SECOND layer is the one meant to
# interpret them. Two characters can never appear in a payload:
#   '  -- closes the first layer's quoting
#   %  -- Android's `input text' rewrites the sequence %s to a space,
#         which is the very mechanism spaces ride through, so any other
#         % is a live grenade (`printf "%s\n"' typed this way arrives as
#         `printf " \n"').
# Both are rejected, loudly, rather than escaped.
# ---------------------------------------------------------------------

TYPE_CHUNK=60   # chars per `input text'; long strings drop keystrokes

type_text() {   # type TEXT into the focused app. No ENTER.
  local text="$1" chunk
  case "$text" in
    *"'"*) die "type_text: payload contains a single quote: $text" ;;
    *'%'*) die "type_text: payload contains '%', which 'input text' \
mangles: $text" ;;
  esac
  while [ -n "$text" ]; do
    chunk="${text:0:$TYPE_CHUNK}"
    text="${text:$TYPE_CHUNK}"
    adbs shell "input text '${chunk// /%s}'" >/dev/null
    sleep 0.25
  done
}

type_enter() { adbs shell input keyevent 66 >/dev/null; sleep 0.5; }

termux_focused() {
  # dumpsys is readable by the adb `shell' uid on a stock build, so the
  # foreground app is a FACT this script can check rather than a promise
  # extracted from a human.
  #
  # `mCurrentFocus' ONLY -- not `mFocusedApp'. Measured on this tablet
  # with the notification shade pulled down:
  #   mCurrentFocus=Window{... NotificationShade}
  #   mFocusedApp=ActivityRecord{... com.termux/.app.TermuxActivity ...}
  # Both lines are present, one of them says com.termux, and typing
  # would go into the shade. mCurrentFocus is the window that actually
  # receives key events; mFocusedApp is only the activity behind
  # whatever is on top. Matching either would have been a live
  # false positive, so mFocusedApp is a fallback used only when
  # mCurrentFocus is missing entirely.
  #
  # dumpsys output is captured into a variable before grepping: `grep
  # -m1' closing the pipe early can SIGPIPE the producer, which under
  # `set -o pipefail' would read as "not focused".
  local dump cur
  dump="$(adbs shell dumpsys window 2>/dev/null || true)"
  cur="$(printf '%s\n' "$dump" | grep -m1 'mCurrentFocus=' || true)"
  if [ -z "$cur" ]; then
    cur="$(printf '%s\n' "$dump" | grep -m1 'mFocusedApp=' || true)"
  fi
  FOCUS_LINE="$cur"
  case "$cur" in
    *com.termux*) return 0 ;;
    *) return 1 ;;
  esac
}

wait_for_termux_focus() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    termux_focused && return 0
    sleep 2
  done
  return 1
}

phase_ssh_bootstrap() {
  log "launching Termux on $SERIAL"
  adbs shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 \
    >/dev/null 2>&1 || true

  if ! wait_for_termux_focus; then
    echo >&2
    echo "  Termux is not the focused app after 30s." >&2
    echo "  Focus reads: ${FOCUS_LINE:-<dumpsys gave nothing parseable>}" >&2
    echo >&2
    echo "  The next step TYPES A COMMAND into whatever has focus, so it" >&2
    echo "  will not proceed blind." >&2
    if [ -t 0 ]; then
      echo "  Open Termux by hand (dismiss any first-run popup so it sits" >&2
      echo "  at a bare shell prompt), then press Enter here." >&2
      read -r _ || true
      termux_focused || die "Termux still not focused -- aborting rather \
than typing a shell command into another app"
    else
      die "not running on a terminal, so there is nobody to ask -- open \
Termux on the tablet and re-run"
    fi
  fi
  log "Termux is focused"

  # ONE chained line. See the header for why this is not three lines
  # with sleeps between them.
  local bootstrap
  bootstrap="pkg install -y openssh rsync"
  bootstrap="$bootstrap && mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  bootstrap="$bootstrap && echo \"$SSH_PUBKEY\" > ~/.ssh/authorized_keys"
  bootstrap="$bootstrap && chmod 600 ~/.ssh/authorized_keys && sshd"

  log "typing the bootstrap chain (${#bootstrap} chars, \
${TYPE_CHUNK}-char chunks)"
  type_text "$bootstrap"
  type_enter
  log "typed; now polling ssh for up to ${SSH_WAIT_SECONDS}s while \
'pkg install' runs on the device"
}

# ---------------------------------------------------------------------
# PHASE provision -- over ssh, batch mode, the key just authorized.
# ---------------------------------------------------------------------

PROVISION_OUTPUT=""

# Excludes, in order of how badly each would hurt:
#   *.elc  -- a stale .elc SILENTLY SHADOWS the .el it was built from.
#             The repo gitignores them for exactly this reason; syncing
#             one to the device would ship a build of some older source.
#   .#*    -- Emacs lock files are DANGLING SYMLINKS (user@host:pid).
#   *~ #*# -- backups/autosaves; noise, and *~ can shadow nothing but
#             still confuses a directory listing on a tablet.
RSYNC_EXCLUDES=(--exclude='*.elc' --exclude='.#*' --exclude='*~'
                --exclude='#*#' --exclude='.git' --exclude='__pycache__')

phase_provision() {
  ssh_run "mkdir -p jetpacs/emacs jetpacs/py" \
    || die "could not mkdir ~/jetpacs/{emacs,py} on the device over ssh"

  # tar over ssh, NOT rsync: on this tablet's Termux (rsync 3.5.0,
  # openssh 10.5p1) the rsync RECEIVER gets EACCES on chdir into a
  # directory the same login shell enters fine -- no AVC logged, owner
  # and 0700 modes correct, `cd` over the identical ssh channel works.
  # Observed live 2026-08-13; not understood, not worth fighting: tar
  # rides the proven exec channel and the tree is small.  The --delete
  # mirror semantic is approximated by extracting over the previous
  # tree; stale .el files are swept by the remote provisioner's .elc
  # sweep companion below only for .elc -- a RENAMED .el lingers until
  # the next wipe, which the MANIFEST records as accepted.
  log "tar emacs/ -> Termux ~/jetpacs/emacs/ (whole tree, apps/ and \
spike/ included)"
  tar -C "$REPO_ROOT/emacs" --exclude='*.elc' --exclude='.#*' \
      --exclude='*~' --exclude='#*#' --exclude='__pycache__' -czf - . \
    | ssh_run 'tar -C jetpacs/emacs -xzf -' \
    || die "tar of emacs/ to the device failed"

  # NO --delete here, deliberately. ~/jetpacs/py is where
  # device/emacs-init.el points jetpacs-files-default-dir, i.e. it is a
  # directory the tablet's Files app can CREATE AND EDIT files in. A
  # mirror would delete the user's on-device work on the next run. Repo
  # files still win on name collision, so live.py stays authoritative.
  log "rsync device/py/ -> Termux ~/jetpacs/py/ (fixtures; no --delete, \
this is a live editing dir)"
  tar -C "$REPO_ROOT/device/py" -czf - . \
    | ssh_run 'tar -C jetpacs/py -xzf -' \
    || die "tar of device/py/ to the device failed"

  log "staging device/emacs-init.el + the remote provisioner"
  ssh_run 'cat > jetpacs/emacs-init.el' < "$REPO_ROOT/device/emacs-init.el" \
    || die "transfer of device/emacs-init.el to the device failed"
  ssh_run 'cat > .onboard-provision.sh' \
      < "$SCRIPT_DIR/onboard-provision-remote.sh" \
    || die "transfer of tools/onboard-provision-remote.sh failed"

  # The remote script's stderr streams straight through to ours as it
  # runs (log/die breadcrumbs); only its REPORT_ lines are on stdout,
  # and those are what phase_verify parses.
  log "running the remote provisioner (pip install can take minutes)"
  PROVISION_OUTPUT="$(ssh_run bash .onboard-provision.sh)" \
    || die "the remote provisioning script failed on the device -- its \
output above names the exact step"
}

report_field() {
  printf '%s\n' "$PROVISION_OUTPUT" | sed -n "s/^REPORT_${1}=//p" | tail -n1
}

# ---------------------------------------------------------------------
# PHASE verify
# ---------------------------------------------------------------------

phase_verify() {
  local elisp_dir py_dir elisp_files emacs_home harness init_dest \
        init_state pylsp_bin pylsp_version live_py_tail tail_note

  elisp_dir="$(report_field ELISP_DIR)"
  elisp_files="$(report_field ELISP_FILES)"
  py_dir="$(report_field PY_DIR)"
  emacs_home="$(report_field EMACS_HOME)"
  harness="$(report_field INIT_HARNESS)"
  init_dest="$(report_field INIT_DEST)"
  init_state="$(report_field INIT_STATE)"
  pylsp_bin="$(report_field PYLSP_BIN)"
  pylsp_version="$(report_field PYLSP_VERSION)"
  live_py_tail="$(report_field LIVE_PY_TAIL)"

  if [ "$live_py_tail" = "612e" ]; then
    tail_note=' (ok: ends "a.", no trailing newline)'
  else
    tail_note=' (EXPECTED 612e -- see the provisioner WARNING above)'
  fi

  echo >&2
  echo "==================== onboard-tablet: landed ====================" >&2
  printf '  device serial          : %s\n' "$SERIAL" >&2
  printf '  ssh                    : %s@127.0.0.1:%s (adb forward, key %s)\n' \
    "$SSH_USER" "$SSH_PORT" "$SSH_KEY" >&2
  printf '  Termux elisp tree      : %s  (%s .el files)\n' \
    "${elisp_dir:-?}" "${elisp_files:-?}" >&2
  printf '  Termux py fixtures     : %s\n' "${py_dir:-?}" >&2
  printf '  live.py tail bytes     : 0x%s%s\n' "${live_py_tail:-?}" \
    "$tail_note" >&2
  printf '  Android Emacs HOME     : %s  [probed this run, not assumed]\n' \
    "${emacs_home:-?}" >&2
  printf '  onboarding harness     : %s\n' "${harness:-?}" >&2
  printf '  device init.el         : %s  [%s]\n' \
    "${init_dest:-?}" "${init_state:-?}" >&2
  printf '  pylsp                  : %s\n' "${pylsp_bin:-?}" >&2
  printf '  pylsp --version        : %s\n' "${pylsp_version:-?}" >&2
  echo "===============================================================" >&2
  echo >&2
  echo "REMAINING (on the tablet, by hand -- no adb path to either" >&2
  echo "without a debuggable or rooted build):" >&2
  echo "  1. Launch the EBP Companion app (binds 127.0.0.1:8765)." >&2
  echo "  2. Launch, or force-stop and relaunch, org.gnu.emacs. It reads" >&2
  echo "     the init.el above, gains Termux's usr/bin on exec-path and" >&2
  echo "     PATH, loads the synced elisp, dials the Companion and pushes" >&2
  echo "     Files. Watch *Messages* for 'jetpacs-emacs-init:'" >&2
  echo "     breadcrumbs; M-x jetpacs-emacs-init-report dumps state, and" >&2
  echo "     M-x jetpacs-emacs-init-connect re-dials by hand." >&2
  echo >&2
}

# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------

resolve_ssh_key
RSYNC_RSH="ssh -i $SSH_KEY -p $SSH_PORT -l $SSH_USER -o BatchMode=yes \
-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
-o ServerAliveInterval=30 -o LogLevel=ERROR"
ensure_forward

step "PHASE ssh-bootstrap"
if ssh_ready; then
  log "ssh already reachable on 127.0.0.1:$SSH_PORT with $SSH_KEY -- skipping"
else
  phase_ssh_bootstrap
  ensure_forward
  wait_for_ssh_ready "$SSH_WAIT_SECONDS" || die "ssh still not reachable \
${SSH_WAIT_SECONDS}s after the typed bootstrap. This script cannot read \
Termux's terminal, so check the tablet directly -- the whole chain is on \
one line there, so the FIRST failing step is the last thing printed: did \
'pkg install -y openssh rsync' reach the network? did the echo land \
(cat ~/.ssh/authorized_keys)? did 'sshd' print an error? Fix on-device, \
then re-run -- this phase is skipped entirely once ssh answers."
  log "ssh reachable"
fi

step "PHASE provision"
phase_provision

step "PHASE verify"
phase_verify
