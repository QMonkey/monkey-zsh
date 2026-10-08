#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-zsh dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-zsh

# ──────────────────────── version gate ────────────────────────
# id|min|desc|install — parsed once, printed as its own section right after
# Platform. "pkg" installs zsh itself when it is missing or too old.
MAIN_VERSION="zsh|ver:5.3|zsh|pkg"
MAIN_VERSION_TITLE="zsh"

# ──────────────────────── required ────────────────────────
# Ordered sections: a title, the specs under it, a blank line closes it.
#   @header|Title   bold section title
#   @note|text      indented note
#   @config         the "Config files" section (CONFIG_PHASE=required below)
REQUIRED_CHECKS=(
	"@header|Required tools"
	"git|bin|git (required by zinit bootstrap)"
	"@config"
	"@header|python3${NC} (TIOCSTI injection)"
	"python3|bin|python3 (required by TIOCSTI injection)"
)

# ──────────────────────── optional ────────────────────────
# fzf ships far newer via Homebrew than most distro repos — prefer brew
# when it exists (install_pkg splits the batch on these names).
BREW_FIRST=(fzf)
# Missing entries are reported red but never fail the check; they are only
# installed under --install (INSTALL_OPTIONAL=1).
OPTIONAL_SECTION_TITLE="Optional tools"
OPTIONAL_SECTION_NOTE="(Missing won't block monkey-zsh, but will disable some features)"
OPTIONAL_CHECKS=(
	"fzf|bin|fzf (fzf-tab / forgit / fzf integration)"
	"zoxide|bin|zoxide (smart cd)"
	"eza|bin|eza (ls aliases)"
	"go|bin|go (build smart-suggestion on first load)"
)
INSTALL_OPTIONAL=1
INSTALL_REQUIRED_PHASE=late
INSTALL_OPTIONAL_PHASE=late

# ──────────────────────── config ────────────────────────
# Checked inside the required run (between "Required tools" and python3),
# so it is re-evaluated after --install has run.
CONFIG_PHASE=required
# src|dst|desc|mode|name|hint — mode "link" (default) warns about foreign
# targets, "strict" additionally requires the link to resolve into this repo.
# hint reproduces upstream's verbatim missing-fail text (ln -sf, not -sfn).
CONFIG_LINKS=(
	"$(pwd)/.zshrc|$HOME/.zshrc|.zshrc||.zshrc|.zshrc not found (run: ln -sf $(pwd)/.zshrc ~/.zshrc)"
)
# type|params|ok|incomplete|missing
CONFIG_HINTS=(
	"path|$HOME/.zprofile|.zprofile exists (login-shell env)||.zprofile not found (optional; put login env vars there)"
	"path|${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git/zinit.zsh|zinit installed|zinit dir exists but may be incomplete|zinit not installed (auto-cloned on first zsh start)"
)

# ──────────────────────── terminal ────────────────────────
CHECK_TERMINAL_CAPS=1
CHECK_LANG=1

checkhealth_main "$@"
