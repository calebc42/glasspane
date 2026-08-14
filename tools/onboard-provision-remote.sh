#!/data/data/com.termux/files/usr/bin/bash
# Runs INSIDE Termux, over the ssh session tools/onboard-tablet.sh opens
# (transferred there as ~/.onboard-provision.sh and invoked as
# `bash .onboard-provision.sh'). See device/MANIFEST.md for the deploy
# contract this implements and the runtime checks it owes.
#
# Everything the DESKTOP side can do generically (rsync the emacs/ and
# device/py/ trees, stage this script and emacs-init.el) has already
# happened by the time this runs. What is left has to branch on live
# device state, so it is a real script rather than a chain of
# `ssh host <one-liner>' calls.
#
# Idempotent: every mutation checks before it acts, and it is always
# safe to re-run -- after a wipe, after a partial failure, or just to
# re-verify.
set -euo pipefail

# A non-interactive `ssh host cmd' does not necessarily source the
# profile a login shell would, so put $PREFIX/bin on PATH explicitly
# instead of hoping.
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:$PATH"

JETPACS_DIR="$HOME/jetpacs"
EMACS_INIT_STAGED="$JETPACS_DIR/emacs-init.el"
ELISP_DIR="$JETPACS_DIR/emacs"
PY_DIR="$JETPACS_DIR/py"
ORG_DIR="$JETPACS_DIR/org"
# Kept in sync BY HAND with device/MANIFEST.md's deploy table and
# device/emacs-init.el's `jetpacs-emacs-init-termux-bin' -- there is
# nowhere on-device to source one shared constant from.
TERMUX_BIN="/data/data/com.termux/files/usr/bin"
# Candidate org.gnu.emacs HOME paths, tried in order. Emacs's Android
# port sets HOME from getFilesDir().getCanonicalPath() (src/android.c:
# `setenv ("HOME", android_files_dir, 1)'), and which of these two the
# canonical path resolves to is an OS-build property -- so probe, do not
# hardcode one and hope.
EMACS_HOME_CANDIDATES=(
  "/data/data/org.gnu.emacs/files"
  "/data/user/0/org.gnu.emacs/files"
)

log() { printf '[provision] %s\n' "$*" >&2; }
die() { printf '[provision] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    python3 -c \
      "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" \
      "$1"
  fi
}

# --- sanity: the desktop side's transfers actually landed -------------

[ -f "$EMACS_INIT_STAGED" ] || die "missing $EMACS_INIT_STAGED -- the \
transfer of device/emacs-init.el did not land before this ran"
[ -d "$ELISP_DIR" ] || die "missing $ELISP_DIR -- the rsync of emacs/ did \
not land before this ran"
[ -d "$PY_DIR" ] || die "missing $PY_DIR -- the rsync of device/py/ did \
not land before this ran"
[ -d "$ORG_DIR" ] || die "missing $ORG_DIR -- the transfer of org/ did \
not land before this ran"

# A directory is not a tree. device/emacs-init.el's whole stage 3 is
# `(require 'jetpacs-files)' and friends off this root; an empty or
# half-transferred directory would only surface much later, on the
# tablet, as a pile of "require ... FAILED" breadcrumbs.
[ -f "$ELISP_DIR/ebp.el" ] && [ -f "$ELISP_DIR/jetpacs-files.el" ] \
  || die "$ELISP_DIR exists but does not contain ebp.el and \
jetpacs-files.el -- the tree transfer is incomplete"
ELISP_FILES="$(find "$ELISP_DIR" -name '*.el' | wc -l | tr -d ' ')"
log "elisp tree: $ELISP_FILES .el files under $ELISP_DIR"

[ -f "$ORG_DIR/inbox.org" ] \
  && [ -f "$ORG_DIR/org-mode-walkthrough/orgro-manual.org" ] \
  || die "$ORG_DIR is missing inbox.org or the Orgro manual bundle"
log "Org seed bundle: inbox + Orgro walkthrough under $ORG_DIR"

