<!-- mac-setup.md — Agent-readable Mac dev environment setup -->
<!-- Tell Claude Code / Codex: "follow mac-setup.md to set up my terminal environment" -->

CONTEXT: AI agent executing this file. Install and configure a Mac terminal environment (Ghostty, Fish, Starship, ccs). Run bash blocks exactly as written. macOS + Homebrew required.

STOP_IF_NOT_MAC:
```bash
if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: macOS only. Detected: $(uname). Halting."
  exit 1
fi
echo "OK: macOS $(sw_vers -productVersion)"
```

STOP_IF_NO_BREW:
```bash
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Install it first:"
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
echo "OK: brew $(brew --version | head -1)"
```

## CONSTRAINTS
- platform: macOS only (Apple Silicon or Intel)
- package_manager: Homebrew only
- configs: pulled from https://github.com/eva01/jin-terminal
- ghostty requires: macOS 13+
- fish shell: will be set as default — warn user before chsh

---

## STEP 1 — INSTALL TOOLS

```bash
brew install --cask ghostty
brew install fish starship eza fastfetch fnm jq
brew install eva01/tap/ccswitch
```

Verify:
```bash
for tool in fish starship eza fastfetch fnm jq ccs; do
  command -v $tool &>/dev/null && echo "OK: $tool $(${tool} --version 2>/dev/null | head -1)" || echo "FAIL: $tool not found"
done
ghostty --version 2>/dev/null && echo "OK: ghostty" || echo "NOTE: ghostty is a GUI app — open it from /Applications"
```

---

## STEP 2 — SET FISH AS DEFAULT SHELL

Inform the user before running this — it will change their login shell.

```bash
FISH_PATH="$(brew --prefix)/bin/fish"

# Add to allowed shells if not already listed
if ! grep -qF "$FISH_PATH" /etc/shells; then
  echo "$FISH_PATH" | sudo tee -a /etc/shells
fi

# Change default shell
chsh -s "$FISH_PATH"
echo "OK: default shell set to $FISH_PATH — restart terminal to take effect"
```

---

## STEP 3 — INSTALL CONFIGS

Pulls configs from https://github.com/eva01/jin-terminal

```bash
REPO="https://raw.githubusercontent.com/eva01/jin-terminal/main"

# Fish
mkdir -p ~/.config/fish
curl -fsSL "$REPO/fish/config.fish" -o ~/.config/fish/config.fish
echo "OK: fish config installed"

# Starship
mkdir -p ~/.config
curl -fsSL "$REPO/starship/starship.toml" -o ~/.config/starship.toml
echo "OK: starship config installed (Catppuccin Mocha two-line prompt)"

# Ghostty
mkdir -p ~/.config/ghostty
curl -fsSL "$REPO/ghostty/config" -o ~/.config/ghostty/config
echo "OK: ghostty config installed (MesloLGS NF, Catppuccin Mocha)"
```

NOTE: ghostty config sets `font-family = MesloLGS NF`. Install the font if not present:
```bash
brew install --cask font-meslo-lg-nerd-font
```

---

## STEP 4 — CCS FIRST-TIME SETUP

Inform the user: "ccs is installed. Save your current Claude Code account."

```bash
ccs --version   # confirm install
ccs add         # save current logged-in account
ccs ls          # confirm it was saved
```

If the user has a second account:
1. Log out of Claude Code, log in with account 2
2. `ccs add`
3. `ccs sw` to rotate (restart Claude Code after each switch)

Optional — auto-switch on rate limit (requires a statusline that writes `/tmp/claude-usage-cache.json`):
```bash
ccs rate-setup   # installs PreToolUse hook at 80% threshold
```

---

## VERIFY

```bash
# Shell
echo $SHELL   # should be /opt/homebrew/bin/fish (after restart)

# Tools
fish --version
starship --version
eza --version
fastfetch --version
fnm --version
ccs --version

# Configs
test -f ~/.config/fish/config.fish    && echo "OK: fish config" || echo "MISSING: fish config"
test -f ~/.config/starship.toml       && echo "OK: starship config" || echo "MISSING: starship config"
test -f ~/.config/ghostty/config      && echo "OK: ghostty config" || echo "MISSING: ghostty config"

# ccs
ccs ls   # should list at least 1 account
```

---

## CHECKLIST

```
[ ] brew install --cask ghostty
[ ] brew install fish starship eza fastfetch fnm jq
[ ] brew install eva01/tap/ccswitch
[ ] fish added to /etc/shells + set as default (chsh)
[ ] configs pulled: fish, starship, ghostty
[ ] font-meslo-lg-nerd-font installed
[ ] ccs add (at least one account saved)
[ ] terminal restarted — fish prompt with starship active
```

---

## UNINSTALL

Each block is independent — skip anything you want to keep.

```bash
# 1. Remove tools
brew uninstall fish starship eza fastfetch fnm jq
brew uninstall eva01/tap/ccswitch
brew uninstall --cask ghostty

# 2. Restore default shell (zsh)
chsh -s /bin/zsh
# Remove fish from /etc/shells
sudo sed -i '' "\|$(brew --prefix)/bin/fish|d" /etc/shells

# 3. Remove configs
rm -f ~/.config/fish/config.fish
rm -f ~/.config/starship.toml
rm -f ~/.config/ghostty/config

# 4. Remove ccs data
rm -rf ~/.claude-switch-backup    # saved account credentials
# If using macOS Keychain:
security delete-generic-password -s "Claude Code-credentials" 2>/dev/null || true

# 5. Remove font (optional)
brew uninstall --cask font-meslo-lg-nerd-font
```

Verify clean:
```bash
command -v fish starship eza ccs 2>/dev/null | head  # should return nothing
echo $SHELL   # should be /bin/zsh
```

---

Source: https://github.com/eva01/jin-terminal
