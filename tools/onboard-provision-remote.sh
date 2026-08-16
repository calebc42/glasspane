#!/data/data/com.termux/files/usr/bin/bash
# Device-side Jetpacs installer.  It is used both by onboard-tablet.sh over
# SSH and by the setup kit staged from the Companion app.
#
#   install-jetpacs.sh install shared emacs PAYLOAD
#   install-jetpacs.sh install termux emacs PAYLOAD
#   install-jetpacs.sh install shared termux PAYLOAD
#   install-jetpacs.sh audit   shared emacs
#   install-jetpacs.sh remove  shared emacs
#   install-jetpacs.sh reset-home shared emacs
#
# "remove" removes the selected init.el seam and ~/.emacs.d/jetpacs, but keeps
# the managed early-init HOME/PATH block. "reset-home" is the separate,
# explicit operation that removes that early-init block. Neither operation
# deletes the user-content Vault.
set -euo pipefail
umask 077

export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:$PATH"

ACTION="${1:-install}"
VAULT_MODE="${2:-}"
EMACS_HOME_MODE="${3:-}"
PAYLOAD_DIR="${4:-}"

TERMUX_HOME="${JETPACS_TERMUX_HOME:-$HOME}"
TERMUX_BIN="${JETPACS_TERMUX_BIN:-/data/data/com.termux/files/usr/bin}"
SHARED_VAULT="${JETPACS_SHARED_VAULT:-/sdcard}"

HOME_BEGIN=';;; >>> Jetpacs managed: Android Emacs HOME >>>'
HOME_END=';;; <<< Jetpacs managed: Android Emacs HOME <<<'
INIT_BEGIN=';;; >>> Jetpacs managed: composition root >>>'
INIT_END=';;; <<< Jetpacs managed: composition root <<<'

log() { printf '[jetpacs-install] %s\n' "$*" >&2; }
die() { printf '[jetpacs-install] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage: install-jetpacs.sh ACTION VAULT-MODE EMACS-HOME [PAYLOAD]

  ACTION       install | audit | remove | reset-home
  VAULT-MODE   shared (/sdcard) | emacs | termux
  EMACS-HOME   emacs (Local Emacs) | termux (Termux-shared)
  PAYLOAD      setup-kit payload directory; required for install

VAULT-MODE and EMACS-HOME are independent. Every combination keeps
~/.emacs.d private; /sdcard can be a Vault but never Unix HOME. Install owns
~/.emacs.d/jetpacs and one marked init block. Existing init files are preserved
and backed up once as *.jetpacs-preinstall.
EOF
}

case "$ACTION" in
  install|audit|remove|reset-home) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage; die "unknown action: $ACTION" ;;
esac

find_emacs_home() {
  if [ -n "${JETPACS_EMACS_HOME:-}" ]; then
    EMACS_HOME="$JETPACS_EMACS_HOME"
    return
  fi
  local candidate
  for candidate in \
    /data/data/org.gnu.emacs/files \
    /data/user/0/org.gnu.emacs/files; do
    if [ -d "$candidate" ]; then
      EMACS_HOME="$candidate"
      return
    fi
  done
  die "Android Emacs's original HOME is not visible from Termux. Launch \
org.gnu.emacs once and confirm that it is the build sharing Termux's UID."
}

