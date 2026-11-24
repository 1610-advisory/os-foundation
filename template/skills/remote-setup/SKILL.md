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
bash <root>/skills/remote-setup/check.sh          # Mac or Linux
```
```powershell
powershell -ExecutionPolicy Bypass -File <root>\skills\remote-setup\check.ps1   # Windows
```

On Windows, use a normal PowerShell window in Windows Terminal. Do not use "Run as administrator".

Tell the person each `FAIL` and `ASK` line in plain words. Fix only the failed items, in the order below.

## 1. Claude Code

1. Check it is installed: `claude --version`. If not, install it from the official Claude Code page (ask first).
   - Windows: Claude Code needs Git for Windows first (`winget install --id Git.Git -e`). Then install Claude Code with the PowerShell command on the official page. Close and open the terminal after each install.
2. Check the sign-in: `claude auth status`. `authMethod` must be `claude.ai`. An API key does not work with Remote Control. If needed, the person runs `claude` and types `/login`, then picks their Claude account (Pro, Max, Team or Enterprise).
3. Turn on Remote Control for every new session. Add this line to `~/.claude/settings.json`. Add the line. Never replace the file:
   ```json
   "remoteControlAtStartup": true
   ```
   Or the person runs `claude`, types `/config`, and turns on Remote Control at startup.
4. Set the company defaults for Claude Code (no need to ask). The values are in `skills/remote-setup/defaults.txt` (now `autoCompactWindow`). The script keeps every other setting, makes the file if it is missing, and prints the old and the new value:
   ```bash
   bash <root>/skills/remote-setup/set-settings.sh
   ```
   ```powershell
   powershell -ExecutionPolicy Bypass -File <root>\skills\remote-setup\set-settings.ps1
   ```
   If it says the file is not valid JSON, it changed nothing. Show the person the file and fix it together.
5. Run `claude` once in `<root>` and trust the folder. Then exit.

## 2. Herdr

Herdr keeps terminal sessions alive. Closing the window does not stop them.

1. Check: `herdr --version`. If it is missing, install it (ask first):
   - Mac or Linux: `curl -fsSL https://herdr.dev/install.sh | sh` (or `brew install herdr`)
   - Windows: `powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"`
2. Update an old version: `herdr update` (Homebrew: `brew upgrade herdr`).
3. Install the Claude link, so Herdr can bring Claude sessions back after a restart: `herdr integration install claude`. Check: `herdr integration status` shows `claude: current`.

## 3. Start the company session

1. Start Herdr once: `herdr` (the person can close the window after; it keeps running).
   Never start `herdr server` from an agent's own shell. The server stops when that shell closes. Start it through the LaunchAgent (Mac), the user service (Linux) or the Startup shortcut (Windows), in section 5.
2. Make a workspace and start Claude in it, with Remote Control on and a clear name:
   ```bash
   ws=$(herdr workspace create --cwd "<root>" --label "<slug> OS" --no-focus)
   pane=$(printf '%s' "$ws" | sed -n 's/.*"root_pane":{[^}]*"pane_id":"\([^"]*\)".*/\1/p')
   herdr agent start <slug>-os --kind claude --pane "$pane" --timeout 60000 -- --name "<slug> OS" --remote-control "<slug> OS"
   ```
   Windows (PowerShell):
   ```powershell
   $ws = herdr workspace create --cwd "<root>" --label "<slug> OS" --no-focus | ConvertFrom-Json
   herdr agent start <slug>-os --kind claude --pane $ws.result.root_pane.pane_id --timeout 60000 -- --name "<slug> OS" --remote-control "<slug> OS"
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

**Windows** (no administrator window needed)
- On power, never sleep or hibernate:
  ```powershell
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  ```
- A laptop: on power, closing the lid does nothing:
  ```powershell
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
  ```
  The same settings are in Settings → System → Power, and Control Panel → Power Options → "Choose what closing the lid does".
- Windows Update restarts the computer. Set "Active hours" (Settings → Windows Update → Advanced options) to the hours the person works. After a restart, someone signs in once (section 5).

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
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string><string>"$H" status server 2>/dev/null | grep -q 'status: running' || exec "$H" server</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(dirname "$H"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string></dict>
</dict></plist>
EOF
plutil -lint ~/Library/LaunchAgents/com.company-os.herdr.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.company-os.herdr.plist
```
How it behaves: at sign-in it starts the Herdr server. If Herdr already runs, it does nothing (a second `herdr server` exits with "already running", so the guard checks first). If the server crashes, launchd starts it again after 30 seconds. `herdr server stop` stays stopped until the next sign-in. Remove it with `launchctl bootout gui/$(id -u)/com.company-os.herdr` and delete the file.

