#!/bin/bash
# Sets up Prometheus on a Mac with nothing on it: Command Line Tools, Homebrew, Ollama, Node, the
# app itself and a first model. On a new Mac, paste this into Terminal:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nilusitechtigris/Prometheus/main/scripts/setup-mac.sh)"
#
# It's safe to run again: each step checks first and skips what's already done.
# A new Mac only has bash 3.2, so this sticks to what that version can do.
set -euo pipefail

REPO_URL="https://github.com/nilusitechtigris/Prometheus.git"
HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_BIN="/opt/homebrew/bin"
APP_PATH="/Applications/Prometheus.app"
OLLAMA_URL="http://127.0.0.1:11434"
CLT_PATH="/Library/Developer/CommandLineTools"
# softwareupdate only offers the Command Line Tools while this file exists.
CLT_TRIGGER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
MIN_MACOS=14
MIN_FREE_GB=10
CLT_DIALOG_TIMEOUT=2700

REPO_DIR=""
WANT_MODEL=1
WANT_MLX=0
ASSUME_YES=0
DRY_RUN=0
MODEL=""
MODEL_SIZE=""
MEMORY_GB=0
CURRENT_STEP=""
SUDO_KEEPALIVE=""
CLT_TRIGGER_SET=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }
step() { CURRENT_STEP="$1"; printf '\n→ %s\n' "$1"; }

# Runs a command, or with --dry-run only shows it.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  would run: %s\n' "$*"
    else
        "$@"
    fi
}

usage() {
    cat <<'USAGE'
Sets up Prometheus on a Mac, starting from nothing.

Usage: setup-mac.sh [options]

  --dir PATH    Where to put the code (default: ~/Prometheus)
  --no-model    Don't download a first model
  --mlx         Also install MLX LM, to run MLX models
  --yes         Don't ask before starting
  --dry-run     Show what would happen without changing anything
  --help        Show this

To pass these to the one-line install, put -- after it:
  /bin/bash -c "$(curl -fsSL <script url>)" -- --no-model
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir)
                [ $# -ge 2 ] || die "--dir needs a path."
                REPO_DIR="$2"
                shift 2
                ;;
            --no-model) WANT_MODEL=0; shift ;;
            --mlx)      WANT_MLX=1; shift ;;
            --yes|-y)   ASSUME_YES=1; shift ;;
            --dry-run)  DRY_RUN=1; shift ;;
            --help|-h)  usage; exit 0 ;;
            *)          die "Unknown option: $1 (see --help)" ;;
        esac
    done
}

finish() {
    local status=$?
    if [ -n "$SUDO_KEEPALIVE" ]; then
        kill "$SUDO_KEEPALIVE" 2>/dev/null || true
    fi
    if [ "$CLT_TRIGGER_SET" = 1 ]; then
        sudo -n rm -f "$CLT_TRIGGER" 2>/dev/null || true
    fi
    if [ "$status" -ne 0 ] && [ -n "$CURRENT_STEP" ]; then
        printf '\nSetup stopped at: %s\nFix that and run this again. It picks up where it left off.\n' "$CURRENT_STEP" >&2
    fi
}

is_checkout() {
    grep -qs 'LocalAIAgent' "$1/Package.swift"
}

# Finds the checkout this script sits in. There's none when it arrives through curl.
checkout_around_script() {
    local source="${BASH_SOURCE[0]:-}" root
    if [ -z "$source" ] || [ ! -f "$source" ]; then
        return 1
    fi
    root="$(cd "$(dirname "$source")/.." && pwd)"
    is_checkout "$root" || return 1
    printf '%s\n' "$root"
}

have_command_line_tools() {
    local developer
    # Asks xcode-select rather than git or swift: on a new Mac those are stubs that open a dialog.
    developer="$(xcode-select -p 2>/dev/null)" || return 1
    [ -x "$developer/usr/bin/git" ]
}

app_is_open() {
    pgrep -x LocalAIAgent >/dev/null 2>&1
}

ollama_is_up() {
    curl -fsS --max-time 2 "$OLLAMA_URL/api/version" >/dev/null 2>&1
}

