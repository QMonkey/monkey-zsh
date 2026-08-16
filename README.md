# monkey-zsh

A single-file Zsh configuration without heavyweight frameworks like oh-my-zsh.
Plugin management uses [Zinit](https://github.com/zdharma-continuum/zinit)
(declarative, vim-plug style); the prompt is a plain-text two-line layout
(no icon-font dependency).

`~/.zshrc` is a symlink to `~/.zshrc` in this repository — maintain only this one file.

## Features

- **Zinit plugin management**: declarative loading with ice modifiers
  (compile / programs / lazy load); plugins installed under `~/.local/share/zinit`
- **Plain-text two-line prompt**:
  - Line 1: `user@host path git status`
  - Line 2: only the `>` prompt char (green = last command OK, red = failed)
- **Completion** (fzf-tab): fuzzy completion for commands / paths / arguments;
  extra completion definitions via zsh-completions (git, etc.)
- **Autosuggestions**: grey inline history suggestions, accept with →
- **History substring search**: ↑/↓ fuzzy search over history
- **Syntax highlighting**: fast-syntax-highlighting
- **fzf integration**: Ctrl-R history, Ctrl-T files, Alt-C directories
- **AI completion** (optional): smart-suggestion, merged into Tab
  (falls back to AI when no candidates)
- **zoxide**: `z` smart cd, `zi` interactive fzf picker
- **eza aliases**: `ls` colored listing, `ll`, `la`, `lt` tree, `lg` git-status
  column (falls back to native `ls` when eza is missing)

## Requirements

- zsh 5.3+ (zinit's minimum; most features work on 5.1+, 5.3 enables the full feature set)
- fzf (optional; used by fzf-tab and the AI picker)
- zoxide / eza (optional; config degrades gracefully when missing)
- go (optional; needed to build smart-suggestion on first load)

## Install

```sh
git clone https://github.com/qmonkey/monkey-zsh ~/Documents/monkey-zsh
ln -sf ~/Documents/monkey-zsh/.zshrc ~/.zshrc
chsh -s /usr/bin/zsh   # switch to zsh (optional)
```

On first startup Zinit is cloned automatically and all plugins are downloaded.

### Environment variables (login shell)

bash and zsh read different login files: bash reads `~/.bash_profile`
(often just a `source ~/.bashrc`), zsh reads `~/.zprofile`. Put login-only
environment variables directly in `~/.zprofile`.

Do not `source ~/.profile` or `~/.bashrc` from zsh — `~/.profile` typically
sources `~/.bashrc`, and both are full of bash-only syntax and interactive
settings (PS1, aliases, `[[ ... ]]` guards).

Only affects fresh login shells (SSH, tty). Sessions started inside tmux
inherit the logged-in parent's environment anyway.

## Daily usage

| Action | Key / command |
|---|---|
| Reload config | `source ~/.zshrc` (`exec zsh` if plugins changed) |
| Update all plugins | `zinit update` |
| Update zinit itself | `zinit self-update` |
| Fuzzy completion | Tab (fzf-tab) |
| History substring search | ↑ / ↓ |
| Accept autosuggestion | → |
| fzf history | Ctrl-R |
| fzf files | Ctrl-T |
| fzf directory change | Alt-C |
| AI completion | Tab (when no candidates) or Ctrl-O |
| Improvised translation | `# description` + Tab replaces it with a command |
| Smart cd | `z keyword` |
| Interactive directory picker | `zi` |

## AI completion (smart-suggestion)

Enabled automatically once any provider API key is set, otherwise fully disabled:

```sh
export OPENAI_API_KEY="sk-..."
# or
export SMART_SUGGESTION_AI_PROVIDER=deepseek
export DEEPSEEK_API_KEY="..."
```

Providers: `openai | azure_openai | anthropic | gemini | deepseek`.
You can also put config in `~/.config/smart-suggestion/config.zsh`.

### Custom endpoint (OpenAI-compatible)

Point a provider at any compatible API (DeepSeek, Ollama, vLLM, ...) via its
`*_BASE_URL` variable, e.g.:

```sh
export SMART_SUGGESTION_AI_PROVIDER=openai
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.deepseek.com"
```

Anthropic example:

```sh
export SMART_SUGGESTION_AI_PROVIDER=anthropic
export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"
```

Available: `OPENAI_BASE_URL` (also works for local OpenAI-compatible servers
like Ollama, e.g. `http://localhost:11434/v1`), `AZURE_OPENAI_BASE_URL`,
`ANTHROPIC_BASE_URL`, `GEMINI_BASE_URL`, `DEEPSEEK_BASE_URL`.

## Aliases

```
ls ll la l lt lg    # eza family (lt = tree, lg = git status)
grep rg             # colored grep / rg (--hidden)
.. ... ....         # go up 1/2/3 levels
cat                 # untouched (no bat alias, keeps pipelines safe)
```

## Uninstall

```sh
rm ~/.zshrc
rm -rf ~/.local/share/zinit
rm -rf ~/.cache/zsh ~/.local/state/zsh/history
```

## Notes

- In this config `zi` belongs to zoxide (interactive picker). zinit registers
  a `zi=zinit` alias of its own, which is unaliased in `.zshrc`.
- Use `zinit update` to update plugins (there is no `zi` command for zinit here).