#!/usr/bin/env bash
# The one desktop command that installs, audits, or removes Jetpacs on a
# tablet. It establishes one private Emacs/Termux HOME before normal init
# loading, then independently selects a Vault for user content. The old
# /sdcard daily-driver + app-private harness dual install is retired.
#
#   tools/onboard-tablet.sh [--vault shared|emacs|termux]
#                            [--emacs-home emacs|termux|remote] [SERIAL]
#
#   PHASE ssh-bootstrap (skipped once ssh already answers): launches
#     Termux, waits until Termux really is the FOCUSED app (checked with
#     dumpsys, not by asking a human to promise), then types ONE chained
#     command line into it:
#
#       pkg install -y openssh && mkdir -p ~/.ssh && chmod 700 ...
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
#   PHASE provision stages one payload through Termux, then the device-side
#     installer puts it below the selected private HOME's .emacs.d/jetpacs.
#     Local Emacs HOME keeps Android Emacs HOME; Termux-shared redirects it.
#     Existing init content is preserved. The Vault never contains Jetpacs
#     internals merely because it is /sdcard.
#
#   PHASE verify: prints what landed, where, and the on-device human
#     steps this flow cannot remove (launch the Companion, launch Emacs).
#
# Shared Vault (/sdcard) is the recommended default for device-local Org Mode:
# it survives uninstalling Emacs or Termux, at the cost of being readable by
# any app granted Android's "All files" access. Advanced choices keep the
# Vault in Local Emacs HOME or Termux HOME. A separate Advanced choice can use
# Termux as Emacs's Unix HOME or hand the session to Remote Emacs.
set -euo pipefail

# ---------------------------------------------------------------------
# 0. Args, paths, constants
# ---------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

usage() {
  cat >&2 <<EOF
usage: tools/onboard-tablet.sh [OPTIONS] [SERIAL]

  --vault MODE      shared | emacs | termux
                    shared: /sdcard (recommended for Org Mode workflows)
                    emacs: user content in Local Emacs private home
                    termux: user content in Termux private home
  --emacs-home MODE emacs | termux | remote
                    emacs: Local Emacs Unix HOME (default)
                    termux: Termux-shared Unix HOME
                    remote: do not configure Android Emacs
  --home MODE       deprecated alias for --emacs-home
  --remove          remove the init seam and ~/.emacs.d/jetpacs
  --reset-home      remove only the managed early-init HOME/PATH block
  --audit           report the selected layout without changing it
  --skip-pylsp      do not install the optional Termux Python LSP tooling
  -h, --help        show this help

  SERIAL   adb device serial (default: \$ANDROID_SERIAL, else
           192.168.1.181:42553 -- the tablet this tree targets)

Environment:
  ONBOARD_SSH_USER   ssh login name (default: \$(id -un); Termux's sshd
                     ignores the name, so this is cosmetic)
  ONBOARD_SSH_WAIT   seconds to wait for sshd after the typed bootstrap
                     (default 420 -- a cold 'pkg install' on a slow link
                     genuinely takes minutes)

With no options, Recommended selects Local Emacs HOME plus an /sdcard Vault.
Advanced chooses the Emacs host first and then an eligible Vault. Explicit
flags retain the lower-level path controls for automation. Remove/reset-home
require both choices when no terminal is available. .emacs.d is always in one
of the two private homes, never /sdcard.
EOF
}

log()  { printf '[onboard] %s\n' "$*" >&2; }
die()  { printf '[onboard] ERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\n[onboard] === %s ===\n' "$*" >&2; }

VAULT_MODE=""
EMACS_HOME_MODE=""
ACTION=install
ACTION_EXPLICIT=0
INSTALL_PYLSP=1
SERIAL_ARG=""
set_action() {
  local requested="$1"
  if [ "$ACTION_EXPLICIT" -eq 1 ]; then
    die "choose only one of --remove, --reset-home, or --audit"
  fi
  ACTION="$requested"
  ACTION_EXPLICIT=1
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --vault)
      [ "$#" -ge 2 ] || die "$1 requires shared, emacs, or termux"
      VAULT_MODE="$2"
      shift 2
      ;;
    --vault=*) VAULT_MODE="${1#*=}"; shift ;;
    --emacs-home|--home)
      [ "$#" -ge 2 ] || die "$1 requires emacs, termux, or remote"
      EMACS_HOME_MODE="$2"
      shift 2
      ;;
    --emacs-home=*|--home=*) EMACS_HOME_MODE="${1#*=}"; shift ;;
    --remove) set_action remove; shift ;;
    --reset-home) set_action reset-home; shift ;;
    --audit) set_action audit; INSTALL_PYLSP=0; shift ;;
    --skip-pylsp) INSTALL_PYLSP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        [ -z "$SERIAL_ARG" ] || die "only one adb SERIAL may be supplied"
        SERIAL_ARG="$1"
        shift
      done
      ;;
    -*) die "unknown option: $1" ;;
    *)
      [ -z "$SERIAL_ARG" ] || die "only one adb SERIAL may be supplied"
      SERIAL_ARG="$1"
      shift
      ;;
  esac
