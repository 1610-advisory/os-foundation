#!/bin/bash
# Shared helpers for nightly review and reports. Source this file. Do not run it.
set -euo pipefail

nr_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

nr_have_gnu_date() {
  date -d "2020-01-01" +%Y >/dev/null 2>&1
}

nr_epoch() {
  local d=$1
  if nr_have_gnu_date; then
    date -d "${d} 12:00:00" +%s
  else
    date -j -f "%Y-%m-%d %H:%M:%S" "${d} 12:00:00" +%s
  fi
}

nr_date_from_epoch() {
  local e=$1
  if nr_have_gnu_date; then
    date -d "@${e}" +%Y-%m-%d
  else
    date -r "$e" +%Y-%m-%d
  fi
}

nr_date_add() {
  local d=$1 n=$2 e
  e=$(nr_epoch "$d")
  e=$((e + n * 86400))
  nr_date_from_epoch "$e"
}

nr_dow() {
  local d=$1
  if nr_have_gnu_date; then
    date -d "${d} 12:00:00" +%u
  else
    date -j -f "%Y-%m-%d %H:%M:%S" "${d} 12:00:00" +%u
  fi
}

nr_doy() {
  local d=$1 raw
  if nr_have_gnu_date; then
    raw=$(date -d "${d} 12:00:00" +%j)
  else
    raw=$(date -j -f "%Y-%m-%d %H:%M:%S" "${d} 12:00:00" +%j)
  fi
  printf '%d\n' "$((10#$raw))"
}

# ISO week, Monday start. Prints YYYY-Www.
nr_iso_week() {
  local d=$1 dow delta thu year doy week
  dow=$(nr_dow "$d")
  delta=$((4 - dow))
  thu=$(nr_date_from_epoch $(( $(nr_epoch "$d") + delta * 86400 )))
  year=${thu%%-*}
  doy=$(nr_doy "$thu")
  week=$(( (doy - 1) / 7 + 1 ))
  printf '%s-W%02d\n' "$year" "$week"
}

nr_week_start() {
  local d=$1 dow
  dow=$(nr_dow "$d")
  nr_date_add "$d" $((1 - dow))
}

