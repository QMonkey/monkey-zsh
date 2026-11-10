#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-zsh one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-zsh/master/install.sh | bash 2>&1 | tee monkey-zsh-install.log
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
# values, and clones into the very directory clone_project would
# have used — one clone per run, not two.
PROJECT=monkey-zsh
PROJECT_REPO=https://github.com/QMonkey/monkey-zsh.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-zsh}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on), a .git-less directory (zip/tarball),
# or `curl | bash`, which has no checkout at all. The latter two bootstrap
# through INSTALL_DIR and run the install.sh from that checkout, so
# installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		# Outdated checkout: update it in place and keep running from it.
		git -C "$_monkey_dir" pull --ff-only || true
		if [ ! -f "$_monkey_dir/scripts/install.sh" ]; then
			printf '%s\n' "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			printf '%s\n' "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
		_monkey_scripts="$_monkey_dir/scripts"
	else
		# curl|bash or a .git-less directory: the only path to a
		# same-revision scripts/ is the INSTALL_DIR checkout.
		# clone_project cannot do this job — it lives in the very
		# scripts/ being fetched. INSTALL_DIR is where the framework's clone
		# step would have put the checkout too, so that step only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			printf '%s\n' "$INSTALL_DIR is not empty and is not a git clone." >&2
			printf '%s\n' "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# Fresh clone — the ONLY sub-branch where git is hard-required:
			# the pull sub-branch above degrades gracefully without it, and
			# a zip/tarball must not fail here just for a missing git.
			if ! command -v git >/dev/null 2>&1; then
				printf '%s\n' "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
				exit 1
			fi
			# No retry() available yet — the framework loads only after this
			# clone succeeds — so inline the standard 3 attempts. A failed
			# clone leaves a partial directory behind; remove it so the next
			# attempt cannot trip over "already exists". This branch only
			# runs on a fresh install (INSTALL_DIR did not exist or was
			# empty), so the rm can never delete pre-existing data.
			_monkey_rc=1
			for _monkey_attempt in 1 2 3; do
				if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
					_monkey_rc=0
					break
				fi
				rm -rf "$INSTALL_DIR"
				if [ "$_monkey_attempt" -lt 3 ]; then
					sleep 2
				fi
			done
			[ "$_monkey_rc" -eq 0 ] || exit 1
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

# zsh's environment file, persisted at install time (see persist_zsh_env
# below). Declared here because SUMMARY_LINES renders it.
# ~/.config/env/ is a directory the family shares: one file per project, named
# after that project — not after any plugin it happens to configure.
ZSH_ENV_FILE="${ZSH_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/env/zsh.env}"
# The keys the installer seeds, in the order zsh.env.template lists them —
# smart-suggestion's provider set only: the provider switch plus each
# provider's own variables. Behaviour knobs (trigger key, send-context, debug,
# proxy mode, auto-update, update interval, history lines, binary path) are NOT
# seeded: they configure the plugin, not zsh's AI access, and a knob the
# installer writes empty would read as set through the plugin's ${+VAR} guard.
# Every seeded key is written on every run; empty means unset (template
# header).
ZSH_ENV_KEYS="SMART_SUGGESTION_AI_PROVIDER OPENAI_API_KEY OPENAI_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_BASE_URL GEMINI_API_KEY GEMINI_BASE_URL GEMINI_MODEL DEEPSEEK_API_KEY DEEPSEEK_BASE_URL DEEPSEEK_MODEL AZURE_OPENAI_API_KEY AZURE_OPENAI_RESOURCE_NAME AZURE_OPENAI_DEPLOYMENT_NAME AZURE_OPENAI_BASE_URL AZURE_OPENAI_API_VERSION"

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
	"  Env:      ${CYAN}${ZSH_ENV_FILE#"$HOME"/}${NC} (zsh environment; every seeded provider key always written, empty = unset)"
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
# login shell (missing from /etc/shells). NEVER silent: a skipped switch is
# the root cause of env blocks landing in .bash_profile instead of
# ~/.zprofile (shell_env_files picks the target profile from the login
# shell), so every skip/failure path prints why.
switch_login_shell() {
	local zsh_bin alt
	zsh_bin=$(command -v zsh) || return 0
	# chsh validates against /etc/shells, and the registered path varies:
	# Fedora's zsh package registers BOTH /usr/bin/zsh and /bin/zsh, older
	# releases only /bin/zsh — the same binary through the unified-/usr
	# symlink. Prefer a path /etc/shells actually lists.
	if ! grep -qx "$zsh_bin" /etc/shells 2>/dev/null; then
		for alt in /bin/zsh /usr/bin/zsh; do
			[ "$alt" = "$zsh_bin" ] && continue
			if grep -qx "$alt" /etc/shells 2>/dev/null &&
				[ "$(readlink -f "$alt" 2>/dev/null)" = "$(readlink -f "$zsh_bin" 2>/dev/null)" ]; then
				zsh_bin=$alt
				break
			fi
		done
	fi
	if ! grep -qx "$zsh_bin" /etc/shells 2>/dev/null; then
		warn "zsh ($zsh_bin) is not in /etc/shells — login shell not switched."
		warn "  env blocks will land in the bash profiles; fix: echo $zsh_bin | sudo tee -a /etc/shells && chsh -s $zsh_bin"
		return 0
	fi
	if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = "$zsh_bin" ]; then
		ok "login shell is already zsh."
		return 0
	fi
	if sudo_cmd chsh -s "$zsh_bin" "$(id -un)"; then
		ok "login shell switched to zsh."
	else
		warn "chsh failed — env blocks will land in the bash profiles."
		warn "  switch manually: chsh -s $zsh_bin"
	fi
}