**Linux** (ask first). A user service, and linger so it runs without a sign-in:
```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/herdr.service <<EOF
[Unit]
Description=Herdr server
[Service]
ExecStart=/bin/sh -c '"$(command -v herdr)" status server 2>/dev/null | grep -q "status: running" || exec "$(command -v herdr)" server'
Restart=on-failure
RestartSec=30
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now herdr.service
sudo loginctl enable-linger "$USER"
```

**Windows** (ask first). A shortcut in the person's Startup folder starts Herdr at each sign-in, with no window (`conhost.exe --headless`, the same way the sync jobs run). No administrator window is needed:
```powershell
$h = (Get-Command herdr).Source
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Company OS Herdr.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:WINDIR 'System32\conhost.exe'
$s.Arguments = "--headless `"$h`" server"; $s.WorkingDirectory = "<root>"
$s.Save()
```
No window opens, so nothing stays in the taskbar for the person to close by mistake. If Herdr already runs, the shortcut's `herdr server` stops at once with "already running". That is fine. Windows does not restart Herdr after a crash: the person runs `herdr` again. Windows does not start anything before a sign-in. After a restart, someone signs in once. Then Herdr starts and brings back the session.
An older shortcut that starts `herdr.exe` minimized: run the lines above again. They replace it.
Herdr on Windows: it keeps sessions after the window closes. Do not run it as administrator (an administrator server refuses normal windows). Windows may show a SmartScreen warning the first time, because Herdr is not signed. The person checks the publisher and says yes.

## 6. Same account on phone and computer

The phone app shows only sessions of the account it is signed in to. `check.sh` prints the computer's account email. Ask the person to open the Claude app → Settings and compare the email. If they differ, sign out on one side and sign in with the same account.

## 7. Final check

Run the check again and show the result:

Run the same check as in section 0 (`check.sh`, or `check.ps1` on Windows).

Each line is `PASS`, `FAIL` (with the fix) or `ASK` (the person checks it by eye). Done means: no `FAIL`, and the person said yes to each `ASK`. Then do one real test: close the terminal window, lock the phone, wait one minute, and send a message to "<slug> OS" from the phone.
If the restart test matters (it usually does), restart the computer once, sign in, wait two minutes, and send a message from the phone again.

## 8. Restart the session and keep the chat

Use this to restart Claude (for example after an update) and keep the same chat on the phone. Claude comes back with `--resume` and the same session id.

Run the script from a **different** Herdr pane. The session cannot restart itself: `/exit` would stop the script too. Herdr gives the session id and the pane id: `herdr agent get <slug>-os` shows them as `agent_session` → `value` and `pane_id`. Pane ids change after Herdr restarts, so read them again each time. Do not reuse an old id.

Mac or Linux:
```bash
info=$(herdr agent get <slug>-os)
sid=$(printf '%s' "$info" | sed -n 's/.*"agent_session":{[^}]*"value":"\([^"]*\)".*/\1/p')
pane=$(printf '%s' "$info" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')
herdr agent prompt <slug>-os "/exit"
herdr pane wait-output "$pane" --match "claude --resume" --timeout 60000
herdr agent start <slug>-os --kind claude --pane "$pane" --timeout 60000 -- --resume "$sid" --name "<slug> OS" --remote-control "<slug> OS"
```
Windows (PowerShell):
```powershell
$a = (herdr agent get <slug>-os | ConvertFrom-Json).result.agent
herdr agent prompt <slug>-os "/exit"
herdr pane wait-output $a.pane_id --match "claude --resume" --timeout 60000
herdr agent start <slug>-os --kind claude --pane $a.pane_id --timeout 60000 -- --resume $a.agent_session.value --name "<slug> OS" --remote-control "<slug> OS"
```
If `sid` or the pane id is empty, stop. Herdr does not see the session. Start it again with section 3. Test from the phone: the same "<slug> OS" chat answers, with the earlier messages still there.
