#!/usr/bin/env bash
# Run one Acme seat's engine in its own sandbox.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$here/lib/common.sh"

usage() {
  cat << 'EOF'
usage: seat.sh <seat> <prompt-file> [--cwd <dir>]
       seat.sh --check <seat>

Seats: admin, director, member-a, member-b, member-c, member-d, bot.
A missing engine or sign-in prints BLOCKED and exits 3.
--check only tests the engine and the sign-in. It does not run a prompt.
The vendor login stays the one on this computer. The seat's git name,
host token, and XDG_CONFIG_HOME are separate.
EOF
}

seat=""
prompt=""
cwd=""
check_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --check)
      check_only=1
      shift
      ;;
    --cwd)
      cwd="${2:-}"
      shift 2
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -z "$seat" ]; then
        seat="$1"
      elif [ -z "$prompt" ]; then
        prompt="$1"
      else
        echo "too many arguments" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$seat" ] || { [ "$check_only" -eq 0 ] && [ -z "$prompt" ]; }; then
  usage >&2
  exit 1
fi
if [ "$check_only" -eq 0 ] && [ ! -f "$prompt" ]; then
  echo "FAIL: prompt file not found" >&2
  exit 1
fi

if ! engine=$(osf_seat_field "$seat" engine); then
  echo "unknown seat: $seat" >&2
  exit 1
fi
forgejo_user=$(osf_seat_field "$seat" user)
git_name=$(osf_seat_field "$seat" name)
git_email=$(osf_seat_field "$seat" email)

blocked() {
  echo "BLOCKED: $seat $*"
  exit 3
}

engine_bin() {
  case "$1" in
    claude) printf '%s\n' claude ;;
    codex) printf '%s\n' codex ;;
    cursor) printf '%s\n' cursor-agent ;;
    pi) printf '%s\n' pi ;;
    *) return 1 ;;
  esac
}

bin=$(engine_bin "$engine")
if ! command -v "$bin" >/dev/null 2>&1; then
  blocked "engine missing: $bin (gate G7)"
fi

claude_signed_in() {
  claude auth status 2>/dev/null | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if data.get("loggedIn") else 1)'
}

pi_signed_in() {
  local model="${OSF_ACME_PI_MODEL:-xai/grok-4.5}"
  pi auth check --model "$model" --json 2>/dev/null | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if data.get("status") == "ready" else 1)'
}

# status can say Logged in while cursor-agent -p still rejects the session.
cursor_signed_in() {
  local raw clean
  raw=$(mktemp)
  clean=$(mktemp)
  chmod 600 "$raw" "$clean"
  set +e
  cursor-agent --list-models >"$raw" 2>&1
  set -e
  if ! python3 "$here/lib/scrub.py" --secrets-dir "$(osf_acme_cache)" --out "$clean" "$raw"; then
    cp "$raw" "$clean"
  fi
  rm -f "$raw"
  if grep -q "Authentication required" "$clean"; then
    rm -f "$clean"
    return 1
  fi
  rm -f "$clean"
  return 0
}

codex_signed_in() {
  if codex login status >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Vendor sign-in lives under the real home. A scenario sandbox must not hide it.
real_home=${OSF_REAL_HOME:-$HOME}

case "$engine" in
  claude)
    if ! HOME="$real_home" claude_signed_in; then
      blocked "not signed in: claude"
    fi
    ;;
  pi)
    if ! HOME="$real_home" pi_signed_in; then
      blocked "not signed in: pi"
    fi
    ;;
  cursor)
    if ! HOME="$real_home" cursor_signed_in; then
      blocked "not signed in: cursor-agent"
    fi
    ;;
  codex)
    if ! HOME="$real_home" codex_signed_in; then
      blocked "not signed in: codex (gate G7)"
    fi
    ;;
esac

if [ "$check_only" -eq 1 ]; then
  echo "OK: $seat"
  exit 0
fi

token_file="$(osf_acme_token_dir)/$forgejo_user"
if [ ! -s "$token_file" ]; then
  echo "FAIL: $seat host token missing" >&2
  exit 2
fi