# The desktop excludes *.elc from the sync because a stale .elc silently
# shadows its .el. Catch one that reached the device some other way (an
# older script, a hand copy).
stray_elc="$(find "$ELISP_DIR" -name '*.elc' | head -5 || true)"
if [ -n "$stray_elc" ]; then
  log "removing stale .elc on the device (they shadow their .el): $stray_elc"
  find "$ELISP_DIR" -name '*.elc' -delete
fi

# live.py's last two bytes must be "a." with NO trailing newline. That
# matters for a DESKTOP-DRIVEN edit.open that seeds :cursor as the
# fixture's own length -- test/smoke-eglot-lsp.el's pattern. It does NOT
# matter for the on-device Files flow, where the cursor comes from where
# the user taps. Checked anyway: rsync preserves bytes exactly, so a
# mismatch here means something on the Termux side touched the file
# after it landed.
tail_bytes=""
if [ -f "$PY_DIR/live.py" ]; then
  tail_bytes="$(tail -c 2 "$PY_DIR/live.py" | od -An -tx1 | tr -d ' \n')"
  if [ "$tail_bytes" = "612e" ]; then
    log "live.py tail OK (ends 'a.', no trailing newline)"
  else
    log "WARNING: live.py's last 2 bytes are 0x$tail_bytes, expected \
0x612e ('a.') -- a desktop-seeded cursor-at-EOF probe will be off by one"
  fi
else
  log "WARNING: $PY_DIR/live.py not present (device/py/ empty or renamed?)"
fi

# --- pylsp ------------------------------------------------------------
# HARD FACTS says python + python-lsp-server "were just installed ...
# verify at runtime anyway". This is that verification, with a self-heal
# if the install did not actually take.

command -v python3 >/dev/null 2>&1 \
  || die "python3 not on PATH in Termux -- install it: pkg install -y python"

PIP=""
for c in pip pip3; do
  if command -v "$c" >/dev/null 2>&1; then PIP="$c"; break; fi
done

if ! command -v pylsp >/dev/null 2>&1; then
  [ -n "$PIP" ] || die "pylsp is missing and neither pip nor pip3 is on \
PATH -- install python first: pkg install -y python"
  log "pylsp not found on PATH; installing python-lsp-server (slow)"
  "$PIP" install --no-input python-lsp-server \
    || die "'$PIP install python-lsp-server' failed -- ssh in and re-run \
it by hand to see pip's own output"
fi
command -v pylsp >/dev/null 2>&1 \
  || die "pylsp still not on PATH after installing python-lsp-server -- \
check where pip put its console scripts (it must be under $TERMUX_BIN)"