find_emacs_home
case "$EMACS_HOME" in
  /*) ;;
  *) die "Android Emacs HOME is not absolute: $EMACS_HOME" ;;
esac

case "$VAULT_MODE" in
  shared) VAULT="$SHARED_VAULT" ;;
  emacs|local)
    VAULT_MODE=emacs
    VAULT="$EMACS_HOME"
    ;;
  termux) VAULT="$TERMUX_HOME" ;;
  *) usage; die "VAULT-MODE must be 'shared', 'emacs', or 'termux'" ;;
esac

case "$EMACS_HOME_MODE" in
  emacs|local)
    EMACS_HOME_MODE=emacs
    EMACS_USER_HOME="$EMACS_HOME"
    BOOTSTRAP_MODE=local
    ;;
  termux|advanced|private)
    EMACS_HOME_MODE=termux
    EMACS_USER_HOME="$TERMUX_HOME"
    BOOTSTRAP_MODE=termux
    ;;
  *) usage; die "EMACS-HOME must be 'emacs' or 'termux'" ;;
esac

# .emacs.d may be in either private home, never in the Vault merely because it
# is /sdcard. Both roots become mutation boundaries, so fail closed on broad or
# relative spellings before creating or deleting anything.
case "$EMACS_USER_HOME" in
  /*) ;;
  *) die "private Emacs HOME is not absolute: $EMACS_USER_HOME" ;;
esac
EMACS_USER_HOME="${EMACS_USER_HOME%/}"
[ -n "$EMACS_USER_HOME" ] && [ "$EMACS_USER_HOME" != "/" ] \
  || die "refusing unsafe private Emacs HOME: ${EMACS_USER_HOME:-<empty>}"
case "$VAULT" in
  /*) ;;
  *) die "Vault is not absolute: $VAULT" ;;
esac
VAULT="${VAULT%/}"
[ -n "$VAULT" ] && [ "$VAULT" != "/" ] \
  || die "refusing unsafe Vault: ${VAULT:-<empty>}"

EMACS_USER_DOTDIR="$EMACS_USER_HOME/.emacs.d"
JETPACS_ROOT="$EMACS_USER_DOTDIR/jetpacs"
EXPECTED_ROOT="$EMACS_USER_HOME/.emacs.d/jetpacs"
[ "$JETPACS_ROOT" = "$EXPECTED_ROOT" ] \
  || die "internal root validation failed: $JETPACS_ROOT"

BOOTSTRAP_DOTDIR="${EMACS_HOME%/}/.emacs.d"
BOOTSTRAP_EARLY_INIT="$BOOTSTRAP_DOTDIR/early-init.el"
EMACS_USER_INIT="$EMACS_USER_DOTDIR/init.el"

# The other private home is a possible previous managed location. A mode
# switch must move durable state and retire its old init seam; otherwise both
# homes would remain plausible Jetpacs installations and drift would return.
if [ "$EMACS_HOME_MODE" = emacs ]; then
  ALTERNATE_USER_HOME="${TERMUX_HOME%/}"
else
  ALTERNATE_USER_HOME="${EMACS_HOME%/}"
fi
ALTERNATE_USER_DOTDIR="$ALTERNATE_USER_HOME/.emacs.d"
ALTERNATE_JETPACS_ROOT="$ALTERNATE_USER_DOTDIR/jetpacs"
ALTERNATE_USER_INIT="$ALTERNATE_USER_DOTDIR/init.el"
PREVIOUS_MANAGED_ROOT=""
PREVIOUS_MANAGED_INIT=""
if [ "$ALTERNATE_JETPACS_ROOT" != "$JETPACS_ROOT" ] \
     && [ -f "$ALTERNATE_JETPACS_ROOT/install.conf" ]; then
  PREVIOUS_MANAGED_ROOT="$ALTERNATE_JETPACS_ROOT"
  PREVIOUS_MANAGED_INIT="$ALTERNATE_USER_INIT"
fi
PRE_SWITCH_TARGET=""

if [ "$ACTION" != audit ] && command -v pidof >/dev/null 2>&1 \
     && pidof org.gnu.emacs >/dev/null 2>&1; then
  die "Android Emacs is running. Force-stop org.gnu.emacs before changing \
its startup files or migrating its receipt database, then retry."
fi

temp_file() {
  mktemp "${TMPDIR:-$TERMUX_HOME}/jetpacs-install.XXXXXX"
}

backup_once() {
  local file="$1" backup
  [ -f "$file" ] || return 0
  backup="$file.jetpacs-preinstall"
  if [ ! -e "$backup" ]; then
    cp -p "$file" "$backup"
    log "backed up $file -> $backup"
  fi
}

# Remove one complete block bounded by BEGIN/END.  Missing boundaries are
# fine; malformed or duplicate boundaries are errors, never an excuse to
# rewrite a user's init with guessed structure.
without_block() {
  local input="$1" output="$2" begin="$3" end="$4"
  if [ ! -f "$input" ]; then
    : > "$output"
    return
  fi
  awk -v begin="$begin" -v end="$end" '
    $0 == begin {
      if (inside || seen_begin) exit 42
      seen_begin = 1
      inside = 1
      next
    }
    $0 == end {
      if (!inside || seen_end) exit 43
      seen_end = 1
      inside = 0
      next
    }
    !inside { print }
    END { if (inside || seen_begin != seen_end) exit 44 }
  ' "$input" > "$output" \
    || die "malformed or duplicate managed block in $input; left it untouched"
}

validate_block_file() {
  local block="$1" begin="$2" end="$3"
  [ -f "$block" ] || die "missing managed block template: $block"
  [ "$(head -n 1 "$block")" = "$begin" ] \
    || die "$block does not begin with the expected marker"
  [ "$(tail -n 1 "$block")" = "$end" ] \
    || die "$block does not end with the expected marker"
}

validate_existing_block() {
  local file="$1" begin="$2" end="$3" stripped
  stripped="$(temp_file)"
  without_block "$file" "$stripped" "$begin" "$end"
  rm -f "$stripped"
}

install_block() {
  local file="$1" block="$2" begin="$3" end="$4"
  local stripped combined mode=""
  validate_block_file "$block" "$begin" "$end"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && ! grep -qFx "$begin" "$file"; then
    backup_once "$file"
  fi
  stripped="$(temp_file)"
  combined="$(temp_file)"
  without_block "$file" "$stripped" "$begin" "$end"
  if [ -f "$file" ]; then mode="$(stat -c '%a' "$file" 2>/dev/null || true)"; fi
  {
    if [ -s "$stripped" ]; then
      cat "$stripped"
      printf '\n'
    fi
    cat "$block"
  } > "$combined"
  mv "$combined" "$file"
  [ -z "$mode" ] || chmod "$mode" "$file"
  rm -f "$stripped"
}

remove_block() {
  local file="$1" begin="$2" end="$3" stripped mode=""
  [ -f "$file" ] || return 0
  grep -qFx "$begin" "$file" || return 0
  stripped="$(temp_file)"
  without_block "$file" "$stripped" "$begin" "$end"
  mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
  mv "$stripped" "$file"
  [ -z "$mode" ] || chmod "$mode" "$file"
}

replace_tree() {
  local source="$1" destination="$2" staged
  [ -d "$source" ] || die "missing payload directory: $source"
  staged="${destination}.jetpacs-new-$$"
  rm -rf "$staged"
  mkdir -p "$staged"
  (cd "$source" && tar -cf - .) | (cd "$staged" && tar -xf -)
  rm -rf "$destination"
  mv "$staged" "$destination"
}

# Migration copies cross Android's private/shared-storage boundary in shared
# mode.  Build one-shot destinations beside their final path and rename only
# after a complete copy, so failure cannot masquerade as a usable copy.
copy_tree_once() {
  local source="$1" destination="$2" staged
  [ -d "$source" ] || return 0
  [ ! -e "$destination" ] || return 0
  staged="${destination}.jetpacs-new"
  rm -rf "$staged"
  mkdir -p "$staged"
  if (cd "$source" && tar -cf - .) | (cd "$staged" && tar -xf -); then
    mv "$staged" "$destination"
  else
    rm -rf "$staged"
    die "could not copy legacy directory $source; startup was not changed"
  fi
}

copy_file_once() {
  local source="$1" destination="$2" staged
  [ -f "$source" ] || return 0
  [ ! -e "$destination" ] || return 0
  staged="${destination}.jetpacs-new"
  rm -f "$staged"
  if cp -p "$source" "$staged"; then
    mv "$staged" "$destination"
  else
    rm -f "$staged"
    die "could not copy legacy file $source; startup was not changed"
  fi
}

merge_tree() {
  local source="$1" destination="$2"
  [ -d "$source" ] || return 0
  mkdir -p "$destination"
  if ! (cd "$source" && tar -cf - .) | (cd "$destination" && tar -xf -); then
    die "could not migrate managed state from $source; startup was not changed"
  fi
}

copy_file_replace() {
  local source="$1" destination="$2" staged
  [ -f "$source" ] || return 0
  staged="${destination}.jetpacs-new"
  rm -f "$staged"
  if cp -p "$source" "$staged"; then
    mv "$staged" "$destination"
  else
    rm -f "$staged"
    die "could not migrate managed file $source; startup was not changed"
  fi
}

migrate_previous_managed_home() {
  local migration="$JETPACS_ROOT/migration"
  [ -n "$PREVIOUS_MANAGED_ROOT" ] || return 0
  case "$PREVIOUS_MANAGED_ROOT" in
    "$ALTERNATE_USER_HOME/.emacs.d/jetpacs") ;;
    *) die "refusing an unvalidated previous managed root: $PREVIOUS_MANAGED_ROOT" ;;
  esac

  mkdir -p "$migration"
  copy_tree_once "$PREVIOUS_MANAGED_ROOT" \
    "$migration/previous-home-jetpacs"
  [ -d "$migration/previous-home-jetpacs" ] \
    || die "previous managed root was not archived: $PREVIOUS_MANAGED_ROOT"

  # The previous unified install is authoritative. Distribution-owned trees
  # are refreshed from the payload later; carry forward only durable state.
  merge_tree "$PREVIOUS_MANAGED_ROOT/apps" "$JETPACS_ROOT/apps"
  merge_tree "$PREVIOUS_MANAGED_ROOT/var" "$JETPACS_ROOT/var"
  copy_file_replace "$PREVIOUS_MANAGED_ROOT/apps.el" "$JETPACS_ROOT/apps.el"
  copy_file_replace "$PREVIOUS_MANAGED_ROOT/user.el" "$JETPACS_ROOT/user.el"
  log "migrated durable Jetpacs state from $PREVIOUS_MANAGED_ROOT"

  if [ -n "$PRE_SWITCH_TARGET" ]; then
    copy_tree_once "$PRE_SWITCH_TARGET" "$migration/pre-switch-target"
    [ -d "$migration/pre-switch-target" ] \
      || die "pre-switch target was not archived: $PRE_SWITCH_TARGET"
  fi
}

retire_previous_managed_home() {
  local archive="$JETPACS_ROOT/migration/previous-home-jetpacs"
  [ -n "$PREVIOUS_MANAGED_ROOT" ] || return 0

  # The early-init selection has already changed at this point. Remove only
  # Jetpacs's marked seam from the inactive home and leave all user init forms.
  remove_block "$PREVIOUS_MANAGED_INIT" "$INIT_BEGIN" "$INIT_END"
  if [ -d "$archive" ] && [ -e "$PREVIOUS_MANAGED_ROOT" ]; then
    case "$PREVIOUS_MANAGED_ROOT" in
      "$ALTERNATE_USER_HOME/.emacs.d/jetpacs") rm -rf "$PREVIOUS_MANAGED_ROOT" ;;
      *) die "refusing to retire an unvalidated root: $PREVIOUS_MANAGED_ROOT" ;;
    esac
    log "retired the previous managed root (recovery copy kept under migration/)"
  fi
  if [ -n "$PRE_SWITCH_TARGET" ] \
       && [ -d "$JETPACS_ROOT/migration/pre-switch-target" ]; then
    case "$PRE_SWITCH_TARGET" in
      "$EMACS_USER_DOTDIR/.jetpacs-pre-switch") rm -rf "$PRE_SWITCH_TARGET" ;;
      *) die "refusing to retire an unvalidated pre-switch target: $PRE_SWITCH_TARGET" ;;
    esac
  fi
}

legacy_paths() {
  local path result=""
  for path in \
    "$TERMUX_HOME/jetpacs" \
    "$SHARED_VAULT/Documents/jetpacs" \
    "$BOOTSTRAP_DOTDIR/jetpacs" \
    "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" \
    "$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite" \
    "$BOOTSTRAP_DOTDIR/jetpacs-onboard-init.el"; do
    if [ -e "$path" ] && [ "$path" != "$JETPACS_ROOT" ]; then
      if [ -n "$result" ]; then result="$result|"; fi
      result="$result$path"
    fi
  done
  printf '%s' "$result"
}

migrate_old_private_state() {
  local harness="$BOOTSTRAP_DOTDIR/jetpacs-onboard-init.el"
  local old_init="$BOOTSTRAP_DOTDIR/init.el"
  local migration="$JETPACS_ROOT/migration" old_root old_apps_file suffix
  local receipt_marker="$JETPACS_ROOT/var/.legacy-receipts-migrating"
  mkdir -p "$migration"

  # On the first unified install, carry forward the state the retired harness
  # wrote relative to Android Emacs's original user-emacs-directory. Once an
  # install.conf exists, the selected tree is authoritative and stale legacy
  # state must never overwrite it on an update.
  if [ "${FIRST_UNIFIED_INSTALL:-no}" = yes ]; then
    old_root="$BOOTSTRAP_DOTDIR/jetpacs"
    if [ "$old_root" != "$JETPACS_ROOT" ] && [ -d "$old_root/apps" ]; then
      mkdir -p "$JETPACS_ROOT/apps"
      (cd "$old_root/apps" && tar -cf - .) \
        | (cd "$JETPACS_ROOT/apps" && tar -xf -)
      log "migrated app-owned configuration from $old_root/apps"
    fi
    for old_apps_file in \
      "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" \
      "$EMACS_USER_DOTDIR/jetpacs-apps.el"; do
      if [ -f "$old_apps_file" ] && [ ! -f "$JETPACS_ROOT/apps.el" ]; then
        copy_file_once "$old_apps_file" "$JETPACS_ROOT/apps.el"
        log "migrated installed-app registry from $old_apps_file"
      fi
    done
    if [ -f "$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite" ] \
         && { [ ! -f "$JETPACS_ROOT/var/receipts.sqlite" ] \
              || [ -f "$receipt_marker" ]; }; then
      : > "$receipt_marker"
      for suffix in '' '-wal' '-shm'; do
        if [ -f "$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite$suffix" ] \
             && [ ! -f "$JETPACS_ROOT/var/receipts.sqlite$suffix" ]; then
          copy_file_once \
            "$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite$suffix" \
            "$JETPACS_ROOT/var/receipts.sqlite$suffix"
        fi
      done
      rm -f "$receipt_marker"
      log "migrated durable receipts into $JETPACS_ROOT/var"
    fi
    if [ "$old_root" != "$JETPACS_ROOT" ] && [ -d "$old_root" ]; then
      copy_tree_once "$old_root" "$migration/app-private-jetpacs"
      log "archived the retired app-private Jetpacs subtree under migration/"
    fi
    copy_file_once "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" \
      "$migration/app-private-jetpacs-apps.el"
    if [ "$EMACS_USER_DOTDIR/jetpacs-apps.el" \
         != "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" ]; then
      copy_file_once "$EMACS_USER_DOTDIR/jetpacs-apps.el" \
        "$migration/selected-home-jetpacs-apps.el"
    fi
    for suffix in '' '-wal' '-shm'; do
      copy_file_once "$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite$suffix" \
        "$migration/app-private-jetpacs-receipts.sqlite$suffix"
    done
  fi

  if [ -f "$harness" ]; then
    copy_file_once "$harness" "$migration/jetpacs-onboard-init.el"
  fi
  if [ -f "$old_init" ] \
       && awk 'index($0, "jetpacs-onboard-init.el") { found=1 } END { exit !found }' "$old_init"; then
    backup_once "$old_init"
  fi
}

# Run only after the early-init redirect has been installed.  Every legacy
# object is removed only when its recovery copy exists; cleanup failures are
# warnings because the new installation is already complete and authoritative.
retire_old_private_state() {
  local harness="$BOOTSTRAP_DOTDIR/jetpacs-onboard-init.el"
  local old_init="$BOOTSTRAP_DOTDIR/init.el" stripped mode=""
  local migration="$JETPACS_ROOT/migration" old_root suffix source archive

  if [ "${FIRST_UNIFIED_INSTALL:-no}" = yes ]; then
    old_root="$BOOTSTRAP_DOTDIR/jetpacs"
    if [ "$old_root" != "$JETPACS_ROOT" ] \
         && [ -d "$old_root" ] \
         && [ -d "$migration/app-private-jetpacs" ]; then
      if rm -rf "$old_root"; then
        log "retired the old app-private Jetpacs subtree (copy kept under migration/)"
      else
        log "WARNING: could not remove legacy directory $old_root"
      fi
    fi
    for source in \
      "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" \
      "$EMACS_USER_DOTDIR/jetpacs-apps.el"; do
      if [ "$source" = "$BOOTSTRAP_DOTDIR/jetpacs-apps.el" ]; then
        archive="$migration/app-private-jetpacs-apps.el"
      else
        archive="$migration/selected-home-jetpacs-apps.el"
      fi
      if [ -f "$source" ] && [ -f "$archive" ]; then
        if ! rm -f "$source"; then
          log "WARNING: could not remove legacy file $source"
        fi
      fi
    done
    for suffix in '' '-wal' '-shm'; do
      source="$BOOTSTRAP_DOTDIR/jetpacs-receipts.sqlite$suffix"
      archive="$migration/app-private-jetpacs-receipts.sqlite$suffix"
      if [ -f "$source" ] && [ -f "$archive" ]; then
        if ! rm -f "$source"; then
          log "WARNING: could not remove legacy file $source"
        fi
      fi
    done
  fi

  if [ -f "$harness" ] && [ -f "$migration/jetpacs-onboard-init.el" ]; then
    if rm -f "$harness"; then
      log "retired the old app-private onboarding harness (copy kept under migration/)"
    else
      log "WARNING: could not remove legacy harness $harness"
    fi
  fi
  if [ -f "$old_init" ] && awk 'index($0, "jetpacs-onboard-init.el") { found=1 } END { exit !found }' "$old_init"; then
    if stripped="$(temp_file)"; then
      if awk '!index($0, "jetpacs-onboard-init.el")' "$old_init" > "$stripped"; then
        mode="$(stat -c '%a' "$old_init" 2>/dev/null || true)"
        if mv "$stripped" "$old_init"; then
          if [ -z "$mode" ] || chmod "$mode" "$old_init"; then
            log "removed the retired harness load line from $old_init"
          else
            log "WARNING: could not restore the mode on $old_init"
          fi
        else
          rm -f "$stripped"
          log "WARNING: could not replace legacy init $old_init"
        fi
      else
        rm -f "$stripped"
        log "WARNING: could not prepare legacy init cleanup for $old_init"
      fi
    else
      log "WARNING: could not allocate a temporary file for legacy init cleanup"
    fi
  fi
}

install_payload() {
  local home_template seam_template conf_tmp
  [ -n "$PAYLOAD_DIR" ] || die "install requires a PAYLOAD directory"
  [ -d "$PAYLOAD_DIR" ] || die "payload directory not found: $PAYLOAD_DIR"
  [ -f "$PAYLOAD_DIR/init.el" ] || die "payload is missing init.el"
  [ -f "$PAYLOAD_DIR/emacs/ebp.el" ] \
    || die "payload is missing emacs/ebp.el"
  [ -f "$PAYLOAD_DIR/emacs/jetpacs-files.el" ] \
    || die "payload is missing emacs/jetpacs-files.el"
  [ -d "$PAYLOAD_DIR/org/org-mode-walkthrough" ] \
    || die "payload is missing the Org walkthrough"

  home_template="$PAYLOAD_DIR/bootstrap/early-init-$BOOTSTRAP_MODE.el"
  seam_template="$PAYLOAD_DIR/bootstrap/init-seam.el"
  validate_block_file "$home_template" "$HOME_BEGIN" "$HOME_END"
  validate_block_file "$seam_template" "$INIT_BEGIN" "$INIT_END"
  # Reject ambiguous ownership before copying any payload or changing either
  # startup file. Jetpacs manages exactly one instance of each marked block.
  validate_existing_block "$EMACS_USER_INIT" "$INIT_BEGIN" "$INIT_END"
  validate_existing_block "$BOOTSTRAP_EARLY_INIT" "$HOME_BEGIN" "$HOME_END"

  if [ ! -w "$VAULT" ]; then
    die "Vault $VAULT is not writable from Termux. For /sdcard, run \
'termux-setup-storage', approve the Files permission, then retry."
  fi
  if [ -f "$JETPACS_ROOT/install.conf" ]; then
    FIRST_UNIFIED_INSTALL=no
  elif [ -n "$PREVIOUS_MANAGED_ROOT" ]; then
    FIRST_UNIFIED_INSTALL=no
    PRE_SWITCH_TARGET="$EMACS_USER_DOTDIR/.jetpacs-pre-switch"
    if [ -e "$PRE_SWITCH_TARGET" ]; then
      # A prior attempt stopped before flipping early-init. The previous HOME
      # is still active, so discard only the known incomplete target and reuse
      # the recovery staging tree.
      if [ -e "$JETPACS_ROOT" ]; then
        case "$JETPACS_ROOT" in
          "$EMACS_USER_DOTDIR/jetpacs") rm -rf "$JETPACS_ROOT" ;;
          *) die "refusing to replace an unvalidated retry target: $JETPACS_ROOT" ;;
        esac
      fi
    elif [ -e "$JETPACS_ROOT" ]; then
      mv "$JETPACS_ROOT" "$PRE_SWITCH_TARGET"
    else
      PRE_SWITCH_TARGET=""
    fi
  else
    FIRST_UNIFIED_INSTALL=yes
  fi
  mkdir -p "$EMACS_USER_DOTDIR" "$BOOTSTRAP_DOTDIR" "$JETPACS_ROOT"

  # A previous unified install in the other private HOME is migrated before
  # any startup seam changes. This is independent of where the Vault lives.
  migrate_previous_managed_home

  # Replace only distribution-owned subtrees.  apps/, var/, user.el, and any
  # future app-owned directories survive an update.
  replace_tree "$PAYLOAD_DIR/emacs" "$JETPACS_ROOT/emacs"
  replace_tree "$PAYLOAD_DIR/org" "$JETPACS_ROOT/org"
  if [ -d "$PAYLOAD_DIR/examples" ]; then
    replace_tree "$PAYLOAD_DIR/examples" "$JETPACS_ROOT/examples"
  fi
  mkdir -p "$JETPACS_ROOT/apps" "$JETPACS_ROOT/var"
  cp "$PAYLOAD_DIR/init.el" "$JETPACS_ROOT/init.el.new"
  mv "$JETPACS_ROOT/init.el.new" "$JETPACS_ROOT/init.el"

  # Copy durable legacy state before changing either startup file.  In shared
  # mode this can cross filesystems; a failure therefore leaves the old setup
  # active and safe to retry.
  migrate_old_private_state

  conf_tmp="$(temp_file)"
  {
    printf 'format=3\n'
    printf 'vault_mode=%s\n' "$VAULT_MODE"
    printf 'vault=%s\n' "$VAULT"
    printf 'home_mode=%s\n' "$EMACS_HOME_MODE"
    printf 'home=%s\n' "$EMACS_USER_HOME"
    printf 'emacs_home=%s\n' "$EMACS_HOME"
    printf 'root=%s\n' "$JETPACS_ROOT"
  } > "$conf_tmp"
  mv "$conf_tmp" "$JETPACS_ROOT/install.conf"

  # Wire the selected normal init first; flip Android Emacs to that HOME last.
  # A crash between the two therefore leaves either the old setup or a fully
  # populated new root, never an early-init redirect into an empty directory.
  install_block "$EMACS_USER_INIT" "$seam_template" "$INIT_BEGIN" "$INIT_END"
  install_block "$BOOTSTRAP_EARLY_INIT" "$home_template" "$HOME_BEGIN" "$HOME_END"
  retire_old_private_state
  retire_previous_managed_home
  log "installed $JETPACS_ROOT with Unix HOME=$EMACS_USER_HOME and Vault=$VAULT"
}

remove_installation() {
  remove_block "$EMACS_USER_INIT" "$INIT_BEGIN" "$INIT_END"
  case "$JETPACS_ROOT" in
    "$EMACS_USER_HOME/.emacs.d/jetpacs") ;;
    *) die "refusing to delete an unvalidated root: $JETPACS_ROOT" ;;
  esac
  if [ -e "$JETPACS_ROOT" ]; then
    rm -rf "$JETPACS_ROOT"
    log "removed $JETPACS_ROOT"
  fi
  log "kept the managed HOME/PATH block in $BOOTSTRAP_EARLY_INIT"
}

reset_home() {
  remove_block "$BOOTSTRAP_EARLY_INIT" "$HOME_BEGIN" "$HOME_END"
  log "removed the Android Emacs HOME/PATH block; selected files were preserved"
}

case "$ACTION" in
  install) install_payload ;;
  remove) remove_installation ;;
  reset-home) reset_home ;;
  audit) : ;;
esac

ELISP_FILES=0
if [ -d "$JETPACS_ROOT/emacs" ]; then
  ELISP_FILES="$(find "$JETPACS_ROOT/emacs" -name '*.el' | wc -l | tr -d ' ')"
fi
PYLSP_BIN="$(command -v pylsp 2>/dev/null || true)"
HOME_SEAM_COUNT=0
INIT_SEAM_COUNT=0
if [ -f "$BOOTSTRAP_EARLY_INIT" ]; then
  HOME_SEAM_COUNT="$(grep -cFx "$HOME_BEGIN" "$BOOTSTRAP_EARLY_INIT" || true)"
fi
if [ -f "$EMACS_USER_INIT" ]; then
  INIT_SEAM_COUNT="$(grep -cFx "$INIT_BEGIN" "$EMACS_USER_INIT" || true)"
fi
if [ -d "$JETPACS_ROOT/emacs" ] && [ -f "$JETPACS_ROOT/init.el" ]; then
  ROOT_STATE=installed
else
  ROOT_STATE=missing
fi
if [ -w "$VAULT" ]; then VAULT_WRITABLE=yes; else VAULT_WRITABLE=no; fi
LEGACY_HARNESS="$BOOTSTRAP_DOTDIR/jetpacs-onboard-init.el"

# Machine-readable report consumed by onboard-tablet.sh.  Values contain no
# newlines; LEGACY_PATHS is pipe-separated so paths may still contain spaces.
echo "REPORT_ACTION=$ACTION"
echo "REPORT_VAULT_MODE=$VAULT_MODE"
echo "REPORT_VAULT=$VAULT"
echo "REPORT_VAULT_WRITABLE=$VAULT_WRITABLE"
echo "REPORT_EMACS_HOME_MODE=$EMACS_HOME_MODE"
echo "REPORT_EMACS_USER_HOME=$EMACS_USER_HOME"
echo "REPORT_EMACS_USER_DOTDIR=$EMACS_USER_DOTDIR"
echo "REPORT_JETPACS_ROOT=$JETPACS_ROOT"
echo "REPORT_ROOT_STATE=$ROOT_STATE"
echo "REPORT_ELISP_DIR=$JETPACS_ROOT/emacs"
echo "REPORT_ELISP_FILES=$ELISP_FILES"
echo "REPORT_ORG_DIR=$JETPACS_ROOT/org"
echo "REPORT_EXAMPLES_DIR=$JETPACS_ROOT/examples"
echo "REPORT_EMACS_HOME=$EMACS_HOME"
echo "REPORT_BOOTSTRAP_EARLY_INIT=$BOOTSTRAP_EARLY_INIT"
echo "REPORT_HOME_SEAM_COUNT=$HOME_SEAM_COUNT"
echo "REPORT_INIT_DEST=$EMACS_USER_INIT"
echo "REPORT_INIT_SEAM_COUNT=$INIT_SEAM_COUNT"
echo "REPORT_LEGACY_HARNESS=$LEGACY_HARNESS"
echo "REPORT_LEGACY_HARNESS_PRESENT=$([ -f "$LEGACY_HARNESS" ] && echo yes || echo no)"
echo "REPORT_PYLSP_BIN=$PYLSP_BIN"
echo "REPORT_ALTERNATE_JETPACS_ROOT=$ALTERNATE_JETPACS_ROOT"
echo "REPORT_LEGACY_PATHS=$(legacy_paths)"
