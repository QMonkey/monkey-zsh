# monkey-zsh

A single-file Zsh configuration without heavyweight frameworks like oh-my-zsh.
Plugin management uses [Zinit](https://github.com/zdharma-continuum/zinit)
(declarative, vim-plug style); the prompt is a plain-text two-line layout
(no icon-font dependency).

`~/.zshrc` is a symlink to `~/.zshrc` in this repository — maintain only this one file.

## Features

- **Zinit plugin management**: declarative loading — `zinit light` for the
  plugins, one `as"program"` + `atclone'./build.sh'` ice for smart-suggestion;
  plugins installed under `~/.local/share/zinit`
- **Plain-text two-line prompt**:
  - Line 1: `user@host path git status`
  - Line 2: only the `>` prompt char (green = last command OK, red = failed)
- **Completion** (fzf-tab): fuzzy completion for commands / paths / arguments;
  extra completion definitions via zsh-completions (git, etc.)
- **Autosuggestions**: grey inline history suggestions, accept with →
- **History substring search**: ↑/↓ fuzzy search over history
- **Syntax highlighting**: fast-syntax-highlighting
- **fzf integration**: Ctrl-R history, Ctrl-T files, Alt-C directories
- **AI completion** (optional): smart-suggestion, triggered with Ctrl-O
- **zoxide**: `z` smart cd, `zi` interactive fzf picker
- **eza aliases**: `ls` colored listing, `ll`, `la`, `lt` tree, `lg` git-status
  column (falls back to native `ls` when eza is missing)
- **git aliases + forgit**: plain `g`/`gc`/`gp`/`gst`/... for common git ops;
  forgit adds the fzf-interactive `ga` `gd` `glo` `gco` `gsw` `gbd` `grb` `gbl`
  ... (full table below; loaded only when fzf is installed)

## Requirements

- zsh 5.3+ (the gate `checkhealth.sh` enforces; `install.sh` never builds zsh from source because every supported distro ships >= 5.3)
- git (required; zinit is cloned via git on first startup)
- python3 (required by `checkhealth.sh`; it runs the TIOCSTI injection into the running terminal and the installer's `zsh.env` merge)
- fzf (optional; used by fzf-tab, the Ctrl-R / Ctrl-T / Alt-C widgets, zoxide's `zi` picker and forgit — forgit requires fzf >= 0.60.0)
- zoxide / eza (optional; config degrades gracefully when missing)
- go (optional; needed to build smart-suggestion on first load)

## Install

Pick one of the two ways below: a one-click script, or manual setup.

### Option 1: One-click install

Install zsh and all dependencies, and set up monkey-zsh automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-zsh/master/install.sh | bash 2>&1 | tee monkey-zsh-install.log
```

> The one-liner needs `git` besides `curl` itself: the installer clones this repository into `~/Documents/monkey-zsh` before it can install anything. If `git` is missing, the script stops with an error — install it with your system's package manager and re-run the same command.

What the script does, step by step:

1. Pre-authorize `sudo` once — the only password entry of the whole run — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. Homebrew resets the sudo timestamp on every `brew` invocation and WSL2 clock jumps invalidate tickets; NOPASSWD makes the run immune to both in any command order. If the drop-in cannot be installed, or is written but not parsed, the run falls back to the sudo timestamp: one re-authentication on a long run, and a privileged step that cannot prompt fails and is reported instead
2. Install `git` when the host has none (it is needed to clone this repository, and zinit clones its plugins with it on the first zsh start)
3. Install zsh via the system package manager (no source build — every supported distro ships >= 5.3; checkhealth verifies the version), then switch the login shell to zsh right away (non-interactive; idempotent — skipped when already zsh, or when zsh is not in `/etc/shells`). The switch comes before everything that writes to a profile: the framework picks the target profile from the login shell, so a pending `chsh` would drop the env blocks into the bash profiles instead of `~/.zprofile`
4. Install Homebrew (Linuxbrew) as the second package lane on Linux (on macOS it is the only lane) — it carries the names the distro index lacks or ships far older (fzf is asked from Homebrew first) — and persist its `bin`/`sbin` in the PATH block of step 8
5. Clone monkey-zsh to `~/Documents/monkey-zsh` (or update it if already cloned)
6. Install git, python3, fzf, zoxide, eza and go via `checkhealth.sh --install` (fzf asks Homebrew first, the distro manager second); WSL Windows-PATH shims (`/mnt/...`) are detected and the real Linux packages get installed instead
7. Symlink `~/.zshrc` to the repo and create `~/.zprofile`
8. Persist one PATH block in your login profile: the framework bin dirs (`~/.local/bin`, `${CARGO_HOME:-~/.cargo}/bin`, `GOBIN`/every `GOPATH` entry's bin, `~/.npm-global/bin`) plus the Homebrew `bin`/`sbin` — on macOS Homebrew is prepended like any other bin dir (so it lands below the framework dirs, above `/usr/local/bin`); on Linux/WSL it is inserted positionally (after the system paths, ahead of the WSL `/mnt` shims only)
9. Write `~/.config/env/zsh.env` (0600) with every provider key it seeds plus the proxy trio (`HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY`) — values you exported before the run included, the rest left empty — plus one marker-guarded `source` line in your login profile (see _Provider configuration file_ below)

> Zinit and all plugins are cloned automatically on the first zsh start.
>
> PATH changes only apply to shells started after the install — the script prints how to apply them to the current terminal.

### Option 2: Manual installation

```bash
git clone https://github.com/QMonkey/monkey-zsh ~/Documents/monkey-zsh
ln -sf ~/Documents/monkey-zsh/.zshrc ~/.zshrc
chsh -s /usr/bin/zsh   # switch to zsh (optional)
```

On first startup Zinit is cloned automatically and all plugins are downloaded.

### Install dependencies by OS

```bash
# Ubuntu/Debian
sudo apt-get install zsh git python3 fzf zoxide eza golang-go

# OpenSUSE
sudo zypper install zsh git python3 fzf zoxide eza go

# CentOS (fzf/eza come from EPEL)
sudo dnf install epel-release
sudo dnf install zsh git python3 fzf zoxide eza golang

# Fedora (same names, no EPEL — Fedora ships them in the base repos)
sudo dnf install zsh git python3 fzf zoxide eza golang

# Arch Linux
sudo pacman -S zsh git python fzf zoxide eza go

# macOS
brew install zsh git python3 fzf zoxide eza go
```

Or run the health check with `--install` to auto-install missing
dependencies (the distro manager — `apt`/`zypper`/`dnf`/`pacman` — with the
AUR behind it on Arch, and Homebrew behind that):

```bash
./checkhealth.sh --install
```

`checkhealth.sh` exits 1 when a required dependency is missing (optional
tools only print a red line). `--help` lists the options; `SUDO_DROPIN=0` or
`1` overrides whether `--install` installs the temporary NOPASSWD drop-in
(default: no drop-in for a manual run, drop-in when an installer chains it).

What it checks: the zsh version gate (5.3), the required tools (`git`,
`python3`), the optional ones (`fzf`, `zoxide`, `eza`, `go`), the config files
(`~/.zshrc` — a symlink whose target exists; `~/.zprofile`; the zinit
checkout), and the terminal capabilities plus `LANG`.

### Environment variables (login shell)

bash and zsh read different login files: bash reads `~/.bash_profile`
(often just a `source ~/.bashrc`), zsh reads `~/.zprofile`. Put login-only
environment variables directly in `~/.zprofile`.

Variables that belong to monkey-zsh itself don't go there by hand: the
installer keeps them in `~/.config/env/zsh.env` and `~/.zprofile` gets one
line that sources it (see _Provider configuration file_ below).

Do not `source ~/.profile` or `~/.bashrc` from zsh — `~/.profile` typically
sources `~/.bashrc`, and both are full of bash-only syntax and interactive
settings (PS1, aliases, `[[ ... ]]` guards).

Only affects fresh login shells (SSH, tty). Sessions started inside tmux
inherit the logged-in parent's environment anyway.

## `scripts/` (shared framework)

The `scripts/` directory is a [git subtree](https://git-scm.com/docs/git-subtree)
of [monkey-scripts](https://github.com/QMonkey/monkey-scripts) — the shared
install/checkhealth framework that this repo's `install.sh` and
`checkhealth.sh` are built on. Do not edit it here; update it from upstream:

```bash
# first-time fetch (cloned without the subtree):
git subtree add -P scripts https://github.com/QMonkey/monkey-scripts.git master
# later updates:
git subtree pull -P scripts --squash https://github.com/QMonkey/monkey-scripts.git master
```

The one-click installer works without a subtree: on the `curl | bash` path it
clones _this_ repo straight into the install directory (`~/Documents/monkey-zsh`)
and runs the `install.sh` from that clone, so the installer and the `scripts/`
it loads always come from the same revision. If that directory already exists
but is not a git clone, the installer refuses to touch it and tells you so.
Once the subtree above is committed and
pushed, a regular `git clone` of this repo already contains `scripts/` —
there is nothing extra to clone or pull; updates arrive through a plain
`git pull`. Only a checkout from before that commit lacks `scripts/`:
`git pull` (or re-running `install.sh`, which pulls that checkout in place)
fixes it.

## Daily usage

| Action                       | Key / command                                     |
| ---------------------------- | ------------------------------------------------- |
| Reload config                | `source ~/.zshrc` (`exec zsh` if plugins changed) |
| Update all plugins           | `zinit update`                                    |
| Update zinit itself          | `zinit self-update`                               |
| Fuzzy completion             | Tab (fzf-tab)                                     |
| History substring search     | ↑ / ↓                                             |
| Accept autosuggestion        | →                                                 |
| fzf history                  | Ctrl-R                                            |
| fzf files                    | Ctrl-T                                            |
| fzf directory change         | Alt-C                                             |
| AI completion                | Ctrl-O                                            |
| Smart cd                     | `z keyword`                                       |
| Interactive directory picker | `zi`                                              |

## forgit (fzf-powered git)

All commands open an fzf picker for interactive selection. Plain `git`
aliases (`g`/`gc`/`gp`/`gst`/...) live in the Aliases section below.

| Alias    | Action                          |
| -------- | ------------------------------- |
| `ga`     | add files / hunks               |
| `grh`    | reset HEAD (pick commit)        |
| `grs`    | restore file                    |
| `glo`    | log (browse commits)            |
| `grl`    | reflog                          |
| `gd`     | diff (working tree vs. commits) |
| `gso`    | show commit                     |
| `gi`     | edit .gitignore                 |
| `gat`    | edit .gitattributes             |
| `gcf`    | checkout file                   |
| `gcff`   | checkout file from a commit     |
| `gcb`    | checkout branch                 |
| `gsw`    | switch branch                   |
| `gco`    | checkout commit                 |
| `gct`    | checkout tag                    |
| `gbd`    | delete branch                   |
| `grc`    | revert commit                   |
| `gclean` | clean untracked files           |
| `gss`    | show stash                      |
| `gsp`    | stash push                      |
| `gcp`    | cherry-pick from branch         |
| `grb`    | rebase                          |
| `gfu`    | fixup commit                    |
| `gsq`    | squash commit                   |
| `grw`    | reword commit                   |
| `gbl`    | blame                           |
| `gwt`    | worktree                        |
| `gwa`    | worktree add                    |
| `gwd`    | worktree delete                 |

## AI completion (smart-suggestion)

Enabled by `.zshrc` when `SMART_SUGGESTION_AI_PROVIDER` names a provider, or
when any of `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` /
`DEEPSEEK_API_KEY` is set; otherwise the plugin is not loaded at all. The
default is OpenAI — one variable is enough:

```bash
export OPENAI_API_KEY="sk-..."
```

Any other provider is the same shape — set its own key (e.g.
`DEEPSEEK_API_KEY="sk-..."`); no switch needed. With several keys set and the
switch left empty, the plugin picks the first non-empty provider in its own
order: openai, azure_openai, anthropic, gemini, deepseek. Two cases do name
the switch:

```bash
# 1. Azure-only: the gate tests none of the Azure keys, so without this the
#    plugin is never loaded.
export SMART_SUGGESTION_AI_PROVIDER=azure_openai
export AZURE_OPENAI_API_KEY="..."
export AZURE_OPENAI_RESOURCE_NAME="..."     # or AZURE_OPENAI_BASE_URL
export AZURE_OPENAI_DEPLOYMENT_NAME="..."

# 2. Several keys set and you want a specific one:
export SMART_SUGGESTION_AI_PROVIDER=gemini
```

Providers: `openai | azure_openai | anthropic | gemini | deepseek`.
Configuration is environment-only — smart-suggestion reads no config file;
`~/.config/env/zsh.env` is where the installer keeps these variables (below).

### Custom endpoint (OpenAI-compatible)

Point a provider at any compatible API (DeepSeek, Ollama, vLLM, ...) via its
`*_BASE_URL` variable, e.g.:

```bash
export SMART_SUGGESTION_AI_PROVIDER=openai
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.deepseek.com"
```

Anthropic example:

```bash
export SMART_SUGGESTION_AI_PROVIDER=anthropic
export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"
```

Available: `OPENAI_BASE_URL` (also works for local OpenAI-compatible servers
like Ollama — every `*_BASE_URL` is only a prefix and the plugin appends its
own path, `/v1/chat/completions` for openai, so give the host root:
`http://localhost:11434`), `AZURE_OPENAI_BASE_URL`,
`ANTHROPIC_BASE_URL`, `GEMINI_BASE_URL`, `DEEPSEEK_BASE_URL`.

Which model a request carries is decided per provider, and the surfaces are
not uniform:

| provider       | where its model comes from                                        | can you choose it                      |
| -------------- | ----------------------------------------------------------------- | -------------------------------------- |
| `openai`       | fixed in the plugin                                               | **no** — there is no `OPENAI_MODEL`    |
| `anthropic`    | fixed in the plugin                                               | **no** — there is no `ANTHROPIC_MODEL` |
| `azure_openai` | `AZURE_OPENAI_DEPLOYMENT_NAME`, which _is_ the `model` field sent | yes, through that variable             |
| `gemini`       | `GEMINI_MODEL`, else the plugin's own default                     | yes                                    |
| `deepseek`     | `DEEPSEEK_MODEL`, else the plugin's own default                   | yes                                    |

`AZURE_OPENAI_API_VERSION` pins the API version, not the model.

Two consequences worth knowing before you rely on either side:

- Against a plain OpenAI- or Anthropic-compatible endpoint you cannot pick the
  model from the plugin at all — there is no variable and no flag for it.
- If you route such a provider through a proxy or gateway that terminates the
  request and fills in its own model, the plugin's value never reaches the
  upstream: the proxy decides. That choice belongs to the proxy's own
  configuration, not to zsh, so it is deliberately not a key in `zsh.env` and
  nothing here names it.

### Provider configuration file (`~/.config/env/zsh.env`)

**`~/.config/env/zsh.env` is zsh's environment file, and these variables do
not have to live in your profile by hand.** The profiles source it with
`set -a`, so everything in it reaches zsh and every process zsh starts —
smart-suggestion's provider set is just what the installer seeds there today.
If you export those variables before running the installer, the install
persists them: every seeded key lands in that file (0600, in the family's
shared env-file directory) and your login profile gets one marker-guarded
line that sources it:

```bash
# [normal] zsh env (remove these lines to disable)
[[ -f ~/.config/env/zsh.env ]] && { set -a; source ~/.config/env/zsh.env; set +a; }
```

The path is built from `$ZSH_ENV_FILE`, which follows `$XDG_CONFIG_HOME`. While
that lands under `$HOME` the line is written `~`-relative, which is how a person
reads a profile and how the rest of the family's lines look; the absolute form
is kept only when `$XDG_CONFIG_HOME` points outside `$HOME`, because a literal
`~` would then name a different file.

(The line is written once, at install time, and is not re-expanded afterwards:
it carries the literal `~` form only when the file really is under `$HOME`.)

Rules of that block (the file and the variable names are monkey-zsh's own —
no other project's credential store or variables are read or written):

- The file and the profile line are written on **every** run, even when the
  install exported nothing — every key is there, empty, ready to fill in.
- `SMART_SUGGESTION_AI_PROVIDER` empty means nothing is pinned: the plugin
  detects its provider from whichever API key is set. A value outside
  `openai | azure_openai | anthropic | gemini | deepseek` is reported (such a
  provider fails every request) and the keys are written anyway, so fixing it
  is one line in the file.
- Every seeded key is in the file, and **empty means unset**: the plugin tests
  each provider variable against `""` and falls back to its own endpoint
  default, so an empty line cannot build a half-configured URL.
- Only the provider set is seeded. The plugin's own behaviour knobs
  (trigger key, send-context, debug, proxy mode, auto-update, update interval,
  history lines, binary path) configure the plugin, not zsh's AI access, so they
  are not written here and keep their upstream defaults (`^o`, `true`, `false`,
  `true`, `true`, `7`, `10`, self-located). Set them wherever you configure that
  plugin; note that they are guarded by zsh's `${+VAR}` **presence** test, so a
  name you write into any sourced file as empty counts as set and wipes its
  default — nothing in this repo normalizes that any more.
- When the selected provider is missing a key it cannot work without, the
  installer names them and warns; the file is still written, so filling those
  lines by hand needs no re-run.
- Your own variables survive: `render_fill` rewrites only the keys it was
  handed, so anything else you add to the file passes through byte for byte.
- A value already in `zsh.env` wins over this run's export (fill-empty
  semantics): re-running the installer never clobbers a hand-edit, and to
  change a value you edit that file. Re-runs also never duplicate the block.
  The proxy trio is the exception worth remembering: those names are the
  host's, may also be filled in another project's env file, and since nothing
  rewrites a non-empty line, a rotation has to be applied to every file that
  lists them — while an empty line here blanks the inherited value for the
  whole zsh subtree, because this file is sourced last.
- Two sets are seeded and the test differs for each. The provider keys are
  what the plugin reads by name. The proxy trio (`HTTPS_PROXY`, `HTTP_PROXY`,
  `NO_PROXY`) is not a plugin setting at all — it is the environment that
  binary inherits when it dials the gateway, so it is listed here to give you
  one place to fill it in, and `NO_PROXY` additionally arrives with the
  loopback binds merged into whatever you exported (a provider pointed at
  `127.0.0.1` must not be proxied; `lib/env.sh` `no_proxy_floor` owns that
  rule and the key list, so no project can spell them differently). The
  machine-specific part of a configuration is still its **value**, not its
  key: every one of these lines is seeded empty, never with this host's
  answer baked in — see _Custom endpoint (OpenAI-compatible)_
  above for who decides the model when the plugin does not.

## Aliases

```text
ls ll la l lt lg    # eza family (lt = tree, lg = git status)
grep rg             # colored grep / rg (--hidden)
.. ... ....         # go up 1/2/3 levels
cat                 # untouched (no bat alias, keeps pipelines safe)
git aliases         # g gaa gau gapa gb gba gbD gc gca gcam gcmsg gdca gf gfa
                    # gl glg gm gp gst gsta gstp gswc
```

## Uninstall

```bash
rm ~/.zshrc
rm -rf ~/.local/share/zinit
rm -rf ~/.cache/zsh ~/.local/state/zsh/history
rm ~/.config/env/zsh.env   # and delete the "zsh env" lines from ~/.zprofile
```

## Notes

- In this config `zi` belongs to zoxide (interactive picker). zinit registers
  a `zi=zinit` alias of its own, which is unaliased in `.zshrc`.
- Use `zinit update` to update plugins (there is no `zi` command for zinit here).
- `.zshrc` pins the emacs keymap (`bindkey -e`): with neither the `emacs` nor
  the `vi` option set, zsh takes the keymap from `$EDITOR`, and an `$EDITOR`
  whose name contains "vi" (nvim, vim) puts the shell in `viins`, where → and
  ^E stop accepting the grey suggestion.
