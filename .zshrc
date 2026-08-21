# ============================================================
#  monkey-zsh -- single-file Zsh configuration
#  Plugin manager: Zinit (declarative, vim-plug style)
#  Prompt:        plain-text two-line (no icon font required)
# ============================================================

# ---------- Environment (via ~/.zprofile) ----------
# zsh only sources ~/.zprofile for login shells; load it here so interactive
# non-login shells get the same env.
#
#   - `-o login` true        -> login shell already sourced ~/.zprofile, skip.
#   - `_ZPROFILE_LOADED` set -> already sourced in THIS process, skip.
#       (NOT exported: an exported marker would leak into child shells and
#        wrongly make them skip sourcing, losing env vars.)
#   - `typeset -U PATH path` -> makes PATH idempotent, so even if ~/.zprofile
#       is sourced more than once (e.g. nested shells), entries stay unique.
typeset -U PATH path
if [[ ! -o login && -z ${_ZPROFILE_LOADED:-} && -f ~/.zprofile ]]; then
  source ~/.zprofile
fi
_ZPROFILE_LOADED=1

# ---------- Zinit bootstrapping ----------
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
  command mkdir -p "$(dirname "$ZINIT_HOME")"
  command git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# zinit registers aliases zi=zinit etc.; free up "zi" for zoxide's interactive picker
unalias zi 2>/dev/null

# ---------- Basic options ----------
setopt AUTO_CD EXTENDED_GLOB NO_BEEP NO_FLOW_CONTROL INTERACTIVE_COMMENTS
setopt COMPLETE_IN_WORD PROMPT_SUBST
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_VERIFY

HISTFILE="${XDG_STATE_HOME:-${HOME}/.local/state}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
command mkdir -p "${HISTFILE:h}"

[[ -f /etc/DIR_COLORS ]] && eval "$(dircolors -b /etc/DIR_COLORS)"

# ---------- Plugins ----------
zinit light zsh-users/zsh-completions

autoload -Uz compinit
command mkdir -p "${XDG_CACHE_HOME:-${HOME}/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-${HOME}/.cache}/zsh/zcompdump-$ZSH_VERSION"

# fzf-tab needs fzf installed (no specific version required)
if (( $+commands[fzf] )); then
  zinit light Aloxaf/fzf-tab

  # fzf system integration (Ctrl-R history / Ctrl-T files / Alt-C directories)
  eval "$(fzf --zsh)"

  # forgit: fzf-powered git interaction (ga/gd/glo/...); requires fzf >= 0.60.0 (see README)
  zinit light wfxr/forgit
fi

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search

# AI completion (smart-suggestion): enabled when any provider API key is set (see README)
if [[ -n "${SMART_SUGGESTION_AI_PROVIDER:-}" || -n "${OPENAI_API_KEY:-}" \
   || -n "${ANTHROPIC_API_KEY:-}" || -n "${GEMINI_API_KEY:-}" || -n "${DEEPSEEK_API_KEY:-}" ]]; then
  zinit as"program" atclone'./build.sh' atpull'%atclone' \
    pick"smart-suggestion" src"smart-suggestion.plugin.zsh" for \
      yetone/smart-suggestion
fi

# Syntax highlighting, load last
zinit light zdharma-continuum/fast-syntax-highlighting

# ---------- Completion behavior ----------
zstyle ':completion:*' use-cache true
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-${HOME}/.cache}/zsh/completion-cache"
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# ---------- Two-line plain-text prompt ----------
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr ' +'
zstyle ':vcs_info:git:*' unstagedstr ' *'
zstyle ':vcs_info:git:*' formats ' %F{yellow}(%b%u%c)%f'
zstyle ':vcs_info:git:*' actionformats ' %F{red}(%b|%a)%f'

# Register vcs_info via the hook mechanism, NOT `precmd() { vcs_info }`.
# zsh dispatches to the `precmd_functions` array when it is non-empty, and
# plugins (autosuggestions etc.) already populate it via add-zsh-hook; a legacy
# `precmd()` function would be silently ignored. Hooks coexist with plugins.
autoload -Uz add-zsh-hook
add-zsh-hook precmd vcs_info

# Line 1: user@host  path  git status
# Line 2: prompt char only (>), green=last command OK, red=failed
PROMPT=$'%F{green}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_}\n%(?.%F{green}.%F{red})>%f '
PROMPT2=$'%F{blue}.%f '
PROMPT_EOL_MARK=''

# ---------- Key bindings ----------
# Use terminfo so arrow keys work across terminals (xterm/linux/tmux/...)
zmodload zsh/terminfo
bindkey "${terminfo[kcuu1]}" history-substring-search-up
bindkey "${terminfo[kcud1]}" history-substring-search-down

# ---------- zoxide ----------
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# ---------- Everyday aliases ----------
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --group-directories-first'
  alias la='eza -a --group-directories-first'
  alias l='eza -1 --group-directories-first'
  alias lt='eza --tree --group-directories-first'
  alias lg='eza -lh --git --group-directories-first'  # show git status column
else
  alias ls='ls --color=auto'
  alias ll='ls -lah --color=auto'
  alias la='ls -A --color=auto'
  alias l='ls -1'
fi

alias grep='grep --color=auto'
alias rg='rg --hidden --glob "!.git"'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ---------- git aliases (curated from oh-my-zsh git plugin) ----------
# forgit takes over ga/gd/gbl/gco/gbd/gsw/grb (fzf-interactive versions);
# the rest stay as plain git aliases. Loaded below, before this block.
alias g='git'
alias gaa='git add --all'
alias gau='git add --update'
alias gapa='git add --patch'
alias gb='git branch'
alias gba='git branch --all'
alias gbD='git branch --delete --force'
alias gc='git commit --verbose'
alias gca='git commit --verbose --all'
alias gcam='git commit --all --message'
alias gcmsg='git commit --message'
alias gdca='git diff --cached'
alias gf='git fetch'
alias gfa='git fetch --all --prune --jobs=10'
alias gl='git pull'
alias glg='git log --graph --oneline --decorate'
alias gm='git merge'
alias gp='git push'
alias gst='git status'
alias gsta='git stash push'
alias gstp='git stash pop'
alias gswc='git switch --create'

# ---------- colored man pages ----------
# GROFF_NO_SGR forces groff to emit overstrike (X^HX) instead of SGR escapes,
# which less then recolors via the LESS_TERMCAP_* mapping below.
export GROFF_NO_SGR=1
export MANPAGER='less -R'
export LESS='-R'
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_us=$'\E[1;32m'
export LESS_TERMCAP_ue=$'\E[0m'
export FZF_DEFAULT_OPTS='--height 40% --border --inline-info'
