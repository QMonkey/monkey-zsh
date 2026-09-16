#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-zsh.

OPTIONS
  -i, --install    Install missing dependencies
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --install) INSTALL_MODE=true ;;
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
		echo -e "  ${PASS} ${2:-$1}"
		return 0
	else
		echo -e "  ${FAIL} ${2:-$1}"
		ALL_PASSED=false
		return 1
	fi
}

check_version() {
	local bin="$1" min="$2" desc="$3"
	if ! have_native_cmd "$bin"; then
		echo -e "  ${FAIL} ${desc} (${bin} not found)"
		ALL_PASSED=false
		return 1
	fi
	local ver="" flag
	for flag in --version -V -v; do
		ver=$("$bin" "$flag" 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
		[[ -n "$ver" ]] && break
	done
	if [[ -z "$ver" ]]; then
		echo -e "  ${FAIL} ${desc} (could not detect version)"
		ALL_PASSED=false
		return 1
	fi
	if printf '%s\n%s\n' "$min" "$ver" | sort -V -C; then
		echo -e "  ${PASS} ${desc} ${ver}"
		return 0
	else
		echo -e "  ${FAIL} ${desc} ${ver} (need >= ${min})"
		ALL_PASSED=false
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
	sudo_bin=$(native_sudo) || { "$@"; return; }
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-zsh] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

# System package manager install. Returns non-zero when the OS is unknown
# or the manager fails, so callers can fall back to Homebrew (eza/zoxide
# may be absent from older distro repos).
install_with_system_mgr() {
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	macos) brew install "$@" ;;
	*) return 1 ;;
	esac
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	if ! install_with_system_mgr "$@"; then
		have_native_cmd brew && brew install "$@"
	fi
	# Freshly installed binaries may be shadowed by bash's per-process
	# command hash cache (a /mnt shim executed earlier in this same run);
	# re-scan PATH.
	hash -r
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
	*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
	esac
	echo ""
}

# Sets MISSING_REQUIRED.
check_required_tools() {
	echo -e "${BOLD}Required tools${NC}"
	check_bin git "git (required by zinit bootstrap)" || MISSING_REQUIRED+=("git")
	echo ""
}

# Sets MISSING_OPTIONAL. Optional tools must NOT poison ALL_PASSED — a
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
			echo -e "  ${PASS} ${desc}"
		else
			echo -e "  ${FAIL} ${desc}"
			MISSING_OPTIONAL+=("$tool")
		fi
	done
	echo ""
}

check_terminal_caps() {
	echo -e "${BOLD}Terminal capabilities${NC}"
	if [[ -n "${COLORTERM:-}" ]] || [[ "$TERM" =~ (256color|tmux|screen|alacritty|kitty|wezterm|xterm-kitty) ]]; then
		echo -e "  ${PASS} TERM=${TERM} (true color capable)"
	else
		echo -e "  ${WARN} TERM=${TERM} — true color may not work"
	fi
	if [[ "$LANG" == *".UTF-8" || "$LANG" == *".utf8" ]]; then
		echo -e "  ${PASS} LANG=${LANG}"
	else
		echo -e "  ${WARN} LANG=${LANG} (UTF-8 recommended)"
	fi
	echo ""
}

check_config_files() {
	echo -e "${BOLD}Config files${NC}"
	local zshrc="${HOME}/.zshrc"
	if [[ -L "$zshrc" ]]; then
		local target
		target=$(readlink -f "$zshrc" 2>/dev/null || readlink "$zshrc")
		if [[ -f "$target" ]]; then
			echo -e "  ${PASS} .zshrc → ${target}"
		else
			echo -e "  ${FAIL} .zshrc symlink broken → ${target}"
			ALL_PASSED=false
		fi
	elif [[ -f "$zshrc" ]]; then
		echo -e "  ${WARN} .zshrc exists but is not a symlink"
	else
		echo -e "  ${FAIL} .zshrc not found (run: ln -sf $(pwd)/.zshrc ~/.zshrc)"
		ALL_PASSED=false
	fi

	if [[ -f "${HOME}/.zprofile" ]]; then
		echo -e "  ${PASS} .zprofile exists (login-shell env)"
	else
		echo -e "  ${WARN} .zprofile not found (optional; put login env vars there)"
	fi

	local zinit_home="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
	if [[ -f "$zinit_home/zinit.zsh" ]]; then
		echo -e "  ${PASS} zinit installed"
	elif [[ -d "$zinit_home" ]]; then
		echo -e "  ${WARN} zinit dir exists but may be incomplete"
	else
		echo -e "  ${WARN} zinit not installed (auto-cloned on first zsh start)"
	fi

	echo ""
}

install_missing_required() {
	if ! $INSTALL_MODE || [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing missing packages: ${MISSING_REQUIRED[*]}${NC}"
	echo ""
	if install_pkg "${MISSING_REQUIRED[@]}"; then
		echo -e "${GREEN}Done.${NC}"
		local bin
		for bin in "${MISSING_REQUIRED[@]}"; do
			if have_native_cmd "$bin"; then
				echo -e "  ${PASS} ${bin} installed"
			else
				ALL_PASSED=false
				echo -e "  ${FAIL} ${bin} still missing"
			fi
		done
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
	# Package names that differ from the binary name, per package manager.
	# A case function instead of `declare -A`: macOS still ships bash 3.2,
	# which has no associative arrays.
	pkg_name() {
		local bin="$1"
		case "$OS:$bin" in
		debian:go) echo "golang-go" ;;
		centos:go) echo "golang" ;;
		*) echo "$bin" ;;
		esac
	}
	local opkgs=() bin b
	for b in "${MISSING_OPTIONAL[@]}"; do
		opkgs+=("$(pkg_name "$b")")
	done
	if [[ ${#opkgs[@]} -gt 0 ]]; then
		if install_pkg "${opkgs[@]}"; then
			for bin in "${MISSING_OPTIONAL[@]}"; do
				if have_native_cmd "$bin"; then
					echo -e "  ${PASS} ${bin} installed"
				else
					echo -e "  ${FAIL} ${bin} still missing"
				fi
			done
		else
			echo -e "${RED}Failed. Run: $(get_install_hint "${opkgs[*]}")${NC}"
		fi
	fi
	echo ""
}

print_summary() {
	if $ALL_PASSED; then
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
	MISSING_REQUIRED=()
	MISSING_OPTIONAL=()
	print_header
	print_zsh_version
	print_platform
	check_required_tools
	check_optional_tools
	check_terminal_caps
	check_config_files
	install_missing_required
	install_missing_optional
	print_summary
}

main "$@"