done
[ "$#" -eq 0 ] || die "unexpected arguments: $*"

choose_emacs_home_mode() {
  if [ -n "$EMACS_HOME_MODE" ]; then return; fi
  if [ -t 0 ]; then
    printf '\nWhere should your HOME directory be?\n\n' >&2
    printf '  1. Local Emacs  (default)\n' >&2
    printf '     .emacs.d/jetpacs uses Android Emacs private storage.\n\n' >&2
    printf '  2. Remote Emacs\n' >&2
    printf '     Leave Android Emacs and its HOME untouched.\n\n' >&2
    printf '  3. Termux\n' >&2
    printf '     .emacs.d/jetpacs uses Termux private storage.\n\n' >&2
    printf 'Choice [1]: ' >&2
    local choice
    read -r choice
    case "${choice:-1}" in
      1|emacs|local) EMACS_HOME_MODE=emacs ;;
      2|remote) EMACS_HOME_MODE=remote ;;
      3|termux|advanced|private) EMACS_HOME_MODE=termux ;;
      *) die "invalid Emacs HOME choice: $choice" ;;
    esac
  elif [ "$ACTION" = install ]; then
    EMACS_HOME_MODE=emacs
    log "no terminal and no --emacs-home; using Local Emacs HOME"
  else
    die "$ACTION requires --emacs-home emacs|termux in non-interactive use"
  fi
}

choose_vault_mode() {
  if [ -n "$VAULT_MODE" ]; then return; fi
  if [ -t 0 ]; then
    printf '\nWhere should your Vault be?\n\n' >&2
    printf '  1. /sdcard\n' >&2
    printf '     Persistent user content; apps with "All files" access can read it.\n\n' >&2
    if [ "$EMACS_HOME_MODE" = emacs ]; then
      printf '  2. Local Emacs home\n' >&2
      printf '     Private user content deleted with Emacs app data.\n\n' >&2
    else
      printf '  2. Local Emacs home\n' >&2
      printf '     Private user content deleted with Emacs app data.\n\n' >&2
      printf '  3. Termux home\n' >&2
      printf '     Private user content deleted with Termux app data.\n\n' >&2
    fi
    printf 'Choice [1]: ' >&2
    local choice
    read -r choice
    case "${choice:-1}" in
      1|shared) VAULT_MODE=shared ;;
      2|emacs|local) VAULT_MODE=emacs ;;
      3|termux)
        [ "$EMACS_HOME_MODE" = termux ] \
          || die "Termux Vault is offered only when Termux is the selected HOME"
        VAULT_MODE=termux
        ;;
      *) die "invalid Vault choice: $choice" ;;
    esac
  elif [ "$ACTION" = install ]; then
    VAULT_MODE=shared
    log "no terminal and no --vault; using the /sdcard Vault default"
  else
    die "$ACTION requires --vault shared|emacs|termux in non-interactive use"
  fi
}

case "$EMACS_HOME_MODE" in
  local) EMACS_HOME_MODE=emacs ;;
  private|advanced) EMACS_HOME_MODE=termux ;;
  ''|emacs|termux|remote) ;;
  *) die "--emacs-home must be emacs, termux, or remote" ;;
esac
case "$VAULT_MODE" in
  local) VAULT_MODE=emacs ;;
  ''|shared|emacs|termux) ;;
  *) die "--vault must be shared, emacs, or termux" ;;
esac

