#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
INSTALLER="$REPO_ROOT/tools/onboard-provision-remote.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { printf 'onboarding-layout-test: %s\n' "$*" >&2; exit 1; }

assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_dir() { [ -d "$1" ] || fail "missing directory: $1"; }
assert_absent() { [ ! -e "$1" ] || fail "expected absent: $1"; }
assert_contains() {
  grep -qF "$2" "$1" || fail "$1 does not contain: $2"
}
assert_not_contains() {
  if [ -f "$1" ] && grep -qF "$2" "$1"; then
    fail "$1 unexpectedly contains: $2"
  fi
}
assert_count() {
  local actual
  actual="$(grep -cF "$2" "$1" || true)"
  [ "$actual" = "$3" ] || fail "$1 contains '$2' $actual times, expected $3"
}
assert_before() {
  awk -v first="$2" -v second="$3" '
    index($0, first) && !a { a=NR }
    index($0, second) && !b { b=NR }
    END { exit !(a && b && a < b) }
  ' "$1" || fail "$1 does not place '$2' before '$3'"
}

make_payload() {
  local payload="$1"
  mkdir -p "$payload/emacs" "$payload/org/org-mode-walkthrough" \
           "$payload/examples/python" "$payload/bootstrap"
  cp "$REPO_ROOT/emacs/ebp.el" "$payload/emacs/ebp.el"
  cp "$REPO_ROOT/emacs/jetpacs-files.el" "$payload/emacs/jetpacs-files.el"
  cp "$REPO_ROOT/org/org-mode-walkthrough/orgro-manual.org" \
     "$payload/org/org-mode-walkthrough/orgro-manual.org"
  cp "$REPO_ROOT/device/py/live.py" "$payload/examples/python/live.py"
  cp "$REPO_ROOT/device/init.el" "$payload/init.el"
  cp "$REPO_ROOT/device/early-init-local.el" \
     "$payload/bootstrap/early-init-local.el"
  cp "$REPO_ROOT/device/early-init-termux.el" \
     "$payload/bootstrap/early-init-termux.el"
  cp "$REPO_ROOT/device/init-seam.el" "$payload/bootstrap/init-seam.el"
}

run_installer() {
  local fixture="$1"
  shift
  HOME="$fixture/termux" \
  JETPACS_TERMUX_HOME="$fixture/termux" \
  JETPACS_SHARED_VAULT="$fixture/sdcard" \
  JETPACS_EMACS_HOME="$fixture/emacs-private" \
  JETPACS_TERMUX_BIN="$fixture/termux-bin" \
    bash "$INSTALLER" "$@"
}

# Jetpacs owns exactly one bounded init section. An ambiguous duplicate must
# fail before setup changes either the init file or the managed tree.
duplicate="$TEST_ROOT/duplicate-managed-section"
mkdir -p "$duplicate/termux" "$duplicate/sdcard" \
         "$duplicate/emacs-private/.emacs.d" "$duplicate/termux-bin"
make_payload "$duplicate/payload"
{
  printf ';; existing user init\n'
  cat "$REPO_ROOT/device/init-seam.el"
  printf '\n;; existing user form between duplicates\n'
  cat "$REPO_ROOT/device/init-seam.el"
} > "$duplicate/emacs-private/.emacs.d/init.el"
cp "$duplicate/emacs-private/.emacs.d/init.el" "$duplicate/init.before"
if run_installer "$duplicate" install shared emacs "$duplicate/payload" \
     > /dev/null 2> "$duplicate/error"; then
  fail "installer accepted duplicate Jetpacs init sections"
fi
cmp -s "$duplicate/init.before" "$duplicate/emacs-private/.emacs.d/init.el" \
  || fail "duplicate-section failure changed the user's init.el"
assert_absent "$duplicate/emacs-private/.emacs.d/jetpacs"
assert_contains "$duplicate/error" 'malformed or duplicate managed block'

