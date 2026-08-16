# ============================================================
#  monkey-zsh -- single-file Zsh configuration
#  Plugin manager: Zinit (declarative, vim-plug style)
#  Prompt:        plain-text two-line (no icon font required)
# ============================================================

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
compinit -u -d "${XDG_CACHE_HOME:-${HOME}/.cache}/zsh/zcompdump-$ZSH_VERSION"

zinit light Aloxaf/fzf-tab

# fzf system integration (Ctrl-R history / Ctrl-T files / Alt-C directories)
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search

# AI completion (smart-suggestion, default key Ctrl-O) -- enabled automatically
# once any provider API key is set
#   Providers: openai | azure_openai | anthropic | gemini | deepseek
#   Example: export OPENAI_API_KEY="sk-..."
#            export SMART_SUGGESTION_AI_PROVIDER=deepseek
#   Or write config to ~/.config/smart-suggestion/config.zsh
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

precmd() { vcs_info }

# Line 1: user@host  path  git status
# Line 2: prompt char only (>), green=last command OK, red=failed
PROMPT=$'%F{green}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_}\n%(?.%F{green}.%F{red})>%f '
PROMPT2=$'%F{blue}.%f '
PROMPT_EOL_MARK=''

# ---------- Key bindings ----------
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^[OA' history-substring-search-up
bindkey '^[OB' history-substring-search-down

# Tab unified completion: fzf-tab normal completion, fall back to AI when no candidates
# Input starting with # -> translate directly into a command (skip fzf-tab)
# (Active when smart-suggestion is loaded; ^o kept as manual trigger key)
if (( ${+widgets[_do_smart_suggestion]} )); then
  function tab_complete_or_ai() {
    if [[ $BUFFER == '#'* ]]; then
      zle _do_smart_suggestion
      return
    fi
    local buffer_before=$BUFFER
    zle fzf-tab-complete
    if [[ -n $BUFFER && $BUFFER == $buffer_before ]]; then
      zle _do_smart_suggestion
    fi
  }
  zle -N tab_complete_or_ai
  bindkey '^I' tab_complete_or_ai
fi

# ---------- zoxide (smart cd): z <dir>, zi <fzf picker> ----------
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# ---------- Everyday aliases ----------
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --group-directories-first'
  alias la='eza -a --group-directories-first'
  alias l='eza -1'
  alias lt='eza --tree'
  alias lg='eza -lh --git'          # show git status column
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

export MANPAGER='less -R'
export LESS='-R'
export FZF_DEFAULT_OPTS='--height 40% --border --inline-info'