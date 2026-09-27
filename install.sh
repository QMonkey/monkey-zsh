#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-zsh one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-zsh/master/install.sh | bash
#
# The shared installer (sudo, packages, clone, checkhealth, symlinks,
# completion) lives in scripts/ — a `git subtree` of
# github.com/QMonkey/monkey-scripts. On the curl|bash path there is no
# checkout at all, so install.sh clones THIS repo and runs the copy of
# install.sh inside it — that copy carries its own scripts/, so the
# installer and the framework it loads are always the same revision.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs both
# values, and clones into the very directory clone_monkey_project would
# have used — one clone per run, not two.
PROJECT=monkey-zsh
PROJECT_REPO=https://github.com/QMonkey/monkey-zsh.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-zsh}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			git clone "$PROJECT_REPO" "$INSTALL_DIR" || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── layout & data ────────────────────────
ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-zsh}"

# src|dst — everything else (dirs to create, files to touch) is ENSURE_*.
SYMLINKS=(
	"$INSTALL_DIR/.zshrc|$HOME/.zshrc"
)
ENSURE_FILES=(
	"$HOME/.zprofile" # login-shell env vars have a place to live
)

# PATH exports land in the profile but only apply to shells started later —
# say so, and offer the TIOCSTI injection into the running terminal.
PERSIST_PATH=1
SUMMARY_LINES=(
	"  Config:   ${CYAN}$INSTALL_DIR/.zshrc${NC} → ${CYAN}~/.zshrc${NC}"
	"  Plugins:  ${CYAN}~/.local/share/zinit/${NC} (cloned on first zsh start)"
	""
	"  Start it: ${CYAN}exec zsh${NC}"
	"  Update monkey-zsh: ${CYAN}cd $INSTALL_DIR && git pull${NC}"
)

# ──────────────────────── project steps ────────────────────────

# Step 1: zsh itself — every supported distro ships >= 5.3, so there is no
# source-build fallback; checkhealth.sh verifies the version afterwards.
install_zsh() {
	if have_native_cmd zsh; then
		ok "zsh $(zsh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) already installed."
		return 0
	fi
	info "Installing zsh via the system package manager..."
	install_pkg zsh || :
	have_native_cmd zsh || fail "zsh installation failed — install it manually: $(get_install_hint zsh)"
	ok "zsh installed."
}

# Non-interactive by design (the installer runs unattended) and idempotent:
# skipped when the login shell is already zsh, or when zsh is not a valid
# login shell (missing from /etc/shells).
switch_login_shell() {
	local zsh_bin
	zsh_bin=$(command -v zsh) || return 0
	grep -qx "$zsh_bin" /etc/shells 2>/dev/null || return 0
	if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = "$zsh_bin" ]; then
		ok "login shell is already zsh."
		return 0
	fi
	sudo_cmd chsh -s "$zsh_bin" "$(id -un)" && ok "login shell switched to zsh."
}

# A hook prints its own trailing blank line when it produced output.
install_step_prepare() {
	ensure_git
	echo ""
}
install_step_tool() {
	install_zsh
	echo ""
}
install_step_post_tool() {
	install_linuxbrew
	echo ""
}
install_step_after() {
	switch_login_shell
	echo ""
}

install_main "$@"