if [ "$ACTION" = install ] && [ -t 0 ] \
     && [ -z "$EMACS_HOME_MODE" ] && [ -z "$VAULT_MODE" ]; then
  printf '\nWhere should your HOME directory/Vault be?\n\n' >&2
  printf '  1. Recommended\n' >&2
  printf '     Local Emacs HOME + /sdcard Vault.\n\n' >&2
  printf '  2. Advanced\n' >&2
  printf '     Choose the Emacs host, then an eligible Vault.\n\n' >&2
  printf 'Choice [1]: ' >&2
  read -r setup_choice
  case "${setup_choice:-1}" in
    1|recommended)
      EMACS_HOME_MODE=emacs
      VAULT_MODE=shared
      ;;
    2|advanced) ;;
    *) die "invalid setup choice: $setup_choice" ;;
  esac
fi

choose_emacs_home_mode
case "$EMACS_HOME_MODE" in
  emacs|termux) ;;
  remote)
    [ "$ACTION" = install ] || die "--emacs-home remote is only valid for install"
    echo "Jetpacs remote mode selected: Android Emacs HOME and Vault were not changed."
    echo "Pairing ID: 101112131415161718191a1b1c1d1e1f"
    echo "Pairing token: AAECAwQFBgcICQoLDA0ODw"
    echo "Install this tree under ~/.emacs.d/jetpacs, add its emacs/ directory"
    echo "to load-path, set jetpacs-pairing-id/token, then (require 'jetpacs)."
    echo "Forward the listener with: adb forward tcp:8765 tcp:8765"
    exit 0
    ;;
  *) die "--emacs-home must be emacs, termux, or remote" ;;
esac

choose_vault_mode
case "$VAULT_MODE" in
  shared|emacs|termux) ;;
  *) die "--vault must be shared, emacs, or termux" ;;
esac

SERIAL="${SERIAL_ARG:-${ANDROID_SERIAL:-192.168.1.181:42553}}"
SSH_PORT=8022
SSH_USER="${ONBOARD_SSH_USER:-$(id -un)}"
SSH_WAIT_SECONDS="${ONBOARD_SSH_WAIT:-420}"

SCRATCH_DIR="$REPO_ROOT/tools/onboard-scratch"
DEFAULT_KEY="$HOME/.ssh/id_ed25519"
DEDICATED_KEY="$SCRATCH_DIR/onboard_ed25519"

adbs() { adb -s "$SERIAL" "$@"; }

# ---------------------------------------------------------------------
# Preflight: local tools, device visible, the tree's own invariants
# ---------------------------------------------------------------------

for cmd in adb ssh ssh-keygen tar; do
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
  bootstrap="pkg install -y openssh"
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