shared="$TEST_ROOT/shared"
payload="$shared/payload"
mkdir -p "$shared/termux" "$shared/sdcard" \
         "$shared/emacs-private/.emacs.d" "$shared/termux-bin"
make_payload "$payload"
mkdir -p "$shared/emacs-private/.emacs.d/jetpacs/apps/glasspane"
printf ';; keep app config\n' \
  > "$shared/emacs-private/.emacs.d/jetpacs/apps/glasspane/user.el"
printf '(setq jetpacs-app-store-installed '\''("demo.el"))\n' \
  > "$shared/emacs-private/.emacs.d/jetpacs-apps.el"
printf 'legacy receipt bytes' \
  > "$shared/emacs-private/.emacs.d/jetpacs-receipts.sqlite"
printf ';; keep original private init\n(load "/old/jetpacs-onboard-init.el" nil t)\n' \
  > "$shared/emacs-private/.emacs.d/init.el"
printf ';; retired harness\n' \
  > "$shared/emacs-private/.emacs.d/jetpacs-onboard-init.el"
printf ';; keep early custom\n' > "$shared/emacs-private/.emacs.d/early-init.el"
mkdir -p "$shared/termux/jetpacs" "$shared/sdcard/Documents/jetpacs"
printf 'user Vault content\n' > "$shared/sdcard/keep-me.org"

run_installer "$shared" install shared emacs "$payload" > "$shared/report"
managed="$shared/emacs-private/.emacs.d/jetpacs"
assert_file "$managed/init.el"
assert_file "$managed/emacs/ebp.el"
assert_file "$managed/org/org-mode-walkthrough/orgro-manual.org"
assert_file "$managed/examples/python/live.py"
assert_dir "$managed/apps"
assert_dir "$managed/var"
assert_file "$managed/apps/glasspane/user.el"
assert_file "$managed/apps.el"
assert_file "$managed/var/receipts.sqlite"
assert_file "$managed/migration/app-private-jetpacs-apps.el"
assert_file "$managed/migration/app-private-jetpacs-receipts.sqlite"
assert_absent "$shared/emacs-private/.emacs.d/jetpacs-apps.el"
assert_absent "$shared/emacs-private/.emacs.d/jetpacs-receipts.sqlite"
assert_file "$managed/migration/jetpacs-onboard-init.el"
assert_absent "$shared/emacs-private/.emacs.d/jetpacs-onboard-init.el"
assert_contains "$shared/emacs-private/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_before "$shared/emacs-private/.emacs.d/init.el" \
  ';; keep original private init' \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_contains "$shared/emacs-private/.emacs.d/init.el" \
  '(require '\''jetpacs)'
assert_absent "$shared/sdcard/.emacs.d"
assert_file "$shared/sdcard/keep-me.org"
assert_contains "$managed/install.conf" 'vault_mode=shared'
assert_contains "$managed/install.conf" "vault=$shared/sdcard"
assert_contains "$managed/install.conf" 'home_mode=emacs'
assert_contains "$managed/install.conf" "home=$shared/emacs-private"
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  ';; keep early custom'
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  ';; Local Emacs keeps the private HOME Android assigned it.'
assert_not_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  '(setenv "HOME" "/data/data/com.termux/files/home")'
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  '(setenv "PATH" (format "%s:%s" "/data/data/com.termux/files/usr/bin"'
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  '(push "/data/data/com.termux/files/usr/bin" exec-path)'
assert_not_contains "$shared/emacs-private/.emacs.d/init.el" \
  'jetpacs-onboard-init.el'
assert_contains "$shared/report" "REPORT_JETPACS_ROOT=$managed"
assert_contains "$shared/report" "REPORT_VAULT=$shared/sdcard"
assert_contains "$shared/report" 'REPORT_EMACS_HOME_MODE=emacs'
assert_contains "$shared/report" "REPORT_EMACS_USER_HOME=$shared/emacs-private"
assert_contains "$shared/report" \
  "REPORT_LEGACY_PATHS=$shared/termux/jetpacs|$shared/sdcard/Documents/jetpacs"

