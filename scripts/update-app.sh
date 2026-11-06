#!/bin/bash
# Updates Prometheus to the newest code on GitHub: it downloads the code, builds it on this Mac and
# replaces the app. The Update button in Settings runs this same file from inside the app. If your
# copy doesn't have that button yet, paste this into Terminal:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nilusitechtigris/Prometheus/main/scripts/update-app.sh)"
#
# It only ever moves forward. An older build can erase saved chats it can't read, so this leaves
# alone any copy that main doesn't contain. The app isn't touched unless the build worked.
# A new Mac only has bash 3.2, so this sticks to what that version can do.
set -euo pipefail

REPO_URL="https://github.com/nilusitechtigris/Prometheus.git"
BRANCH="main"
BUILT_APP="build/Prometheus.app"
LOG="$HOME/Library/Logs/Prometheus-update.log"
# The app reads this exit code from --build-only as "nothing to do". Matches AppUpdater.swift.
EXIT_UP_TO_DATE=3
# How long the app gets to quit, in fifths of a second.
QUIT_TIMEOUT=300

APP_PATH="/Applications/Prometheus.app"
REPO_DIR="$HOME/Prometheus"
MODE="full"
QUITTING_PID=""
NEWEST=""

# The app shows lines starting with → as progress, • as what's new and ✗ as what went wrong.
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "✗ $*"; exit 1; }
git_repo() { git -C "$REPO_DIR" "$@"; }

usage() {
    cat <<'USAGE'
Updates Prometheus to the newest code on GitHub.

Usage: update-app.sh [options]

  --dir PATH    Where the code lives (default: ~/Prometheus)
  --app PATH    The app to replace (default: /Applications/Prometheus.app)
  --help        Show this

The app itself uses these two:
  --build-only                 Download and build, but don't replace anything
  --install-when-closed PID    Wait for that process to quit, then replace the app
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir|--app|--install-when-closed)
                [ $# -ge 2 ] || die "$1 needs a value."
                case "$1" in
                    --dir) REPO_DIR="$2" ;;
                    --app) APP_PATH="$2" ;;
                    *)     MODE="install"; QUITTING_PID="$2" ;;
                esac
                shift 2
                ;;
            --build-only) MODE="build"; shift ;;
            --help|-h)    usage; exit 0 ;;
            *)            die "Unknown option: $1 (see --help)" ;;
        esac
    done
}

app_is_open() {
    pgrep -x LocalAIAgent >/dev/null 2>&1
}

# The commit the app was built from. Copies from before this script have none.
installed_commit() {
    /usr/libexec/PlistBuddy -c 'Print :PrometheusCommit' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
}

check_tools() {
    local developer
    developer="$(xcode-select -p 2>/dev/null || true)"
    if [ -z "$developer" ] || [ ! -x "$developer/usr/bin/git" ]; then
        die "The Command Line Tools are missing. Install them with: xcode-select --install"
    fi
}

# Finds out now, with nothing changed yet, rather than once the app has already quit.
check_can_replace() {
    local probe="$APP_PATH/Contents/.update-check"
    if [ ! -w "$(dirname "$APP_PATH")" ]; then
        die "This account can't change $(dirname "$APP_PATH"), so the app can't be replaced."
    fi
    if [ -d "$APP_PATH" ]; then
        if ! mkdir "$probe" 2>/dev/null; then
            die "macOS won't let this change $APP_PATH. If it asked, allow Prometheus under Privacy & Security › App Management, then try again."
        fi
        rmdir "$probe"
    fi
}

check_folder() {
    if ! grep -qs 'LocalAIAgent' "$REPO_DIR/Package.swift" || [ ! -e "$REPO_DIR/.git" ]; then
        die "$REPO_DIR isn't a copy of Prometheus, so it was left alone. Move it, or pick another place with --dir."
    fi
    if [ "$(git_repo symbolic-ref --short -q HEAD || true)" != "$BRANCH" ]; then
        die "$REPO_DIR isn't on $BRANCH, so it was left alone."
    fi
    if [ -n "$(git_repo status --porcelain --untracked-files=no)" ]; then
        die "$REPO_DIR has changes of its own, so it was left alone."
    fi
}