phase_provision() {
  local stage='.cache/jetpacs-onboard' payload
  payload="$stage/payload"

  # Non-install actions need no payload and stream the installer through stdin.
  # In particular, --audit leaves no temporary files behind on the tablet.
  if [ "$ACTION" != install ]; then
    log "running device-side action=$ACTION vault=$VAULT_MODE emacs-home=$EMACS_HOME_MODE"
    PROVISION_OUTPUT="$(ssh_run bash -s -- \
      "$ACTION" "$VAULT_MODE" "$EMACS_HOME_MODE" \
      < "$SCRIPT_DIR/onboard-provision-remote.sh")" \
      || die "the remote $ACTION action failed -- its output above names the step"
    return
  fi

  ssh_run 'mkdir -p .cache/jetpacs-onboard' \
    || die "could not create the temporary onboarding stage in Termux"
  ssh_run 'cat > .cache/jetpacs-onboard/install-jetpacs.sh' \
      < "$SCRIPT_DIR/onboard-provision-remote.sh" \
    || die "transfer of the device-side installer failed"

  if [ "$ACTION" = install ]; then
    # The stage is transport only and is removed after provisioning.  The
    # active tree is always SELECTED_HOME/.emacs.d/jetpacs.
    ssh_run "rm -rf $payload && mkdir -p $payload/emacs $payload/org \
$payload/examples/python $payload/bootstrap" \
      || die "could not prepare the temporary payload directory"

  # tar over ssh, NOT rsync: on this tablet's Termux (rsync 3.5.0,
  # openssh 10.5p1) the rsync RECEIVER gets EACCES on chdir into a
  # directory the same login shell enters fine -- no AVC logged, owner
  # and 0700 modes correct. The stage is fresh, so renamed modules cannot
  # linger; the device-side installer swaps the distribution subtrees.
    log "staging emacs/ (whole tree, apps/ and spike/ included)"
    tar -C "$REPO_ROOT/emacs" --exclude='*.elc' --exclude='.#*' \
      --exclude='*~' --exclude='#*#' --exclude='__pycache__' -czf - . \
      | ssh_run "tar -C $payload/emacs -xzf -" \
      || die "tar of emacs/ to the device failed"

    log "staging device/py/ as managed examples/python/"
    tar -C "$REPO_ROOT/device/py" -czf - . \
      | ssh_run "tar -C $payload/examples/python -xzf -" \
      || die "tar of device/py/ to the device failed"

    # Distribution assets, not the user's live org-directory. The Org app
    # copies only missing files from here into ~/org.
    log "staging org/ (seed + Orgro walkthrough)"
    tar -C "$REPO_ROOT/org" -czf - . \
      | ssh_run "tar -C $payload/org -xzf -" \
      || die "tar of org/ seed assets to the device failed"

    log "staging the path-independent composition root and startup seams"
    ssh_run "cat > $payload/init.el" < "$REPO_ROOT/device/init.el" \
      || die "transfer of device/init.el failed"
    ssh_run "cat > $payload/bootstrap/early-init-local.el" \
        < "$REPO_ROOT/device/early-init-local.el" \
      || die "transfer of the Local Emacs early-init template failed"
    ssh_run "cat > $payload/bootstrap/early-init-termux.el" \
        < "$REPO_ROOT/device/early-init-termux.el" \
      || die "transfer of the Termux-shared early-init template failed"
    ssh_run "cat > $payload/bootstrap/init-seam.el" \
        < "$REPO_ROOT/device/init-seam.el" \
      || die "transfer of the init seam failed"

    if [ "$INSTALL_PYLSP" -eq 1 ]; then
      log "verifying optional Termux python/pylsp tooling"
      ssh_run 'if ! command -v python3 >/dev/null 2>&1; then pkg install -y python; fi; if ! command -v pylsp >/dev/null 2>&1; then python3 -m pip install --no-input python-lsp-server; fi' \
        || die "could not install the optional python-lsp-server tooling"
    fi
  fi

  # The remote script's stderr streams straight through to ours as it
  # runs (log/die breadcrumbs); only its REPORT_ lines are on stdout,
  # and those are what phase_verify parses.
  log "running device-side action=$ACTION vault=$VAULT_MODE emacs-home=$EMACS_HOME_MODE"
  PROVISION_OUTPUT="$(ssh_run bash "$stage/install-jetpacs.sh" \
    "$ACTION" "$VAULT_MODE" "$EMACS_HOME_MODE" "$payload")" \
    || die "the remote provisioning script failed on the device -- its \
output above names the exact step"

  # This is explicitly a transport cache, not a third Jetpacs installation.
  ssh_run "rm -rf $stage" \
    || log "warning: could not remove temporary transport stage $stage"
}

report_field() {
  printf '%s\n' "$PROVISION_OUTPUT" | sed -n "s/^REPORT_${1}=//p" | tail -n1
}

# ---------------------------------------------------------------------
# PHASE verify
# ---------------------------------------------------------------------