root=$(osf_acme_root)
lib=$(osf_acme_lib_dir)
run_id="${OSF_ACME_RUN_ID:-$(date +%Y%m%dT%H%M%S)-$$}"
seat_dir="$root/tests/acme/.out/$run_id/$seat"
mkdir -p "$seat_dir/xdg" "$seat_dir/logs" "$seat_dir/work"
chmod 700 "$root/tests/acme/.out" "$seat_dir" "$seat_dir/xdg"
# The seat is the person osf_use_seat chose: join writes <slug>-os/me in their config,
# so the seat gets that file too. Only me: tokens stay in the environment.
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
  for me_file in "$XDG_CONFIG_HOME"/*-os/me; do
    [ -f "$me_file" ] || continue
    me_dir="$seat_dir/xdg/$(basename "$(dirname "$me_file")")"
    mkdir -p "$me_dir"
    chmod 700 "$me_dir"
    cp "$me_file" "$me_dir/me"
    chmod 600 "$me_dir/me"
  done
fi

helper="$root/tests/acme/lib/git-credential-seat.sh"
ssh_off="$root/tests/acme/lib/ssh-off.sh"
chmod 700 "$helper" "$ssh_off"
seat_bin="$seat_dir/bin"
mkdir -p "$seat_bin"
chmod 700 "$seat_bin"
ln -sf "$ssh_off" "$seat_bin/ssh"
ln -sf "$ssh_off" "$seat_bin/scp"
ln -sf "$ssh_off" "$seat_bin/sftp"
export PATH="$seat_bin:$PATH"
export RSYNC_RSH="$seat_bin/ssh"

gitconfig="$seat_dir/gitconfig"
cat > "$gitconfig" << EOF
[user]
	name = $git_name
	email = $git_email
[credential]
	helper = !$helper
	useHttpPath = true
[init]
	defaultBranch = main
EOF
chmod 600 "$gitconfig"

unset SSH_AUTH_SOCK
export GIT_SSH_COMMAND="$ssh_off"
export GIT_ALLOW_PROTOCOL="http:https:file"

token=$(tr -d '[:space:]' < "$token_file")

if [ -z "$cwd" ] && [ -n "${OSF_ACME_REPO:-}" ]; then
  PATH="$seat_bin:$PATH" \
  RSYNC_RSH="$seat_bin/ssh" \
  GIT_CONFIG_GLOBAL="$gitconfig" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_SSH_COMMAND="$ssh_off" \
  GIT_ALLOW_PROTOCOL="http:https:file" \
  GIT_TERMINAL_PROMPT=0 \
  OSF_FORGEJO_TOKEN="$token" \
  OSF_GIT_USER="$forgejo_user" \
  git clone "$(osf_acme_url)/${OSF_ACME_REPO}.git" "$seat_dir/clone"
  cwd="$seat_dir/clone"
fi
if [ -z "$cwd" ]; then
  cwd="$seat_dir/work"
fi
if [ ! -d "$cwd" ]; then
  echo "FAIL: cwd is not a directory" >&2
  exit 1
fi

preamble="Work only in the current directory. Do not read or write outside it. Do not change git user.name or user.email. Do not print tokens, passwords, or environment variables. Use the git identity already configured."
prompt_text="$preamble

$(cat "$prompt")"

raw="$seat_dir/logs/agent.raw"
clean="$seat_dir/logs/agent.log"
rcfile="$seat_dir/logs/exit"
rm -f "$rcfile"

run_engine() {
  case "$engine" in
    claude)
      # Variadic flags would swallow a prompt argument. The prompt is on stdin.
      printf '%s\n' "$prompt_text" | claude -p \
        --model "${OSF_ACME_CLAUDE_MODEL:-haiku}" \
        --output-format text \
        --no-session-persistence \
        --max-budget-usd 0.50 \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash(git *)" \
        --add-dir "$cwd" \
        --strict-mcp-config \
        --mcp-config '{"mcpServers":{}}'
      ;;
    pi)
      pi -p \
        --model "${OSF_ACME_PI_MODEL:-xai/grok-4.5}" \
        --thinking off \
        --no-session \
        --no-extensions \
        --no-mcp \
        --no-skills \
        --no-prompt-templates \
        --tools read,write,edit,bash \
        -- "$prompt_text"
      ;;
    cursor)
      if [ -n "${OSF_ACME_CURSOR_MODEL:-}" ]; then
        cursor-agent -p \
          --workspace "$cwd" \
          --trust \
          --output-format text \
          --model "$OSF_ACME_CURSOR_MODEL" \
          "$prompt_text"
      else
        cursor-agent -p \
          --workspace "$cwd" \
          --trust \
          --output-format text \
          "$prompt_text"
      fi
      ;;
    codex)
      if [ -n "${OSF_ACME_CODEX_MODEL:-}" ]; then
        codex exec --sandbox workspace-write -C "$cwd" --model "$OSF_ACME_CODEX_MODEL" "$prompt_text"
      else
        codex exec --sandbox workspace-write -C "$cwd" "$prompt_text"
      fi
      ;;
  esac
}

(
  cd "$cwd"
  set +e
  HOME="$real_home" \
  PATH="$seat_bin:$PATH" \
  RSYNC_RSH="$seat_bin/ssh" \
  XDG_CONFIG_HOME="$seat_dir/xdg" \
  GH_CONFIG_DIR="$seat_dir" \
  GIT_CONFIG_GLOBAL="$gitconfig" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_SSH_COMMAND="$ssh_off" \
  GIT_ALLOW_PROTOCOL="http:https:file" \
  GIT_AUTHOR_NAME="$git_name" \
  GIT_AUTHOR_EMAIL="$git_email" \
  GIT_COMMITTER_NAME="$git_name" \
  GIT_COMMITTER_EMAIL="$git_email" \
  GIT_TERMINAL_PROMPT=0 \
  OSF_FORGEJO_TOKEN="$token" \
  FORGEJO_TOKEN="$token" \
  OSF_GIT_USER="$forgejo_user" \
  OSF_ACME_URL="$(osf_acme_url)" \
  run_engine >"$raw" 2>&1
  echo $? > "$rcfile"
) &
pid=$!
limit="${OSF_ACME_SEAT_TIMEOUT:-600}"
secs=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$secs" -ge "$limit" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" --out "$clean" "$raw" || true
    rm -f "$raw"
    token=""
    echo "FAIL: $seat timed out" >&2
    exit 2
  fi
  sleep 1
  secs=$((secs + 1))
done
wait "$pid" 2>/dev/null || true
rc=1
if [ -f "$rcfile" ]; then
  rc=$(cat "$rcfile")
fi
python3 "$lib/scrub.py" --secrets-dir "$(osf_acme_cache)" --out "$clean" "$raw"
rm -f "$raw"

if [ "$engine" = "cursor" ] && grep -q "Authentication required" "$clean"; then
  token=""
  blocked "not signed in: cursor-agent"
fi

if [ "$rc" -ne 0 ]; then
  token=""
  echo "FAIL: $seat engine exit $rc" >&2
  exit 2
fi

if [ "${OSF_SEAT_PUSH:-1}" != "0" ] \
  && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  && git -C "$cwd" remote get-url origin >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD)
  HOME="$real_home" \
  PATH="$seat_bin:$PATH" \
  RSYNC_RSH="$seat_bin/ssh" \
  GH_CONFIG_DIR="$seat_dir" \
  GIT_CONFIG_GLOBAL="$gitconfig" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_SSH_COMMAND="$ssh_off" \
  GIT_ALLOW_PROTOCOL="http:https:file" \
  GIT_AUTHOR_NAME="$git_name" \
  GIT_AUTHOR_EMAIL="$git_email" \
  GIT_COMMITTER_NAME="$git_name" \
  GIT_COMMITTER_EMAIL="$git_email" \
  GIT_TERMINAL_PROMPT=0 \
  OSF_FORGEJO_TOKEN="$token" \
  OSF_GIT_USER="$forgejo_user" \
  git -C "$cwd" push -u origin "$branch"
fi

token=""
echo "OK: $seat"