# Reinstall is a refresh, not a second startup seam.
run_installer "$shared" install shared emacs "$payload" > /dev/null
assert_count "$shared/emacs-private/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>' 1
assert_count "$shared/emacs-private/.emacs.d/early-init.el" \
  ';;; >>> Jetpacs managed: Android Emacs HOME >>>' 1

# Removing Jetpacs preserves the Vault and private HOME; resetting HOME is separate.
printf ';; user edit after install\n' >> "$shared/emacs-private/.emacs.d/init.el"
run_installer "$shared" remove shared emacs > /dev/null
assert_absent "$managed"
assert_file "$shared/sdcard/keep-me.org"
assert_contains "$shared/emacs-private/.emacs.d/init.el" ';; user edit after install'
assert_not_contains "$shared/emacs-private/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  '(push "/data/data/com.termux/files/usr/bin" exec-path)'
run_installer "$shared" reset-home shared emacs > /dev/null
assert_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  ';; keep early custom'
assert_not_contains "$shared/emacs-private/.emacs.d/early-init.el" \
  ';;; >>> Jetpacs managed: Android Emacs HOME >>>'

# Emacs Vault + Local Emacs HOME are independent selections that happen to
# resolve to the same private directory.
local="$TEST_ROOT/local"
mkdir -p "$local/termux" "$local/sdcard" \
         "$local/emacs-private/.emacs.d" "$local/termux-bin"
make_payload "$local/payload"
printf ';; local init\n' > "$local/emacs-private/.emacs.d/init.el"
run_installer "$local" install emacs emacs "$local/payload" > /dev/null
local_managed="$local/emacs-private/.emacs.d/jetpacs"
assert_file "$local_managed/init.el"
assert_contains "$local_managed/install.conf" 'vault_mode=emacs'
assert_contains "$local_managed/install.conf" "vault=$local/emacs-private"
assert_contains "$local_managed/install.conf" 'home_mode=emacs'
assert_contains "$local/emacs-private/.emacs.d/init.el" ';; local init'
assert_not_contains "$local/emacs-private/.emacs.d/early-init.el" \
  '(setenv "HOME" "/data/data/com.termux/files/home")'

# Termux Vault + Termux-shared HOME are also independent selections.
termux="$TEST_ROOT/termux-shared"
mkdir -p "$termux/termux/.emacs.d" "$termux/sdcard" \
         "$termux/emacs-private/.emacs.d" "$termux/termux-bin"
make_payload "$termux/payload"
printf ';; my init\n' > "$termux/termux/.emacs.d/init.el"
run_installer "$termux" install termux termux "$termux/payload" > /dev/null
termux_managed="$termux/termux/.emacs.d/jetpacs"
assert_file "$termux_managed/init.el"
assert_contains "$termux_managed/install.conf" 'vault_mode=termux'
assert_contains "$termux_managed/install.conf" "vault=$termux/termux"
assert_contains "$termux_managed/install.conf" 'home_mode=termux'
assert_contains "$termux/termux/.emacs.d/init.el" ';; my init'
assert_contains "$termux/termux/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_contains "$termux/emacs-private/.emacs.d/early-init.el" \
  '(setenv "HOME" "/data/data/com.termux/files/home")'

# All Vault x Unix-HOME combinations are valid. These cross-pairs are the
# regression guard against collapsing the two onboarding questions again.
check_combo() {
  local fixture="$1" vault_mode="$2" home_mode="$3"
  local expected_vault="$4" expected_home="$5" expected_root
  mkdir -p "$fixture/termux" "$fixture/sdcard" \
           "$fixture/emacs-private/.emacs.d" "$fixture/termux-bin"
  make_payload "$fixture/payload"
  run_installer "$fixture" install "$vault_mode" "$home_mode" \
    "$fixture/payload" > /dev/null
  expected_root="$expected_home/.emacs.d/jetpacs"
  assert_file "$expected_root/init.el"
  assert_contains "$expected_root/install.conf" "vault_mode=$vault_mode"
  assert_contains "$expected_root/install.conf" "vault=$expected_vault"
  assert_contains "$expected_root/install.conf" "home_mode=$home_mode"
  assert_contains "$expected_root/install.conf" "home=$expected_home"
}