phase_verify() {
  local vault vault_writable emacs_home_mode emacs_user_home emacs_user_dotdir \
        jetpacs_root elisp_dir examples_dir \
        org_dir elisp_files emacs_home early_init init_dest pylsp_bin legacy \
        root_state home_seams init_seams legacy_harness_present

  vault="$(report_field VAULT)"
  vault_writable="$(report_field VAULT_WRITABLE)"
  emacs_home_mode="$(report_field EMACS_HOME_MODE)"
  emacs_user_home="$(report_field EMACS_USER_HOME)"
  emacs_user_dotdir="$(report_field EMACS_USER_DOTDIR)"
  jetpacs_root="$(report_field JETPACS_ROOT)"
  root_state="$(report_field ROOT_STATE)"
  elisp_dir="$(report_field ELISP_DIR)"
  elisp_files="$(report_field ELISP_FILES)"
  examples_dir="$(report_field EXAMPLES_DIR)"
  org_dir="$(report_field ORG_DIR)"
  emacs_home="$(report_field EMACS_HOME)"
  early_init="$(report_field BOOTSTRAP_EARLY_INIT)"
  home_seams="$(report_field HOME_SEAM_COUNT)"
  init_dest="$(report_field INIT_DEST)"
  init_seams="$(report_field INIT_SEAM_COUNT)"
  legacy_harness_present="$(report_field LEGACY_HARNESS_PRESENT)"
  pylsp_bin="$(report_field PYLSP_BIN)"
  legacy="$(report_field LEGACY_PATHS)"

  echo >&2
  echo "=================== Jetpacs onboarding report ==================" >&2
  printf '  device serial          : %s\n' "$SERIAL" >&2
  printf '  action                 : %s\n' "$ACTION" >&2
  printf '  Vault mode             : %s\n' "$VAULT_MODE" >&2
  printf '  user-content Vault     : %s  [writable from Termux: %s]\n' \
    "${vault:-?}" "${vault_writable:-?}" >&2
  printf '  Emacs HOME mode        : %s\n' "${emacs_home_mode:-?}" >&2
  printf '  private Unix HOME      : %s\n' "${emacs_user_home:-?}" >&2
  printf '  private .emacs.d       : %s\n' "${emacs_user_dotdir:-?}" >&2
  printf '  managed Jetpacs root   : %s  [%s]\n' \
    "${jetpacs_root:-?}" "${root_state:-?}" >&2
  printf '  ssh                    : %s@127.0.0.1:%s (adb forward, key %s)\n' \
    "$SSH_USER" "$SSH_PORT" "$SSH_KEY" >&2
  printf '  managed elisp tree     : %s  (%s .el files)\n' \
    "${elisp_dir:-?}" "${elisp_files:-?}" >&2
  printf '  managed examples       : %s\n' "${examples_dir:-?}" >&2
  printf '  managed Org seed       : %s\n' "${org_dir:-?}" >&2
  printf '  original Emacs HOME    : %s  [bootstrap location only]\n' \
    "${emacs_home:-?}" >&2
  printf '  early-init seam        : %s  [%s managed block(s)]\n' \
    "${early_init:-?}" "${home_seams:-?}" >&2
  printf '  private init seam      : %s  [%s managed block(s)]\n' \
    "${init_dest:-?}" "${init_seams:-?}" >&2
  printf '  retired private harness: %s\n' "${legacy_harness_present:-?}" >&2
  printf '  pylsp                  : %s\n' "${pylsp_bin:-not installed}" >&2
  if [ -n "$legacy" ]; then
    printf '  inactive legacy trees  : %s\n' "${legacy//|/, }" >&2
  else
    printf '  inactive legacy trees  : none detected\n' >&2
  fi
  echo "===============================================================" >&2
  echo >&2
  case "$ACTION" in
    install)
      echo "REMAINING:" >&2
      echo "  1. Grant Emacs 'All files' access if the Vault is /sdcard." >&2
      echo "  2. Force-stop and relaunch org.gnu.emacs, then open the" >&2
      echo "     EBP Companion. Emacs reads the private early-init redirect," >&2
      echo "     then the private init and managed root above. User content" >&2
      echo "     opens from the Vault; .emacs.d never lives there." >&2
      if [ -n "$legacy" ]; then
        echo "  3. The legacy trees listed above are no longer on the startup" >&2
        echo "     path. Inspect them before deleting; they may contain edits." >&2
      fi
      ;;
    remove)
      echo "Jetpacs was removed; the Vault and selected Unix HOME were kept." >&2
      echo "Use --reset-home --vault $VAULT_MODE --emacs-home $EMACS_HOME_MODE" >&2
      echo "only if Android Emacs should" >&2
      echo "return to its original app-private HOME." >&2
      ;;
    reset-home)
      echo "The HOME/PATH block was removed. The Vault and private files remain." >&2
      ;;
    audit) : ;;
  esac
  echo >&2
}

# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------

resolve_ssh_key
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
'pkg install -y openssh' reach the network? did the echo land \
(cat ~/.ssh/authorized_keys)? did 'sshd' print an error? Fix on-device, \
then re-run -- this phase is skipped entirely once ssh answers."
  log "ssh reachable"
fi

if [ "$ACTION" != audit ]; then
  log "force-stopping org.gnu.emacs before changing startup/state files"
  adbs shell am force-stop org.gnu.emacs >/dev/null
fi

step "PHASE provision"
phase_provision

step "PHASE verify"
phase_verify
