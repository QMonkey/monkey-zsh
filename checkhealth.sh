#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# List-item helpers: 2-space indent, brackets outside the color span,
# OK centered as [ OK ]. fail() does not abort — checkhealth must keep
# going and summarize (exit status comes from REQUIRED_FAILURES).
info() { echo -e "  [${CYAN}INFO${NC}] $*"; }
ok() { echo -e "  [${GREEN} OK ${NC}] $*"; }
warn() { echo -e "  [${YELLOW}WARN${NC}] $*"; }
fail() {
	echo -e "  [${RED}FAIL${NC}] $*"
}

REQUIRED_FAILURES=0
INSTALL_MODE=false
SKIP_CONFIG_CHECKS=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-zsh.

OPTIONS
  -i, --install    Install missing dependencies
  --skip-check-config
                   Skip config-file checks (install.sh passes this: the
                   config symlinks are linked after this script runs)
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --install) INSTALL_MODE=true ;;
		--skip-check-config) SKIP_CONFIG_CHECKS=true ;;
		-h | --help) usage ;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done
}

# ──────────────────────────── helpers ────────────────────────────

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side (node, python, git, ...) appear as /mnt/c/... shims. They are
# NOT Linux binaries: `sudo` cannot even see them (secure_path drops /mnt/*).
# Treat /mnt/* resolutions as "not installed" so the real Linux packages get
# installed instead.
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# Absolute path to a LINUX sudo, or non-zero.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

check_bin() {
	if have_native_cmd "$1"; then
		ok "${2:-$1}"
		return 0
	else
		fail "${2:-$1}"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		return 1
	fi
}

check_version() {
	local bin="$1" min="$2" desc="$3"
	if ! have_native_cmd "$bin"; then
		fail "${desc} (${bin} not found)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		return 1
	fi
	local ver="" flag
	for flag in --version -V -v; do
		ver=$("$bin" "$flag" 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
		[[ -n "$ver" ]] && break
	done
	if [[ -z "$ver" ]]; then
		fail "${desc} (could not detect version)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		return 1
	fi
	if printf '%s\n%s\n' "$min" "$ver" | sort -V -C; then
		ok "${desc} ${ver}"
		return 0
	else
		fail "${desc} ${ver} (need >= ${min})"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		return 1
	fi
}

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse | opensuse-leap | opensuse-tumbleweed | opensuse-microos | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	Darwin) echo "macos" ;;
	*) echo "unknown" ;;
	esac
}

sudo_cmd() {
	# Lazy re-auth: Homebrew resets the sudo timestamp on EVERY invocation
	# (brew.sh runs `sudo --reset-timestamp` at startup), so a ticket that
	# was valid a minute ago can be dead here. Re-authenticate proactively
	# with an explanatory prompt instead of letting the command fail or
	# spring a context-free password prompt. `-n true` never prompts; the
	# interactive `-v` only runs when the ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || {
		"$@"
		return
	}
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-zsh] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

# ────────────────── package index refresh ──────────────────
# Refresh the package index before installing: a stale or missing index is
# the usual cause of "Unable to locate package" on freshly provisioned
# machines (and universe-only packages like fzf/zoxide/eza are invisible
# until the first update). Retried once for transient network failures;
# a failed refresh is never fatal — the install step still runs (dnf
# refreshes expired metadata on demand anyway, brew auto-updates).
# Guarded to at most one refresh per run: checkhealth installs in two
# batches (required + optional) and the index does not go stale between
# them — call freely before every install.
PKG_DB_REFRESHED=0
refresh_pkg() {
	[ "$PKG_DB_REFRESHED" -eq 1 ] && return 0
	PKG_DB_REFRESHED=1
	local attempt
	for attempt in 1 2; do
		case "$OS" in
		debian) sudo_cmd apt-get update ;;
		arch) sudo_cmd pacman -Sy ;;
		opensuse) sudo_cmd zypper --non-interactive refresh ;;
		centos) sudo_cmd dnf makecache -q ;;
		macos | *) return 0 ;;
		esac && return 0
		[ "$attempt" -lt 2 ] && sleep 2
	done
	return 0
}