check_combo "$TEST_ROOT/shared-termux" shared termux \
  "$TEST_ROOT/shared-termux/sdcard" "$TEST_ROOT/shared-termux/termux"
check_combo "$TEST_ROOT/emacs-termux" emacs termux \
  "$TEST_ROOT/emacs-termux/emacs-private" "$TEST_ROOT/emacs-termux/termux"
check_combo "$TEST_ROOT/termux-emacs" termux emacs \
  "$TEST_ROOT/termux-emacs/termux" "$TEST_ROOT/termux-emacs/emacs-private"

# Changing only Unix HOME carries durable state to the other private home,
# removes the inactive init seam/root, and leaves both Vault choice and user
# init forms intact. Switching back exercises the reverse direction.
switching="$TEST_ROOT/switching"
mkdir -p "$switching/termux" "$switching/sdcard" \
         "$switching/emacs-private/.emacs.d" "$switching/termux-bin"
make_payload "$switching/payload"
printf ';; user private init\n' > "$switching/emacs-private/.emacs.d/init.el"
run_installer "$switching" install shared emacs "$switching/payload" > /dev/null
old_switch_root="$switching/emacs-private/.emacs.d/jetpacs"
mkdir -p "$old_switch_root/apps/demo" "$old_switch_root/var"
printf ';; durable app config\n' > "$old_switch_root/apps/demo/user.el"
printf 'durable protocol state\n' > "$old_switch_root/var/state"
printf ';; durable user override\n' > "$old_switch_root/user.el"

mkdir -p "$switching/termux/.emacs.d"
printf ';; user Termux init\n' > "$switching/termux/.emacs.d/init.el"
run_installer "$switching" install shared termux "$switching/payload" > /dev/null
termux_switch_root="$switching/termux/.emacs.d/jetpacs"
assert_absent "$old_switch_root"
assert_file "$termux_switch_root/apps/demo/user.el"
assert_file "$termux_switch_root/var/state"
assert_file "$termux_switch_root/user.el"
assert_dir "$termux_switch_root/migration/previous-home-jetpacs"
assert_contains "$switching/emacs-private/.emacs.d/init.el" ';; user private init'
assert_not_contains "$switching/emacs-private/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_contains "$switching/termux/.emacs.d/init.el" ';; user Termux init'
assert_contains "$switching/termux/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'

run_installer "$switching" install shared emacs "$switching/payload" > /dev/null
new_switch_root="$switching/emacs-private/.emacs.d/jetpacs"
assert_absent "$termux_switch_root"
assert_file "$new_switch_root/apps/demo/user.el"
assert_file "$new_switch_root/var/state"
assert_file "$new_switch_root/user.el"
assert_dir "$new_switch_root/migration/previous-home-jetpacs"
assert_contains "$switching/emacs-private/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'
assert_contains "$switching/termux/.emacs.d/init.el" ';; user Termux init'
assert_not_contains "$switching/termux/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'

# A failed cross-home migration must not redirect Android Emacs into the new
# tree. The setup remains retryable after permissions are repaired.
failure="$TEST_ROOT/failure"
mkdir -p "$failure/termux" "$failure/sdcard" \
         "$failure/emacs-private/.emacs.d/jetpacs/apps" \
         "$failure/termux-bin"
make_payload "$failure/payload"
printf ';; original early init\n' \
  > "$failure/emacs-private/.emacs.d/early-init.el"
printf 'unreadable legacy state\n' \
  > "$failure/emacs-private/.emacs.d/jetpacs/apps/private.el"
chmod 000 "$failure/emacs-private/.emacs.d/jetpacs/apps/private.el"
if run_installer "$failure" install shared termux "$failure/payload" \
     > /dev/null 2> "$failure/error"; then
  chmod 600 "$failure/emacs-private/.emacs.d/jetpacs/apps/private.el"
  fail "migration with unreadable legacy state unexpectedly succeeded"