# ──────────────────────── zsh environment ────────────────────────
# ZSH_ENV_FILE is zsh's own environment file: the profiles source it with
# `set -a`, so whatever it holds reaches zsh and every process zsh starts.
# The file and the profile line are written on every run — an install that
# exported nothing still leaves every seeded key as an empty line, which is
# exactly the shape to fill in by hand afterwards.
#
# Empty means unset for every seeded key, and that comes from upstream: the
# plugin tests each provider variable against "" and falls back to its own
# endpoint default. Nothing here normalizes a name — which is also why the
# plugin's behaviour knobs are not seeded: those are guarded with zsh's `${+VAR}`
# presence test, so an installer-written empty line would read as set and wipe
# the plugin's own default.
#
# Keys smart-suggestion does not read stay out of the list: the file mirrors
# the plugin's variable surface, nothing more. Machine-specific information
# belongs to values, not to key names — a key that IS read is seeded empty and
# filled in by hand, and one that is not read is not this file's business.
#
# Nothing is shared: this owns no other project's credential store, reads no
# other project's variables, and re-running any other installer cannot change
# zsh's completion.
#
# Shape follows the family's env-file convention; the mechanism comes from
# scripts/ (render_fill + append_env_block), the data stays zsh's own.
persist_zsh_env() {
	local provider="${SMART_SUGGESTION_AI_PROVIDER:-}" k need="" missing=""
	case "$provider" in
	openai) need="OPENAI_API_KEY" ;;
	anthropic) need="ANTHROPIC_API_KEY" ;;
	gemini) need="GEMINI_API_KEY" ;;
	deepseek) need="DEEPSEEK_API_KEY" ;;
	azure_openai)
		need="AZURE_OPENAI_API_KEY AZURE_OPENAI_DEPLOYMENT_NAME"
		# RESOURCE_NAME only builds the hostname when no base URL was given.
		[ -n "${AZURE_OPENAI_BASE_URL:-}" ] || need="$need AZURE_OPENAI_RESOURCE_NAME"
		;;
	"")
		info "SMART_SUGGESTION_AI_PROVIDER is unset — smart-suggestion detects its provider from whichever API key is set. Writing every key empty for you to fill in."
		;;
	*)
		warn "SMART_SUGGESTION_AI_PROVIDER=$provider is none of openai|azure_openai|anthropic|gemini|deepseek — smart-suggestion fails every request with \"unsupported provider\" until it is. Writing every key anyway."
		;;
	esac
	# A provider whose required variables are missing cannot answer a single
	# request, so an incomplete set is reported even though the file is
	# written — it is the hand-fill entry point for exactly this case. Keys
	# with no requirement of their own (the two branches above) leave need
	# empty, so this reports nothing for them.
	for k in $need; do
		[ -n "${!k:-}" ] || missing="$missing ${k}"
	done
	[ -z "$missing" ] ||
		warn "SMART_SUGGESTION_AI_PROVIDER=$provider but incomplete (missing$missing) — smart-suggestion cannot reach that provider. Export all of them and re-run, or fill the lines in ${ZSH_ENV_FILE#"$HOME"/} by hand."
	# render_fill runs on python3, which checkhealth installs as a required
	# tool earlier in the chain; without it the file cannot be merged, and an
	# unsourced profile block would be worse than no block at all.
	have_native_cmd python3 || {
		warn "python3 not found — cannot write ${ZSH_ENV_FILE##*/} (render_fill needs it). zsh env not persisted; re-run after the dependency pass."
		return 0
	}
	# Every key, not only the exported ones: render_fill keeps an existing
	# non-empty value over this run's environment either way, and the keys with
	# no value land as empty placeholders that mean unset (see the header
	# above for how each family of keys gets that meaning).
	render_fill "$INSTALL_DIR/zsh.env.template" "$ZSH_ENV_FILE" $ZSH_ENV_KEYS || return 0
	append_env_block "zsh env (remove these lines to disable)" "$(env_source_line "$ZSH_ENV_FILE")"
	info "zsh env: smart-suggestion keys persisted to ${ZSH_ENV_FILE#"$HOME"/} (0600), empty = unset."
	info "zsh env: a value already in that file wins over this run's export — edit the file to change one."
	printf '\n'
}

# ──────────────────────── hooks ────────────────────────
# A hook prints its own trailing blank line when it produced output.
install_step_prepare() {
	ensure_git
	printf '\n'
}
install_step_tool() {
	install_zsh
	# Switch the login shell BEFORE the framework writes any env blocks:
	# shell_env_files() (persist_path, Homebrew shellenv, tmux auto-start)
	# reads the login shell from the user database to pick the target
	# profile — with chsh still pending the blocks would land in
	# .bash_profile/.profile instead of ~/.zprofile, and only a re-run
	# (or a later component) would write them where zsh reads them.
	switch_login_shell
	printf '\n'
}
install_step_post_tool() {
	brew_ensure
	printf '\n'
}

install_step_after() {
	# Last: the profiles already carry the family's PATH and credential blocks,
	# so the zsh env block lands among them, and the dependency pass that
	# brings python3 (render_fill's engine) has already run.
	persist_zsh_env
	printf '\n'
}

install_main "$@"