# Package name for a binary, per package manager: "go" is "golang-go" on
# apt and "golang" on dnf, and the brew fallback must map those back (brew
# validates every name up front and aborts the WHOLE batch when one is
# unknown — a lone apt-style "golang-go" would prevent even the
# brew-available fzf/zoxide/eza from installing).
# A case function instead of `declare -A`: macOS still ships bash 3.2,
# which has no associative arrays.
pkg_name() {
	local bin="$1" pm="$2"
	case "$pm:$bin" in
	debian:go) echo "golang-go" ;;
	centos:go) echo "golang" ;;
	brew:go) echo "go" ;;
	*) echo "$bin" ;;
	esac
}

# System package install with Homebrew fallback (eza/zoxide may be absent
# from older distro repos). Gated on --install; recycles bash's command
# hash so a freshly installed binary resolves.
install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	refresh_pkg
	local rc=0
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	macos) brew install "$@" ;;
	*) rc=1 ;;
	esac || rc=$?
	if [ "$rc" -ne 0 ] && have_native_cmd brew && [ "$OS" != "macos" ]; then
		local b bpkg=()
		for b in "$@"; do
			bpkg+=("$(pkg_name "$b" brew)")
		done
		brew install "${bpkg[@]}" || rc=1
	fi
	# Freshly installed binaries may be shadowed by bash's per-process
	# command hash cache (a /mnt shim executed earlier in this same run);
	# re-scan PATH. Run AFTER capturing rc — hash -r must not mask the
	# install status.
	hash -r
	return "$rc"
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	opensuse) echo "sudo zypper install ${*}" ;;
	centos) echo "sudo dnf install ${*}" ;;
	macos) echo "brew install ${*}" ;;
	linux-unknown) echo "install ${*} manually or 'brew install ${*}'" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ──────────────────── phases ────────────────────

print_header() {
	echo -e "${BOLD}monkey-zsh dependency check${NC}"
	echo ""
}

print_zsh_version() {
	echo -e "${BOLD}zsh${NC}"
	if check_version zsh 5.3 "zsh"; then
		:
	else
		MISSING_REQUIRED+=("zsh")
	fi
	echo ""
}

print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	case "$OS" in
	debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
	arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
	opensuse) echo -e "  Package manager: ${CYAN}zypper${NC}" ;;
	centos) echo -e "  Package manager: ${CYAN}dnf${NC}" ;;
	macos) echo -e "  Package manager: ${CYAN}homebrew${NC}" ;;
	*) warn "Unsupported OS — install dependencies manually" ;;
	esac
	echo ""
}

# Sets MISSING_REQUIRED.
check_required_tools() {
	echo -e "${BOLD}Required tools${NC}"
	check_bin git "git (required by zinit bootstrap)" || MISSING_REQUIRED+=("git")
	echo ""
}

# Sets MISSING_OPTIONAL. Optional tools must NOT increment REQUIRED_FAILURES — a
# missing fzf degrades features but monkey-zsh still works.
check_optional_tools() {
	echo -e "${BOLD}Optional tools${NC}"
	echo "  (Missing won't block monkey-zsh, but will disable some features)"
	local tool desc
	for tool in fzf zoxide eza go; do
		case "$tool" in
		fzf) desc="fzf (fzf-tab / forgit / fzf integration)" ;;
		zoxide) desc="zoxide (smart cd)" ;;
		eza) desc="eza (ls aliases)" ;;
		go) desc="go (build smart-suggestion on first load)" ;;
		esac
		if have_native_cmd "$tool"; then
			ok "${desc}"
		else
			fail "${desc}"
			MISSING_OPTIONAL+=("$tool")
		fi
	done
	echo ""
}

check_terminal_caps() {
	echo -e "${BOLD}Terminal capabilities${NC}"
	if [[ -n "${COLORTERM:-}" ]] || [[ "$TERM" =~ (256color|tmux|screen|alacritty|kitty|wezterm|xterm-kitty) ]]; then
		ok "TERM=${TERM} (true color capable)"
	else
		warn "TERM=${TERM} — true color may not work"
	fi
	if [[ "$LANG" == *".UTF-8" || "$LANG" == *".utf8" ]]; then
		ok "LANG=${LANG}"
	else
		warn "LANG=${LANG} (UTF-8 recommended)"
	fi
	echo ""
}