fi
chmod 600 "$failure/emacs-private/.emacs.d/jetpacs/apps/private.el"
assert_contains "$failure/emacs-private/.emacs.d/early-init.el" \
  ';; original early init'
assert_not_contains "$failure/emacs-private/.emacs.d/early-init.el" \
  ';;; >>> Jetpacs managed: Android Emacs HOME >>>'
assert_not_contains "$failure/termux/.emacs.d/init.el" \
  ';;; >>> Jetpacs managed: composition root >>>'

# Recommended is a separate, Emacs-owned bootstrap: the Companion prepares a
# payload, the init.el shim loads this file once, and Emacs creates its own
# private ~/.emacs.d/jetpacs tree without a shell-side installer.
recommended="$TEST_ROOT/recommended"
mkdir -p "$recommended/home/.emacs.d" "$recommended/vault" \
         "$recommended/kit"
make_payload "$recommended/kit/payload"
cp "$REPO_ROOT/device/install-recommended.el" \
  "$recommended/kit/install-recommended.el"
emacs -Q --batch \
  --eval "(setq user-emacs-directory \"$recommended/home/.emacs.d/\" jetpacs-bootstrap-vault-directory \"$recommended/vault\")" \
  -l "$recommended/kit/install-recommended.el" > /dev/null
recommended_root="$recommended/home/.emacs.d/jetpacs"
assert_file "$recommended_root/init.el"
assert_file "$recommended_root/emacs/ebp.el"
assert_file "$recommended_root/org/org-mode-walkthrough/orgro-manual.org"
assert_file "$recommended_root/install.conf"
assert_contains "$recommended_root/install.conf" "vault=$recommended/vault"
assert_contains "$recommended_root/install.conf" "home=$recommended/home"
assert_dir "$recommended_root/apps"
assert_dir "$recommended_root/var"
assert_dir "$recommended/vault/org"
assert_absent "$recommended/kit"

# The persistent footprint adds the bundled package to `load-path' and uses
# the same public `require' entry point as package.el/package-vc users. Generic
# user settings run first because the whole marked section is appended.
[ "$(wc -l < "$REPO_ROOT/device/init-seam.el")" = 4 ] \
  || fail "device/init-seam.el is not the minimal four-line managed block"
assert_contains "$REPO_ROOT/device/init-seam.el" \
  '(require '\''jetpacs)'
assert_not_contains "$REPO_ROOT/emacs/jetpacs-init.el" '(setq default-directory'
assert_contains "$REPO_ROOT/emacs/jetpacs-init.el" \
  '(defvar org-directory (expand-file-name "org/" jetpacs-vault-directory))'
assert_contains "$REPO_ROOT/emacs/jetpacs-init.el" \
  '(defvar ebp-org-roots (jetpacs-files-effective-roots)'

# Preparing the handoff again is Repair. Distribution files refresh while
# private app configuration, protocol state, and user.el survive.
mkdir -p "$recommended_root/apps/demo" "$recommended/kit"
printf ';; keep recommended app config\n' \
  > "$recommended_root/apps/demo/user.el"
printf 'keep recommended protocol state\n' > "$recommended_root/var/state"
printf ';; keep recommended overrides\n' > "$recommended_root/user.el"
make_payload "$recommended/kit/payload"
cp "$REPO_ROOT/device/install-recommended.el" \
  "$recommended/kit/install-recommended.el"
emacs -Q --batch \
  --eval "(setq user-emacs-directory \"$recommended/home/.emacs.d/\" jetpacs-bootstrap-vault-directory \"$recommended/vault\")" \
  -l "$recommended/kit/install-recommended.el" > /dev/null
assert_file "$recommended_root/apps/demo/user.el"
assert_file "$recommended_root/var/state"
assert_file "$recommended_root/user.el"
assert_absent "$recommended/kit"

printf 'onboarding-layout-test: PASS\n'