check_mac() {
    [ "$(uname -s)" = "Darwin" ] || die "This script is for macOS."
    [ "$(id -u)" -ne 0 ] || die "Run this as yourself, without sudo. It asks for your password when it needs to."
    [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || die "Prometheus needs an Apple Silicon Mac."

    local version free_gb
    version="$(sw_vers -productVersion)"
    [ "${version%%.*}" -ge "$MIN_MACOS" ] || die "Prometheus needs macOS $MIN_MACOS or later, and this Mac has $version."

    free_gb="$(df -g / | awk 'NR == 2 { print $4 }')"
    [ "$free_gb" -ge "$MIN_FREE_GB" ] || die "This needs about $MIN_FREE_GB GB of free disk space, and there's $free_gb GB."

    curl -fsS --head --max-time 15 https://github.com >/dev/null 2>&1 \
        || die "Can't reach github.com. Check your internet connection and run this again."
}

# The same picks the README suggests: 16 GB fits Qwen3 4B Instruct, and less gets the 1.7B.
choose_model() {
    MEMORY_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    if [ "$MEMORY_GB" -ge 16 ]; then
        MODEL="qwen3:4b-instruct-2507-q4_K_M"
        MODEL_SIZE="2.5 GB"
    else
        MODEL="qwen3:1.7b"
        MODEL_SIZE="1.4 GB"
    fi
}

choose_folder() {
    if [ -z "$REPO_DIR" ]; then
        REPO_DIR="$(checkout_around_script || true)"
    fi
    if [ -z "$REPO_DIR" ]; then
        REPO_DIR="$HOME/Prometheus"
    fi
    if [ -e "$REPO_DIR" ] && ! is_checkout "$REPO_DIR"; then
        die "$REPO_DIR already exists and isn't Prometheus. Pick another place with --dir."
    fi
}

show_plan() {
    say "Prometheus setup"
    say ""
    say "This installs whatever's missing: the Command Line Tools, Homebrew, Ollama and Node."
    if [ "$WANT_MLX" = 1 ]; then
        say "It also installs MLX LM."
    fi
    say "Then it puts the code in $REPO_DIR, builds the app into /Applications and opens it."
    if [ "$WANT_MODEL" = 1 ]; then
        say "This Mac has $MEMORY_GB GB of memory, so the first model is $MODEL ($MODEL_SIZE)."
    fi
    if [ "$DRY_RUN" = 1 ]; then
        say ""
        say "Dry run: nothing will change."
    fi
}

# Reads from the terminal, so this also works when the script arrives through a pipe.
confirm_start() {
    local reply
    if [ "$ASSUME_YES" = 1 ] || [ "$DRY_RUN" = 1 ]; then
        return 0
    fi
    if ! { : </dev/tty; } 2>/dev/null; then
        return 0
    fi
    printf '\nStart? [Y/n] ' >/dev/tty
    read -r reply </dev/tty || return 0
    case "$reply" in
        [nN]*) say "Nothing was changed."; exit 0 ;;
    esac
}

# Asks for the password once, up front, so the rest can run while you're away.
get_sudo_if_needed() {
    if [ "$DRY_RUN" = 1 ] || { have_command_line_tools && [ -x "$BREW_BIN/brew" ]; }; then
        return 0
    fi
    case " $(id -Gn) " in
        *" admin "*) ;;
        *) die "This account isn't an administrator, and installing the developer tools needs one." ;;
    esac
    say ""
    say "Your Mac password is needed to install the developer tools. Nothing shows as you type it."
    sudo -v || die "Couldn't get administrator rights."
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || true; sleep 50; done ) &
    SUDO_KEEPALIVE=$!
}

keep_mac_awake() {
    if [ "$DRY_RUN" = 0 ]; then
        caffeinate -i -w "$$" &
    fi
}

install_command_line_tools() {
    step "Command Line Tools"
    if have_command_line_tools; then
        ok "Already installed"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        say "  would install them with softwareupdate"
        return 0
    fi

    # The quiet route, the same one Homebrew uses: no dialog to sit and wait for.
    local label
    CLT_TRIGGER_SET=1
    sudo touch "$CLT_TRIGGER"
    label="$(softwareupdate -l 2>/dev/null \
        | grep -B 1 -E 'Command Line Tools' \
        | awk -F'*' '/^ *\*/ { print $2 }' \
        | sed -e 's/^ *Label: //' -e 's/^ *//' \
        | sort -V \
        | tail -n 1)" || true
    if [ -n "$label" ]; then
        say "  Installing $label"
        if sudo softwareupdate -i "$label" --verbose; then
            sudo xcode-select --switch "$CLT_PATH"
        else
            warn "softwareupdate didn't finish."
        fi
    fi
    sudo rm -f "$CLT_TRIGGER"
    CLT_TRIGGER_SET=0

    if ! have_command_line_tools; then
        wait_for_clt_dialog
    fi
    ok "Installed"
}

wait_for_clt_dialog() {
    local waited=0
    xcode-select --install 2>/dev/null || true
    say "  Click Install in the window that opened, then agree to the license. Waiting for it to finish…"
    until have_command_line_tools; do
        sleep 10
        waited=$((waited + 10))
        [ "$waited" -lt "$CLT_DIALOG_TIMEOUT" ] || die "The Command Line Tools still aren't installed."
    done
}