check_config_files() {
	# --skip-check-config (passed by install.sh): the config symlinks are
	# linked AFTER this script runs, so judging them here would fail every
	# chained run and burn all three retries. Standalone runs (the manual
	# diagnosis entry point) still get the full check.
	if $SKIP_CONFIG_CHECKS; then
		warn "config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local zshrc="${HOME}/.zshrc"
	if [[ -L "$zshrc" ]]; then
		local target
		target=$(readlink -f "$zshrc" 2>/dev/null || readlink "$zshrc")
		if [[ -f "$target" ]]; then
			ok ".zshrc → ${target}"
		else
			fail ".zshrc symlink broken → ${target}"
			REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		fi
	elif [[ -f "$zshrc" ]]; then
		warn ".zshrc exists but is not a symlink"
	else
		fail ".zshrc not found (run: ln -sf $(pwd)/.zshrc ~/.zshrc)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi

	if [[ -f "${HOME}/.zprofile" ]]; then
		ok ".zprofile exists (login-shell env)"
	else
		warn ".zprofile not found (optional; put login env vars there)"
	fi

	local zinit_home="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
	if [[ -f "$zinit_home/zinit.zsh" ]]; then
		ok "zinit installed"
	elif [[ -d "$zinit_home" ]]; then
		warn "zinit dir exists but may be incomplete"
	else
		warn "zinit not installed (auto-cloned on first zsh start)"
	fi

	echo ""
}

check_python3() {
	# TIOCSTI injection (install.sh's end-of-run terminal activation) needs
	# python3 — system perl is the runtime fallback, never installed here,
	# so it is not detected.
	echo -e "${BOLD}python3${NC} (TIOCSTI injection)"
	check_bin python3 "python3 (required by TIOCSTI injection)" || MISSING_REQUIRED+=("python3")
	echo ""
}

# The required checks, in ONE place: main runs them up front, and
# install_missing_required re-runs them after installing — the install
# changed the world, so the verdict (REQUIRED_FAILURES / MISSING_REQUIRED) is
# always recomputed from here and never carried over stale.
run_required_checks() {
	REQUIRED_FAILURES=0
	MISSING_REQUIRED=()
	print_zsh_version
	check_required_tools
	check_config_files
	check_python3
}

install_missing_required() {
	if ! $INSTALL_MODE || [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing missing packages: ${MISSING_REQUIRED[*]}${NC}"
	echo ""
	if install_pkg "${MISSING_REQUIRED[@]}"; then
		run_required_checks
		if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
			echo -e "${RED}Run: $(get_install_hint "${MISSING_REQUIRED[*]}")${NC}"
		fi
	else
		echo -e "${RED}Failed. Run: $(get_install_hint "${MISSING_REQUIRED[*]}")${NC}"
	fi
	echo ""
}

install_missing_optional() {
	if ! $INSTALL_MODE || [[ ${#MISSING_OPTIONAL[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing missing optional tools: ${MISSING_OPTIONAL[*]}${NC}"
	echo ""
	# Package names that differ from the binary name live in the
	# pm-parameterized pkg_name() above — one mapping table for the
	# system manager and the brew fallback alike.
	local opkgs=() bin b
	for b in "${MISSING_OPTIONAL[@]}"; do
		opkgs+=("$(pkg_name "$b" "$OS")")
	done
	if [[ ${#opkgs[@]} -gt 0 ]]; then
		if install_pkg "${opkgs[@]}"; then
			for bin in "${MISSING_OPTIONAL[@]}"; do
				if have_native_cmd "$bin"; then
					ok "${bin} installed"
				else
					fail "${bin} still missing"
				fi
			done
		else
			echo -e "${RED}Failed. Run: $(get_install_hint "${opkgs[*]}")${NC}"
		fi
	fi
	echo ""
}

print_summary() {
	if [ "$REQUIRED_FAILURES" -eq 0 ]; then
		echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
		exit 0
	else
		echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
		if ! $INSTALL_MODE; then
			echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
		fi
		exit 1
	fi
}

# ──────────────────── main ────────────────────

main() {
	parse_args "$@"
	OS=$(os_detect)
	readonly OS
	MISSING_REQUIRED=()
	MISSING_OPTIONAL=()
	print_header
	print_platform
	run_required_checks
	check_optional_tools
	check_terminal_caps
	install_missing_required
	install_missing_optional
	print_summary
}

main "$@"