# Monday and the next Monday of an ISO week label, such as 2026-W43.
nr_week_span() {
  local label=$1 year week jan4 dow monday start
  year=${label%%-W*}
  week=${label#*-W}
  week=$((10#$week))
  jan4="${year}-01-04"
  dow=$(nr_dow "$jan4")
  monday=$(nr_date_add "$jan4" $((1 - dow)))
  start=$(nr_date_add "$monday" $(( (week - 1) * 7 )))
  printf '%s %s\n' "$start" "$(nr_date_add "$start" 7)"
}

nr_lock() {
  local dir pid
  dir="$NR_STATE_DIR/lock"
  if mkdir "$dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$dir/pid"
    NR_LOCK_DIR=$dir
    return 0
  fi
  pid=$(cat "$dir/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' "another nightly run is running" >&2
    exit 2
  fi
  rm -rf "$dir"
  if ! mkdir "$dir" 2>/dev/null; then
    printf '%s\n' "another nightly run is running" >&2
    exit 2
  fi
  printf '%s\n' "$$" > "$dir/pid"
  NR_LOCK_DIR=$dir
}

nr_unlock() {
  if [ -n "${NR_LOCK_DIR:-}" ] && [ -d "$NR_LOCK_DIR" ]; then
    rm -rf "$NR_LOCK_DIR"
  fi
  NR_LOCK_DIR=""
}

nr_today() {
  local raw
  if [ -n "${OS_NOW:-}" ]; then
    raw=$OS_NOW
  else
    raw=$(date +%Y-%m-%d)
  fi
  printf '%s\n' "${raw%%T*}" | cut -d' ' -f1
}

nr_valid_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

nr_valid_week() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-W[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

nr_profile() {
  local key=$1 bin out rc
  bin="$NR_ROOT/skills/_host/profile.sh"
  if [ ! -f "$bin" ]; then
    printf '%s\n' "host layer is missing" >&2
    exit 2
  fi
  set +e
  out=$(bash "$bin" "$key" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    return "$rc"
  fi
  printf '%s\n' "$out"
}

nr_switch_on() {
  local name=$1 hit
  hit=$(nr_profile switches | grep -x "$name" || true)
  [ -n "$hit" ]
}

nr_state_dir() {
  local base slug
  slug=$(nr_profile company_slug | head -n 1)
  base=${XDG_CONFIG_HOME:-$HOME/.config}
  printf '%s/%s-os/state\n' "$base" "$slug"
}

nr_fm_get() {
  local file=$1 key=$2
  awk -v key="$key" '
    function strip(s) {
      gsub(/\r/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    function unquote(s) {
      if (s ~ /^".*"$/) return substr(s, 2, length(s) - 2)
      return s
    }
    BEGIN { in_fm = 0; n = 0; mode = "" }
    /^---[[:space:]]*$/ {
      n++
      if (n == 1) { in_fm = 1; next }
      exit
    }
    !in_fm { next }
    mode == "list" {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        sub(/[[:space:]]+#.*$/, "", item)
        item = unquote(strip(item))
        if (item != "") print item
        next
      }
      exit
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      if (line !~ /^[^:]+:/) next
      k = line
      sub(/:.*/, "", k)
      k = strip(k)
      if (k != key) next
      val = line
      sub(/^[^:]*:[[:space:]]*/, "", val)
      val = strip(val)
      if (val == "" || val == "|" || val == ">") { mode = "list"; next }
      if (val == "[]") exit
      if (val ~ /^\[[^]]*\]$/) {
        inner = substr(val, 2, length(val) - 2)
        nitems = split(inner, items, ",")
        for (i = 1; i <= nitems; i++) {
          item = unquote(strip(items[i]))
          if (item != "") print item
        }
        exit
      }
      print unquote(val)
      exit
    }
  ' "$file"
}

nr_person_heading() {
  awk '/^# / { sub(/^# /, ""); print; exit }' "$1"
}

nr_admin_slug() {
  local f role slug
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    role=$(nr_fm_get "$f" role | head -n 1 || true)
    if [ "$role" = "admin" ]; then
      slug=$(nr_fm_get "$f" slug | head -n 1 || true)
      if [ -n "$slug" ]; then
        printf '%s\n' "$slug"
        return 0
      fi
    fi
  done
  printf '%s\n' "admin"
}

nr_director_slug() {
  local area=$1 f role slug hit
  if [ -z "$area" ] || [ "$area" = "company" ]; then
    nr_admin_slug
    return 0
  fi
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    role=$(nr_fm_get "$f" role | head -n 1 || true)
    [ "$role" = "director" ] || continue
    hit=$(nr_fm_get "$f" areas | grep -x "$area" || true)
    if [ -n "$hit" ]; then
      slug=$(nr_fm_get "$f" slug | head -n 1 || true)
      if [ -n "$slug" ]; then
        printf '%s\n' "$slug"
        return 0
      fi
    fi
  done
  nr_admin_slug
}

nr_slug_known() {
  local want=$1 f slug
  [ -n "$want" ] || return 1
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    slug=$(nr_fm_get "$f" slug | head -n 1 || true)
    if [ "$slug" = "$want" ]; then
      return 0
    fi
  done
  return 1
}

nr_slug_by_email() {
  local email=$1 f got slug
  [ -n "$email" ] || return 0
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    got=$(nr_fm_get "$f" email | head -n 1 || true)
    if [ "$got" = "$email" ]; then
      slug=$(nr_fm_get "$f" slug | head -n 1 || true)
      printf '%s\n' "$slug"
      return 0
    fi
  done
}

nr_slug_by_name() {
  local name=$1 f heading slug
  [ -n "$name" ] || return 0
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    heading=$(nr_person_heading "$f" || true)
    slug=$(nr_fm_get "$f" slug | head -n 1 || true)
    if [ "$heading" = "$name" ] || [ "$slug" = "$name" ]; then
      printf '%s\n' "$slug"
      return 0
    fi
  done
}

nr_person_name() {
  local slug=$1 f got heading
  for f in "$NR_ROOT"/people/*.md; do
    [ -f "$f" ] || continue
    got=$(nr_fm_get "$f" slug | head -n 1 || true)
    if [ "$got" = "$slug" ]; then
      heading=$(nr_person_heading "$f" || true)
      if [ -n "$heading" ]; then
        printf '%s\n' "$heading"
      else
        printf '%s\n' "$slug"
      fi
      return 0
    fi
  done
  printf '%s\n' "$slug"
}

nr_is_rules_path() {
  local p=$1 base
  base=$(basename "$p")
  case "$base" in
    AGENTS.md|CLAUDE.md|review-rules.md|CODEOWNERS) return 0 ;;
  esac
  case "$p" in
    skills/*|*/skills/*|.github/*|*/.github/*|.claude/*|*/.claude/*) return 0 ;;
    bots/*/BOT.md|*/bots/*/BOT.md) return 0 ;;
  esac
  return 1
}

nr_safe_rel() {
  local p=$1
  case "$p" in
    ""|/*|..|../*|*/../*|*/..) return 1 ;;
    *$'\n'*|*'|'*) return 1 ;;
  esac
  printf '%s\n' "$p"
}

nr_ranking_line() {
  printf '%s\n' "$1" | grep -E -i -q \
    '(^|[^A-Za-z])(rank|ranks|ranked|ranking|score|scores|scored|scoring|leaderboard|rating|ratings|outperform|underperform)([^A-Za-z]|$)'
}

nr_private_line() {
  printf '%s\n' "$1" | grep -E -i -q \
    'source:[[:space:]]*private|said in a DM|in a DM|private channel|personal mailbox|from an email'
}

nr_area_of() {
  local rel=$1
  case "$rel" in
    .) printf '%s\n' "company" ;;
    areas/*) printf '%s\n' "${rel#areas/}" ;;
    *) printf '%s\n' "$rel" ;;
  esac
}

nr_rand() {
  od -An -N4 -tx1 /dev/urandom | tr -d ' \n'
}

nr_fail_line() {
  if [ "${NR_LOGGED_FAIL:-0}" = "1" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$NR_LOG")"
  printf '%s The review did not run.\n' "$NR_DATE" >> "$NR_LOG"
  chmod 600 "$NR_LOG"
  NR_LOGGED_FAIL=1
  NR_FAILED=1
}

nr_load_engine() {
  local engine
  engine=$(nr_profile sync_engine | head -n 1 || true)
  engine=$(printf '%s' "$engine" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$engine" ]; then
    return 1
  fi
  # The profile command is split on spaces. Paths in it must not contain spaces.
  # shellcheck disable=SC2206
  NR_ENGINE=( $engine )
  if [ -z "${NR_ENGINE[0]:-}" ]; then
    return 1
  fi
  return 0
}

nr_run_engine() {
  local stdin_file=$1 out=$2 err=$3 timeout pid i rc
  timeout=${OS_ENGINE_TIMEOUT:-120}
  : > "$out"
  : > "$err"
  "${NR_ENGINE[@]}" < "$stdin_file" > "$out" 2>"$err" &
  pid=$!
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$timeout" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  set +e
  wait "$pid"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 1
  return 0
}

nr_engine_json() {
  local stdin_file=$1 out err line n
  out=$(mktemp)
  err=$(mktemp)
  chmod 600 "$out" "$err"
  if ! nr_load_engine || ! nr_run_engine "$stdin_file" "$out" "$err"; then
    rm -f "$out" "$err"
    return 1
  fi
  n=$(grep -c '[^[:space:]]' "$out" || true)
  if [ "$n" != "1" ]; then
    rm -f "$out" "$err"
    return 1
  fi
  line=$(grep -v '^[[:space:]]*$' "$out" | head -n 1)
  if ! printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
    rm -f "$out" "$err"
    return 1
  fi
  if ! printf '%s' "$line" | jq -e '.ok == true' >/dev/null 2>&1; then
    rm -f "$out" "$err"
    return 1
  fi
  printf '%s\n' "$line"
  rm -f "$out" "$err"
}

nr_origin_name() {
  local url=$1
  url=${url%.git}
  url=${url%/}
  printf '%s\n' "${url##*/}"
}

nr_sync_base() {
  local repo=$1
  if [ "${OS_SKIP_FETCH:-}" = "1" ]; then
    printf '%s\n' "main"
    return 0
  fi
  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    printf '%s\n' "main"
    return 0
  fi
  if ! nr_git_net "$repo" fetch origin main >/dev/null 2>&1; then
    return 1
  fi
  if git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main; then
    printf '%s\n' "origin/main"
  else
    printf '%s\n' "main"
  fi
}

nr_saved_sha() {
  local rel=$1
  if [ ! -f "$NR_STATE" ]; then
    return 0
  fi
  jq -r --arg r "$rel" '.repos[$r] // ""' "$NR_STATE"
}

nr_save_sha() {
  local rel=$1 sha=$2 tmp
  tmp=$(mktemp)
  jq --arg r "$rel" --arg s "$sha" '.repos[$r]=$s' "$NR_STATE" > "$tmp"
  mv "$tmp" "$NR_STATE"
  chmod 600 "$NR_STATE"
}

nr_replace_repo_flags() {
  local rel=$1 array_file=$2 tmp
  tmp=$(mktemp)
  jq --arg r "$rel" --slurpfile add "$array_file" \
    '.flags = ([.flags[]? | select(.repo != $r)] + $add[0])' "$NR_STATE" > "$tmp"
  mv "$tmp" "$NR_STATE"
  chmod 600 "$NR_STATE"
}

nr_was_open() {
  local id=$1
  [ -f "$NR_STATE" ] || return 1
  jq -e --arg id "$id" --arg date "$NR_DATE" \
    'any(.flags[]?; .id == $id and .date < $date)' "$NR_STATE" >/dev/null
}

nr_file_author() {
  local repo=$1 path=$2 email name slug
  email=$(git -C "$repo" log -1 --format='%ae' -- "$path" 2>/dev/null || true)
  slug=$(nr_slug_by_email "$email" || true)
  if [ -z "$slug" ]; then
    name=$(git -C "$repo" log -1 --format='%an' -- "$path" 2>/dev/null || true)
    slug=$(nr_slug_by_name "$name" || true)
  fi
  printf '%s\n' "$slug"
}

nr_pick_bot() {
  local area=$1 f bot got
  if [ -n "${OS_BOT:-}" ]; then
    printf '%s\n' "$OS_BOT"
    return 0
  fi
  bot=""
  for f in "$NR_ROOT"/bots/*/BOT.md; do
    [ -f "$f" ] || continue
    got=$(nr_fm_get "$f" area | head -n 1 || true)
    if [ -n "$area" ] && [ "$area" != "company" ] && [ "$got" = "$area" ]; then
      basename "$(dirname "$f")"
      return 0
    fi
    if [ -z "$got" ] && [ -z "$bot" ]; then
      bot=$(basename "$(dirname "$f")")
    fi
  done
  printf '%s\n' "$bot"
}

nr_load_identity() {
  local admin bot page owner name
  admin=$(nr_admin_slug)
  NR_BOT=""
  NR_OWNER=$admin
  if nr_switch_on bots; then
    bot=$(nr_pick_bot "${1:-}")
    if [ -n "$bot" ] && [ -f "$NR_ROOT/bots/$bot/BOT.md" ]; then
      NR_BOT=$bot
      page="$NR_ROOT/bots/$bot/BOT.md"
      owner=$(nr_fm_get "$page" owner | head -n 1 || true)
      if [ -n "$owner" ]; then
        NR_OWNER=$owner
      fi
      name=$(nr_fm_get "$page" name | head -n 1 || true)
      if [ -z "$name" ]; then
        name=$bot
      fi
      NR_GIT_NAME=$name
      NR_GIT_EMAIL=$(printf '%s@%s.example' "$bot" "$NR_SLUG")
      return 0
    fi
  fi
  NR_GIT_NAME=$(nr_person_name "$admin")
  NR_GIT_EMAIL=$(printf '%s@%s.example' "$admin" "$NR_SLUG")
}

nr_commit_trailers() {
  local body
  body=$(printf 'Run-Id: %s' "$NR_RUN_ID")
  if [ -n "${NR_BOT}" ]; then
    body=$(printf '%s\nBot-Owner: %s' "$body" "$NR_OWNER")
  fi
  printf '%s\n' "$body"
}

nr_commit_wt() {
  local wt=$1 msg=$2
  if [ -z "$(git -C "$wt" status --porcelain)" ]; then
    return 0
  fi
  git -C "$wt" add -A
  git -C "$wt" -c user.name="$NR_GIT_NAME" -c user.email="$NR_GIT_EMAIL" \
    commit -q -m "$msg" -m "$(nr_commit_trailers)"
}

nr_git_https() {
  local repo=$1 host ask token user rc
  shift
  host="$NR_ROOT/skills/_host/host.sh"
  if [ ! -f "$host" ]; then
    return 1
  fi
  set +e
  if [ -n "${NR_BOT}" ]; then
    token=$(bash "$host" get-token --bot "$NR_BOT" 2>/dev/null)
  else
    token=$(bash "$host" get-token 2>/dev/null)
  fi
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    return 1
  fi
  token=$(printf '%s' "$token" | tr -d '\r\n')
  if [ -z "$token" ]; then
    return 1
  fi
  ask=$(mktemp)
  chmod 700 "$ask"
  cat > "$ask" << 'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${OS_GIT_USER}" ;;
  *) printf '%s\n' "${OS_GIT_TOKEN}" ;;
esac
EOF
  user=${NR_LOGIN:-git}
  if [ "$user" = "git" ] && [ -z "${OS_ARGV_SKIP_WHOAMI:-}" ]; then
    set +e
    user=$(bash "$host" whoami 2>/dev/null | jq -r '.login // "git"')
    set -e
    [ -n "$user" ] || user=git
  fi
  set +e
  OS_GIT_USER="$user" OS_GIT_TOKEN="$token" GIT_ASKPASS="$ask" GIT_TERMINAL_PROMPT=0 \
    git -C "$repo" -c credential.helper= -c http.connectTimeout=5 "$@"
  rc=$?
  set -e
  rm -f "$ask"
  unset OS_GIT_TOKEN
  token=""
  return "$rc"
}

nr_git_net() {
  local repo=$1 url
  shift
  url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  case "$url" in
    https://*|http://*) nr_git_https "$repo" "$@" ;;
    *) git -C "$repo" "$@" ;;
  esac
}

nr_push_https() {
  nr_git_https "$1" push -u origin "$2"
}

nr_commit_slug() {
  local repo=$1 sha=$2 email name slug
  email=$(git -C "$repo" log -1 --format='%ae' "$sha" 2>/dev/null || true)
  slug=$(nr_slug_by_email "$email" || true)
  if [ -z "$slug" ]; then
    name=$(git -C "$repo" log -1 --format='%an' "$sha" 2>/dev/null || true)
    slug=$(nr_slug_by_name "$name" || true)
  fi
  if [ -z "$slug" ]; then
    printf '%s\n' "-"
  else
    printf '%s\n' "$slug"
  fi
}

nr_push_branch() {
  local wt=$1 branch=$2 url
  if [ "${OS_SKIP_PUSH:-}" = "1" ]; then
    return 0
  fi
  url=$(git -C "$wt" remote get-url origin 2>/dev/null || true)
  if [ -z "$url" ]; then
    return 1
  fi
  case "$url" in
    https://*|http://*) nr_push_https "$wt" "$branch" ;;
    *) git -C "$wt" push -u origin "$branch" ;;
  esac
}

nr_host() {
  bash "$NR_ROOT/skills/_host/host.sh" "$@"
}

nr_open_and_merge() {
  local name=$1 branch=$2 body out number
  if [ "${OS_SKIP_PUSH:-}" = "1" ]; then
    return 0
  fi
  body=$(mktemp)
  chmod 600 "$body"
  printf '%s\n' "Nightly review ${NR_DATE}." > "$body"
  set +e
  out=$(nr_host open-pr "$name" --head "$branch" --base main \
    --title "Review ${NR_DATE}" --body-file "$body" 2>/dev/null)
  local rc=$?
  set -e
  rm -f "$body"
  if [ "$rc" -ne 0 ]; then
    return 1
  fi
  number=$(printf '%s' "$out" | jq -r '.number // empty')
  if [ -z "$number" ]; then
    return 1
  fi
  printf 'pr %s %s\n' "$name" "$number"
  nr_host auto-merge "$name" "$number" >/dev/null
}

nr_publish() {
  local wt=$1 rel=$2 msg=$3 name url branch
  branch="review/${NR_DATE}"
  nr_commit_wt "$wt" "$msg" || return 1
  if [ "${OS_SKIP_PUSH:-}" = "1" ]; then
    return 0
  fi
  url=$(git -C "$wt" remote get-url origin 2>/dev/null || true)
  name=$(nr_origin_name "$url")
  if [ -z "$name" ]; then
    return 1
  fi
  nr_push_branch "$wt" "$branch" || return 1
  nr_open_and_merge "$name" "$branch" || return 1
  return 0
}

nr_worktree_open() {
  local repo=$1 base=$2 branch=$3 wt
  wt=$(mktemp -d)
  git -C "$repo" worktree add --detach "$wt" "$base" >/dev/null 2>&1
  if git -C "$repo" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "$wt" checkout -q "$branch"
    if ! git -C "$wt" merge -q --no-edit "$base"; then
      git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
      return 1
    fi
  else
    git -C "$wt" checkout -q -b "$branch"
  fi
  printf '%s\n' "$wt"
}

nr_worktree_close() {
  local repo=$1 wt=$2
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
}

nr_prepare() {
  local level slug
  export OS_PROFILE="$NR_ROOT/company-profile.md"
  level=$(nr_profile level | head -n 1 || true)
  if [ "$level" = "solo" ]; then
    printf '%s\n' "skipped: solo"
    exit 0
  fi
  if [ "$level" != "team" ] && [ "$level" != "app" ]; then
    printf '%s\n' "level is not team or app" >&2
    exit 2
  fi
  slug=$(nr_profile company_slug | head -n 1 || true)
  if [ -z "$slug" ]; then
    printf '%s\n' "company slug is missing" >&2
    exit 2
  fi
  NR_SLUG=$slug
  NR_STATE_DIR=$(nr_state_dir)
  mkdir -p "$NR_STATE_DIR/digests"
  chmod 700 "$NR_STATE_DIR" "$NR_STATE_DIR/digests"
  NR_STATE="$NR_STATE_DIR/review.json"
  NR_LOG="$NR_STATE_DIR/review.log"
  if [ ! -f "$NR_STATE" ]; then
    printf '%s\n' '{"repos":{},"flags":[]}' > "$NR_STATE"
    chmod 600 "$NR_STATE"
  fi
  if [ -z "${NR_DATE:-}" ]; then
    NR_DATE=$(nr_today)
  fi
  if [ -z "${NR_RUN_ID:-}" ]; then
    if [ -n "${OS_RUN_ID:-}" ]; then
      NR_RUN_ID=$OS_RUN_ID
    else
      NR_RUN_ID=$(printf 'review-%s-%s' "$NR_DATE" "$(nr_rand)")
    fi
  fi
  # Used by the scripts that source this file.
  # shellcheck disable=SC2034
  NR_FAILED=0
  NR_LOGGED_FAIL=0
  nr_load_identity
}

nr_cap() {
  if [ -n "${OS_REVIEW_CAP:-}" ]; then
    printf '%s\n' "$OS_REVIEW_CAP"
  else
    printf '%s\n' "20"
  fi
}

nr_drop_ranked() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
      printf '\n'
      continue
    fi
    if nr_ranking_line "$line" || nr_private_line "$line"; then
      continue
    fi
    printf '%s\n' "$line"
  done
}