get_newest_code() {
    say "→ Looking for updates"
    if [ -e "$REPO_DIR" ]; then
        check_folder
        git_repo fetch --quiet origin "$BRANCH" 2>>"$LOG" \
            || die "Couldn't reach GitHub. Check your internet connection and try again."
    else
        git clone --quiet --branch "$BRANCH" "$REPO_URL" "$REPO_DIR" 2>>"$LOG" \
            || die "Couldn't reach GitHub. Check your internet connection and try again."
    fi
    NEWEST="$(git_repo rev-parse "refs/remotes/origin/$BRANCH")"
}

check_for_update() {
    local installed
    installed="$(installed_commit)"
    if [ "$installed" = "$NEWEST" ]; then
        say "✓ Prometheus is up to date"
        if [ "$MODE" = "build" ]; then
            exit "$EXIT_UP_TO_DATE"
        fi
        exit 0
    fi
    if [ -n "$installed" ]; then
        if ! git_repo merge-base --is-ancestor "$installed" "$NEWEST" 2>/dev/null; then
            die "This copy was built from ${installed:0:7}, which isn't on $BRANCH. Replacing it could lose saved chats, so it was left alone."
        fi
        git_repo log --no-merges --format='• %s' "$installed..$NEWEST" | tee -a "$LOG"
    fi
}

build_update() {
    say "→ Downloading the update"
    git_repo merge --quiet --ff-only "$NEWEST" 2>>"$LOG" || true
    if [ "$(git_repo rev-parse HEAD)" != "$NEWEST" ]; then
        die "$REPO_DIR has commits that aren't on $BRANCH, so it was left alone."
    fi
    say "→ Building the update"
    if ! make -C "$REPO_DIR" app 2>&1 | tee -a "$LOG"; then
        say "The details are in $LOG"
        die "The build failed, so nothing was replaced."
    fi
}

# Copies the new app in beside the old one first, so a failed copy leaves the old one as it was.
replace_app() {
    local new="$APP_PATH.new" old="$APP_PATH.old"
    rm -rf "$new" "$old" || return 1
    if ! ditto "$REPO_DIR/$BUILT_APP" "$new"; then
        rm -rf "$new"
        return 1
    fi
    if [ -e "$APP_PATH" ] && ! mv "$APP_PATH" "$old"; then
        rm -rf "$new"
        return 1
    fi
    if ! mv "$new" "$APP_PATH"; then
        mv "$old" "$APP_PATH" 2>/dev/null || true
        return 1
    fi
    rm -rf "$old"
}

# Opens the app whatever happens: the button's copy has already quit by now.
install_update() {
    local result=0
    say "→ Installing the update"
    if replace_app; then
        say "✓ Updated to $(installed_commit | cut -c 1-7)"
    else
        say "✗ Couldn't replace $APP_PATH, so this copy stays as it was."
        result=1
    fi
    if ! open "$APP_PATH"; then
        say "✗ Couldn't open $APP_PATH. Open it yourself from your Applications folder."
        result=1
    fi
    exit "$result"
}

wait_for_app_to_quit() {
    local ticks=0
    while kill -0 "$QUITTING_PID" 2>/dev/null; do
        ticks=$((ticks + 1))
        [ "$ticks" -le "$QUIT_TIMEOUT" ] || die "Prometheus didn't quit, so nothing was replaced."
        sleep 0.2
    done
}

# Never closes the app itself: it could be in the middle of a test.
wait_for_you_to_quit() {
    if ! app_is_open; then
        return 0
    fi
    if ! { : </dev/tty; } 2>/dev/null; then
        say "✓ The update is built. Quit Prometheus and run this again to finish."
        exit 0
    fi
    say "→ Quit Prometheus to finish. Waiting…"
    while app_is_open; do
        sleep 1
    done
}

main() {
    mkdir -p "$(dirname "$LOG")"
    parse_args "$@"
    if [ "$MODE" = "install" ]; then
        wait_for_app_to_quit
        install_update
    fi

    : >"$LOG"
    check_tools
    check_can_replace
    get_newest_code
    check_for_update
    build_update
    if [ "$MODE" = "full" ]; then
        wait_for_you_to_quit
        install_update
    fi
}

# Everything is in functions, so a download cut off halfway can't run half a script. It also means
# bash has read the whole file before the update pulls a new copy of it over the old one.
main "$@"
