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

# ──────────────────────────── helpers ────────────────────────────

check_bin() {
	if command -v "$1" &>/dev/null; then
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
	if ! command -v "$bin" &>/dev/null; then
		echo -e "  ${FAIL} ${desc} (${bin} not found)"
		ALL_PASSED=false
		return 1
	fi
	local ver=""
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
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
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

OS=$(os_detect)

sudo_cmd() {
	if command -v sudo &>/dev/null; then
		sudo "$@"
	else
		"$@"
	fi
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	macos) brew install "$@" ;;
	*) return 1 ;;
	esac
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	macos) echo "brew install ${*}" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ──────────────────── main ────────────────────

echo -e "${BOLD}monkey-zsh dependency check${NC}"
echo ""

# ──── zsh version ────
echo -e "${BOLD}zsh${NC}"
check_version zsh 5.3 "zsh"
echo ""

# ──── platform ────
echo -e "${BOLD}Platform${NC}"
echo -e "  OS: ${CYAN}$(uname -s)${NC}"
case "$OS" in
debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
macos) echo -e "  Package manager: ${CYAN}homebrew${NC}" ;;
*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
esac
echo ""

# ──── required tools ────
echo -e "${BOLD}Required tools${NC}"
MISSING_REQUIRED=()

if check_bin git "git (required by zinit bootstrap)"; then
	:
else
	MISSING_REQUIRED+=("git")
fi
echo ""

# ──── optional tools ────
echo -e "${BOLD}Optional tools${NC}"
echo "  (Missing won't block monkey-zsh, but will disable some features)"
if check_bin fzf "fzf (fzf-tab / forgit / fzf integration)"; then :; fi
if check_bin zoxide "zoxide (smart cd)"; then :; fi
if check_bin eza "eza (ls aliases)"; then :; fi
if check_bin go "go (build smart-suggestion on first load)"; then :; fi
echo ""

# ──── terminal capabilities ────
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

# ──── config files ────
echo -e "${BOLD}Config files${NC}"
ZSHENV="${HOME}/.zshrc"
if [[ -L "$ZSHENV" ]]; then
	TARGET=$(readlink -f "$ZSHENV" 2>/dev/null || readlink "$ZSHENV")
	if [[ -f "$TARGET" ]]; then
		echo -e "  ${PASS} .zshrc → ${TARGET}"
	else
		echo -e "  ${FAIL} .zshrc symlink broken → ${TARGET}"
		ALL_PASSED=false
	fi
elif [[ -f "$ZSHENV" ]]; then
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

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ -f "$ZINIT_HOME/zinit.zsh" ]]; then
	echo -e "  ${PASS} zinit installed"
elif [[ -d "$ZINIT_HOME" ]]; then
	echo -e "  ${WARN} zinit dir exists but may be incomplete"
else
	echo -e "  ${WARN} zinit not installed (auto-cloned on first zsh start)"
fi

echo ""

# ──── install missing ────
if $INSTALL_MODE && [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing missing packages: ${MISSING_REQUIRED[*]}${NC}"
	echo ""

	declare -A APT_NAMES=(
		["zsh"]="zsh"
		["git"]="git"
	)
	declare -A PACMAN_NAMES=(
		["zsh"]="zsh"
		["git"]="git"
	)
	declare -A BREW_NAMES=(
		["zsh"]="zsh"
		["git"]="git"
	)

	pkg_name() {
		local bin="$1"
		case "$OS" in
		debian) echo "${APT_NAMES[$bin]:-$bin}" ;;
		arch) echo "${PACMAN_NAMES[$bin]:-$bin}" ;;
		macos) echo "${BREW_NAMES[$bin]:-$bin}" ;;
		*) echo "$bin" ;;
		esac
	}

	pkgs=()
	for b in "${MISSING_REQUIRED[@]}"; do
		pkgs+=("$(pkg_name "$b")")
	done

	if [[ ${#pkgs[@]} -gt 0 ]]; then
		if install_pkg "${pkgs[@]}"; then
			echo -e "${GREEN}Done.${NC}"
			for bin in "${MISSING_REQUIRED[@]}"; do
				if command -v "$bin" &>/dev/null; then
					echo -e "  ${PASS} ${bin} installed"
				else
					ALL_PASSED=false
					echo -e "  ${FAIL} ${bin} still missing"
				fi
			done
		else
			echo -e "${RED}Failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
		fi
	fi
	echo ""
fi

# ──── summary ────
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