install_homebrew() {
    step "Homebrew"
    if [ -x "$BREW_BIN/brew" ]; then
        ok "Already installed"
    elif [ "$DRY_RUN" = 1 ]; then
        say "  would install it from $HOMEBREW_INSTALLER"
    else
        # Fetched first, because a failed download inside `bash -c "$(curl …)"` would look like success.
        local installer
        installer="$(curl -fsSL "$HOMEBREW_INSTALLER")"
        NONINTERACTIVE=1 /bin/bash -c "$installer"
        [ -x "$BREW_BIN/brew" ] || die "Homebrew's installer finished, but $BREW_BIN/brew isn't there."
        ok "Installed"
    fi
    add_homebrew_to_path
}

# Homebrew leaves this step to you, and new Terminal windows can't find it without it.
add_homebrew_to_path() {
    local profile="${ZDOTDIR:-$HOME}/.zprofile"
    case "${SHELL:-}" in
        */bash) profile="$HOME/.bash_profile" ;;
    esac
    if ! grep -qs 'brew shellenv' "$profile"; then
        if [ "$DRY_RUN" = 1 ]; then
            say "  would add Homebrew to $profile"
        else
            printf '\n# Homebrew\neval "$(%s/brew shellenv)"\n' "$BREW_BIN" >>"$profile"
            ok "Added to $profile"
        fi
    fi
    if [ -x "$BREW_BIN/brew" ]; then
        eval "$("$BREW_BIN/brew" shellenv)"
    fi
}

# Node is here for the harness: its sandbox runs JavaScript with Homebrew's copy.
# Python needs nothing extra, because it comes with the Command Line Tools.
install_packages() {
    step "Ollama and Node"
    local package
    for package in ollama node; do
        if [ -x "$BREW_BIN/$package" ]; then
            ok "$package is already installed"
        else
            run "$BREW_BIN/brew" install "$package"
        fi
    done
    if [ "$WANT_MLX" = 1 ]; then
        if [ -x "$BREW_BIN/mlx_lm.server" ]; then
            ok "mlx-lm is already installed"
        else
            run "$BREW_BIN/brew" install mlx-lm
        fi
    fi
}

get_code() {
    step "Prometheus code"
    if is_checkout "$REPO_DIR"; then
        if [ "$REPO_DIR" = "$(checkout_around_script || true)" ]; then
            ok "Using this copy: $REPO_DIR"
        elif ! run git -C "$REPO_DIR" pull --ff-only; then
            warn "Couldn't update $REPO_DIR, so this builds what's there."
        fi
    else
        run git clone "$REPO_URL" "$REPO_DIR"
    fi
}

build_app() {
    step "Building Prometheus"
    local target="install"
    if app_is_open; then
        # Replacing the app under a running test would ruin it, so that's left for you to do.
        target="app"
        warn "Prometheus is open, so the copy in /Applications stays as it is. Quit it, then run: make -C \"$REPO_DIR\" install"
    fi
    if ! run make -C "$REPO_DIR" "$target"; then
        die "The build failed. If the errors mention StateMacro or SwiftUIMacros, these Command Line Tools have no SDK that builds without Xcode. Install Xcode from the App Store and run: sudo xcode-select -s /Applications/Xcode.app"
    fi
}

start_ollama() {
    step "Starting Ollama"
    if ollama_is_up; then
        ok "Already running"
        return 0
    fi
    run "$BREW_BIN/brew" services start ollama
    if [ "$DRY_RUN" = 1 ]; then
        return 0
    fi
    local tries=0
    until ollama_is_up; do
        tries=$((tries + 1))
        if [ "$tries" -gt 30 ]; then
            warn "Ollama hasn't answered yet. If it doesn't, the app has a Start Ollama button."
            return 0
        fi
        sleep 1
    done
    ok "Running"
}

# A failed download doesn't stop the setup: the app works without it, and Models can fetch one later.
download_model() {
    step "First model"
    if [ "$WANT_MODEL" != 1 ]; then
        ok "Skipped. Open Models in the app to pick one."
        return 0
    fi
    if command -v ollama >/dev/null 2>&1 && ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -xF "$MODEL" >/dev/null; then
        ok "$MODEL is already downloaded"
        return 0
    fi
    if ! run "$BREW_BIN/ollama" pull "$MODEL"; then
        warn "The download didn't finish. Open Models in the app to try again."
    fi
}

open_app() {
    step "Done"
    ok "App:  $APP_PATH (Spotlight finds it)"
    ok "Code: $REPO_DIR"
    say ""
    say "Open Chat in Prometheus and send a message."
    say "To update later, press Update in Settings › Updates."
    CURRENT_STEP=""
    if ! app_is_open; then
        run open "$APP_PATH"
    fi
}

main() {
    parse_args "$@"
    trap finish EXIT
    check_mac
    choose_model
    choose_folder
    show_plan
    confirm_start
    get_sudo_if_needed
    keep_mac_awake

    install_command_line_tools
    install_homebrew
    install_packages
    get_code
    build_app
    start_ollama
    download_model
    open_app
}

# Everything is in functions, so a download cut off halfway can't run half a script.
main "$@"
