---
name: remote-setup
description: >
  Set up a teammate's own computer so they can reach Claude Code from their phone
  (Remote Control) in a session that stays alive: install and check Herdr and Claude
  Code, start the company session with Remote Control on, keep the computer awake,
  start again after a reboot, and end with a pass or fail check for each item. Use
  when someone says "set up remote", "use Claude from my phone", "Remote Control does
  not work", "my session dies", "the phone cannot see my computer", "the desktop app
  keeps crashing", "keep my session alive", or "check my remote setup".
---

# Remote setup

You set up **this person's own computer** so they can talk to a Claude Code session from the Claude app on their phone. The session runs on the computer, in the company folder. **Herdr** keeps it alive when the terminal window closes, and brings it back after a restart.

Rules for this skill:
- Work on this computer only. Never change another person's computer.
- Ask before each install and each system setting. Say what it changes. Wait for a clear yes.
- The person types their own password (`sudo`, sign-in). Never ask for a password, token or code in chat.
- Use plain words. One step at a time. After each step, say what changed.
- The Claude desktop app is not needed for this. If it crashes, use Claude Code in Herdr instead.

Find the company root from the company rules. Call it `<root>`. `<slug>` is the company short name from `company-profile.md`.

## 0. Check first

Run the check before you change anything:

```bash
bash <root>/skills/remote-setup/check.sh
```

Tell the person each `FAIL` and `ASK` line in plain words. Fix only the failed items, in the order below.

## 1. Claude Code

1. Check it is installed: `claude --version`. If not, install it from the official Claude Code page (ask first).
2. Check the sign-in: `claude auth status`. `authMethod` must be `claude.ai`. An API key does not work with Remote Control. If needed, the person runs `claude` and types `/login`, then picks their Claude account (Pro, Max, Team or Enterprise).
3. Turn on Remote Control for every new session. Add this line to `~/.claude/settings.json`. Add the line. Never replace the file:
   ```json
   "remoteControlAtStartup": true
   ```
   Or the person runs `claude`, types `/config`, and turns on Remote Control at startup.
4. Run `claude` once in `<root>` and trust the folder. Then exit.

## 2. Herdr

Herdr keeps terminal sessions alive. Closing the window does not stop them.

1. Check: `herdr --version`. If it is missing, install it (ask first):
   - Mac or Linux: `curl -fsSL https://herdr.dev/install.sh | sh` (or `brew install herdr`)
   - Windows: `powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"`
2. Update an old version: `herdr update` (Homebrew: `brew upgrade herdr`).
3. Install the Claude link, so Herdr can bring Claude sessions back after a restart: `herdr integration install claude`. Check: `herdr integration status` shows `claude: current`.

## 3. Start the company session

1. Start Herdr once: `herdr` (the person can close the window after; it keeps running).
2. Make a workspace and start Claude in it, with Remote Control on and a clear name:
   ```bash
   ws=$(herdr workspace create --cwd "<root>" --label "<slug> OS" --no-focus)
   pane=$(printf '%s' "$ws" | sed -n 's/.*"root_pane":{[^}]*"pane_id":"\([^"]*\)".*/\1/p')
   herdr agent start <slug>-os --kind claude --pane "$pane" --timeout 60000 -- --name "<slug> OS" --remote-control "<slug> OS"
   ```
   The name must start with a letter: lowercase letters, digits, `-` or `_`.
3. If the start says `agent_not_ready`, read the screen: `herdr agent read <slug>-os --lines 40`. Help the person answer the folder-trust question for their own company folder. Stop at any other question and tell them.
4. Test from the phone: open the Claude app, find "<slug> OS" in the session list, and ask "Which folder are you in?". The answer must be `<root>`.

## 4. Keep the computer awake

A sleeping computer drops the session. Ask before each change. Explain the cost (power use, heat).

**Mac**
- On the power adapter, never sleep (the screen may still turn off): `sudo pmset -c sleep 0`
- A laptop sleeps when the lid closes. Keep the lid open, or use an external display, keyboard and power (clamshell mode). Do not turn off lid sleep with hidden settings: a closed laptop in a bag can overheat.
- Restart after a power cut (desktop Macs only; `pmset -g cap` lists `autorestart`): `sudo pmset -a autorestart 1`
- After a restart with FileVault on, the person must sign in once at the computer before Herdr can start.

**Linux**
- Stop sleep: `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
- Lid on power: set `HandleLidSwitchExternalPower=ignore` in `/etc/systemd/logind.conf`, then `sudo systemctl restart systemd-logind`.

**Windows**
- Settings → System → Power: on power, "Sleep" = Never. Lid close on power = "Do nothing".

## 5. Start again after a reboot or crash

Herdr brings back its workspaces and the Claude sessions after it starts again. It must start by itself at sign-in.

**Mac** (ask first). Write `~/Library/LaunchAgents/com.company-os.herdr.plist`, then load it:
```bash
H=$(command -v herdr)
cat > ~/Library/LaunchAgents/com.company-os.herdr.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.company-os.herdr</string>
  <key>ProgramArguments</key><array><string>$H</string><string>server</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(dirname "$H"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string></dict>
</dict></plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.company-os.herdr.plist
```
If Herdr was already running, the new job may exit at once. That is fine: it starts Herdr at the next sign-in.

**Linux** (ask first). A user service, and linger so it runs without a sign-in:
```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/herdr.service <<EOF
[Unit]
Description=Herdr server
[Service]
ExecStart=$(command -v herdr) server
Restart=always
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now herdr.service
sudo loginctl enable-linger "$USER"
```

**Windows.** Herdr on Windows has limits. Add a shortcut to `herdr` in the Startup folder (`shell:startup`). Check by hand after a restart.

## 6. Same account on phone and computer

The phone app shows only sessions of the account it is signed in to. `check.sh` prints the computer's account email. Ask the person to open the Claude app → Settings and compare the email. If they differ, sign out on one side and sign in with the same account.

## 7. Final check

Run the check again and show the result:

```bash
bash <root>/skills/remote-setup/check.sh
```

Each line is `PASS`, `FAIL` (with the fix) or `ASK` (the person checks it by eye). Done means: no `FAIL`, and the person said yes to each `ASK`. Then do one real test: close the terminal window, lock the phone, wait one minute, and send a message to "<slug> OS" from the phone.

On Windows, `check.sh` runs in Git Bash, but some checks say `ASK`. Go through sections 4 and 5 by hand.
