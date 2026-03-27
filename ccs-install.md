<!-- ccs-install.md — Agent-readable install guide for cc-account-switcher -->
<!-- Share this file and tell Claude Code / Codex: "follow ccs-install.md to install ccs" -->

CONTEXT: AI agent executing this file. Install `ccs` (Claude Code multi-account switcher) by following each step in order. Run bash blocks exactly as written unless a condition says otherwise.

STOP_IF_ALREADY_INSTALLED: Check first.
```bash
if command -v ccs &>/dev/null; then
  echo "ccs already installed: $(ccs --version) at $(which ccs)"
  echo "Nothing to do. Run 'ccs ls' to see saved accounts."
  exit 0
fi
```

## CONSTRAINTS
- platform: macOS, Linux, or WSL (not Windows CMD/PowerShell)
- requires: bash 3.2+, jq, git or curl
- sudo: needed for `make install` (writes to /usr/local/bin) — prompt the user if needed
- shell_completions: auto-installed for bash/zsh/fish via `make install`

## STEP 1 — DEPENDENCIES

```bash
# jq is required
if ! command -v jq &>/dev/null; then
  if command -v brew &>/dev/null; then
    brew install jq
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y jq
  else
    echo "ERROR: jq not found. Install it manually: https://jqlang.github.io/jq/download/"
    exit 1
  fi
fi
echo "OK: jq $(jq --version)"
```

## STEP 2 — INSTALL

Choose ONE method. `make install` is preferred (also installs shell completions).

**Option A — clone + make (recommended, installs shell completions)**
```bash
git clone https://github.com/eva01/cc-account-switcher.git /tmp/cc-account-switcher
cd /tmp/cc-account-switcher
sudo make install
```

**Option B — curl (quick, no completions)**
```bash
sudo curl -fsSL https://raw.githubusercontent.com/eva01/cc-account-switcher/main/ccswitch.sh \
  -o /usr/local/bin/ccs
sudo chmod +x /usr/local/bin/ccs
```

**Option C — Homebrew (macOS)**
```bash
brew install eva01/tap/ccswitch
```

## STEP 3 — VERIFY INSTALL

```bash
which ccs && ccs --version
# expect: /usr/local/bin/ccs and ccs vX.Y.Z
```

## STEP 4 — FIRST-TIME SETUP

These steps require the user to be logged into Claude Code. Inform the user:

> "ccs is installed. Now save your current Claude Code account:"

```bash
ccs add        # saves current logged-in account
ccs ls         # confirm it was saved
```

If the user has a second account, tell them:
1. Log out of Claude Code and log in with the second account
2. Run `ccs add` again
3. Run `ccs sw` to switch between them (restart Claude Code after each switch)

## STEP 5 — RATE LIMIT AUTO-SWITCH (optional)

Skip this step if the user does not have a statusline script that writes `/tmp/claude-usage-cache.json`.

If they do, set up the PreToolUse hook:
```bash
ccs rate-setup                  # default 80% threshold
# or: ccs rate-setup --threshold 70
```

This installs a Claude Code hook that auto-switches accounts when usage exceeds the threshold.

## VERIFY

```bash
ccs --version           # installed
ccs ls                  # lists saved accounts (at least 1)
ccs status              # shows active account and token expiry
```

Expected state:
- `ccs --version` returns `ccs vX.Y.Z`
- `ccs ls` shows at least one account
- no errors

## QUICK REFERENCE

```bash
ccs add                   # save current account
ccs ls                    # list saved accounts
ccs sw                    # rotate to next account
ccs to work               # switch to profile named "work"
ccs profile 1 work        # name account 1 "work"
ccs status                # show active account
ccs check                 # verify backup integrity
ccs rate-setup            # enable auto-switch on rate limit
```

Source: https://github.com/eva01/cc-account-switcher