PYLSP_BIN="$(command -v pylsp)"
PYLSP_VERSION="$(pylsp --version 2>&1 | head -n1 || true)"
case "$PYLSP_BIN" in
  "$TERMUX_BIN"/*) log "pylsp resolves under \$TERMUX_BIN: $PYLSP_BIN" ;;
  *) log "WARNING: pylsp resolves to $PYLSP_BIN, OUTSIDE $TERMUX_BIN -- \
device/emacs-init.el only adds $TERMUX_BIN to exec-path/PATH, so eglot on \
the device will NOT find this binary. Either symlink it into \
$TERMUX_BIN or override jetpacs-emacs-init-termux-bin." ;;
esac

# --- Android Emacs HOME (shared uid with com.termux) ------------------

EMACS_HOME=""
for c in "${EMACS_HOME_CANDIDATES[@]}"; do
  if [ -d "$c" ]; then EMACS_HOME="$c"; break; fi
done
[ -n "$EMACS_HOME" ] || die "no candidate org.gnu.emacs HOME is visible \
from Termux (tried: ${EMACS_HOME_CANDIDATES[*]}) -- is org.gnu.emacs \
installed, and has it been launched at least once? The shared-uid access \
this whole bundle depends on does not hold if this directory does not \
even exist."
log "EMACS_HOME=$EMACS_HOME ($(stat -c '%U:%G %a' "$EMACS_HOME" 2>/dev/null \
  || echo 'stat unavailable'))"

EMACS_DOTDIR="$EMACS_HOME/.emacs.d"
# Creating .emacs.d also DECIDES the init location: Emacs 30.1's
# `startup--xdg-or-homedot' returns ~/.emacs.d the moment that directory
# exists, ahead of any XDG ~/.config/emacs. So this mkdir is
# load-bearing, not just convenience.
mkdir -p "$EMACS_DOTDIR" 2>/dev/null || true
[ -d "$EMACS_DOTDIR" ] || die "could not create $EMACS_DOTDIR from Termux"

# Prove write access rather than let the install below be the first
# thing to discover that the shared-uid assumption does not hold on this
# OS build (SELinux can scope per package even under a shared uid).
write_probe="$EMACS_DOTDIR/.onboard-write-test"
if ! ( : > "$write_probe" && rm -f "$write_probe" ); then
  die "cannot write into $EMACS_DOTDIR from Termux -- the shared-uid \
read/write assumption does not hold on this device/OS build, and this \
transport cannot install org.gnu.emacs's init"
fi
log "write access into $EMACS_DOTDIR confirmed"

# --- install the harness, then WIRE it from init.el -------------------
#
# Deliberately NOT `cp emacs-init.el .emacs.d/init.el'.
# docs/ONBOARDING-device.md's daily-driver setup puts
#   (load "/sdcard/Documents/jetpacs/init.el")
# in that exact file. Overwriting it would silently uninstall the daily
# driver, and the two flows would be mutually exclusive rather than
# complementary. So the harness lands beside init.el under its own name
# and init.el gains ONE appended load line -- appended, so anything
# already there still runs FIRST. device/emacs-init.el declines to dial
# the Companion when a client is already attached, which is what makes
# that ordering safe.

HARNESS="$EMACS_DOTDIR/jetpacs-onboard-init.el"
INIT="$EMACS_DOTDIR/init.el"
LOAD_LINE="(load \"$HARNESS\" nil t)"
NEW_SHA="$(sha256_of "$EMACS_INIT_STAGED")"

if [ -f "$HARNESS" ] && [ "$(sha256_of "$HARNESS")" = "$NEW_SHA" ]; then
  log "harness already up to date at $HARNESS (sha256 $NEW_SHA)"
else
  cp "$EMACS_INIT_STAGED" "$HARNESS"
  log "installed harness $HARNESS (sha256 $NEW_SHA)"
fi

if [ ! -f "$INIT" ]; then
  { printf ';;; init.el --- created by tools/onboard-tablet.sh\n'
    printf '%s\n' "$LOAD_LINE"
  } > "$INIT"
  INIT_STATE="created"
  log "created $INIT with the harness load line"
elif grep -qF "jetpacs-onboard-init.el" "$INIT"; then
  INIT_STATE="already wired"
  log "$INIT already loads the harness -- left untouched"
else
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$INIT" "$INIT.bak-$ts"
  { printf '\n;;; appended by tools/onboard-tablet.sh -- the onboarding harness.\n'
    printf ';;; Anything above still runs FIRST; the harness declines to\n'
    printf ';;; dial the Companion when a client is already attached.\n'
    printf '%s\n' "$LOAD_LINE"
  } >> "$INIT"
  INIT_STATE="appended (backup $INIT.bak-$ts)"
  log "appended the harness load line to $INIT (backup at $INIT.bak-$ts)"
fi

# --- machine-readable report for the desktop side ---------------------
echo "REPORT_JETPACS_DIR=$JETPACS_DIR"
echo "REPORT_ELISP_DIR=$ELISP_DIR"
echo "REPORT_ELISP_FILES=$ELISP_FILES"
echo "REPORT_PY_DIR=$PY_DIR"
echo "REPORT_ORG_DIR=$ORG_DIR"
echo "REPORT_EMACS_HOME=$EMACS_HOME"
echo "REPORT_INIT_HARNESS=$HARNESS"
echo "REPORT_INIT_DEST=$INIT"
echo "REPORT_INIT_STATE=$INIT_STATE"
echo "REPORT_PYLSP_BIN=$PYLSP_BIN"
echo "REPORT_PYLSP_VERSION=$PYLSP_VERSION"
echo "REPORT_LIVE_PY_TAIL=$tail_bytes"
