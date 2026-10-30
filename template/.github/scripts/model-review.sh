#!/bin/bash
# Ask a model to review one pull request.
# The 1610 review App is not in v1. There is no code path for it.
#
# The vendor, model and kind come from .github/review.conf.
# vendor=anthropic|openai|xai, model= (blank uses the vendor default),
# kind=second-vendor|same-vendor. OS_REVIEW_VENDOR, OS_REVIEW_MODEL and
# OS_REVIEW_KIND override the file. A missing file or a bad vendor fails
# the check. kind=same-vendor adds "weaker review: same vendor".
# No key: fail with a plain message. Do not call a model.
#
# Test only: OS_REVIEW_FAKE is a path set in the runner environment.
# This script does not read a verdict file from the repository.
# The fake file lines are "<marker> PASS" or "<marker> FAIL".
# The first marker found in the diff wins. A marker of * is the default.
# The review key is never printed and never placed in a command argument.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/lib.sh"
trap ci_cleanup EXIT

usage() {
  cat << 'EOF'
usage: model-review.sh --rules FILE --title-file FILE --body-file FILE --diff-file FILE --out FILE

Review one pull request. Reads .github/review.conf for vendor, model and kind.
OS_REVIEW_VENDOR, OS_REVIEW_MODEL and OS_REVIEW_KIND override that file.
OS_REVIEW_KEY is the review key. OS_REVIEW_FAKE is test-only.
Writes the review text to --out. Exits 0 on VERDICT: PASS, 1 on failure.
Never prints the review key.
EOF
}

rules=""
title_file=""
body_file=""
diff_file=""
out_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --rules)
      rules=${2:-}
      shift 2
      ;;
    --title-file)
      title_file=${2:-}
      shift 2
      ;;
    --body-file)
      body_file=${2:-}
      shift 2
      ;;
    --diff-file)
      diff_file=${2:-}
      shift 2
      ;;
    --out)
      out_file=${2:-}
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$rules" ] || [ -z "$title_file" ] || [ -z "$body_file" ] || [ -z "$diff_file" ] || [ -z "$out_file" ]; then
  usage >&2
  exit 1
fi

# The vendor's error.message, one line, at most 300 characters. Never the key:
# drop the key itself and any masked key the vendor echoes back (a word with three or more stars).
vendor_error() {
  local file=$1 msg
  [ -s "$file" ] || return 0
  msg=$(jq -r '(if (.error | type) == "object" then .error.message else .error end) // .message // empty
    | if type == "string" then . else tojson end' \
    "$file" 2>/dev/null || true)
  [ -n "$msg" ] || return 0
  msg=$(printf '%s' "$msg" | tr '\r\n\t' '   ')
  if [ -n "${OS_REVIEW_KEY:-}" ]; then
    msg=${msg//"$OS_REVIEW_KEY"/[key]}
  fi
  printf '%s' "$msg" | sed -E 's/[A-Za-z0-9_.-]*[*]{3,}[A-Za-z0-9_.-]*/[key]/g' | cut -c 1-300
}

fail() {
  printf '%s\n' "$1" >&2
  if [ -n "${out_file:-}" ]; then
    printf '%s\n' "$1" > "$out_file"
  fi
  exit 1
}

write_out() {
  local text=$1
  : > "$out_file"
  chmod 600 "$out_file"
  if [ "${OS_REVIEW_KIND:-}" = "same-vendor" ]; then
    printf '%s\n\n' "weaker review: same vendor" >> "$out_file"
  fi
  printf '%s\n' "$text" >> "$out_file"
}

last_verdict() {
  local text=$1 line
  line=$(printf '%s\n' "$text" | sed '/^[[:space:]]*$/d' | tail -n 1)
  line=$(ci_trim "$line")
  printf '%s\n' "$line"
}

fake_review() {
  local path=$1 line marker rest verdict default text
  if [ ! -f "$path" ]; then
    fail "model review failed: the fake reviewer file is missing"
  fi
  verdict=""
  default=""
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(ci_trim "$line")
    case "$line" in
      ""|\#*) continue ;;
    esac
    marker=${line%%[[:space:]]*}
    rest=$(ci_trim "${line#"$marker"}")
    case "$rest" in
      PASS|FAIL) ;;
      *) fail "model review failed: the fake reviewer file is not valid" ;;
    esac
    if [ "$marker" = "*" ]; then
      if [ -z "$default" ]; then
        default=$rest
      fi
      continue
    fi
    if [ -z "$verdict" ] && grep -q -F -- "$marker" "$diff_file"; then
      verdict=$rest
    fi
  done < "$path"
  if [ -z "$verdict" ]; then
    verdict=$default
  fi
  if [ "$verdict" != "PASS" ] && [ "$verdict" != "FAIL" ]; then
    fail "model review failed: the fake reviewer has no verdict"
  fi
  if [ "$verdict" = "FAIL" ]; then
    text="SUMMARY: Test reviewer. A marker in the diff failed the review.
FINDING: 1 diff:1 The test marker failed the review.
VERDICT: FAIL"
  else
    text="SUMMARY: Test reviewer. No finding.
VERDICT: PASS"
  fi
  write_out "$text"
  if [ "$verdict" = "FAIL" ]; then
    exit 1
  fi
  exit 0
}

vendor_url() {
  case "$1" in
    anthropic) printf '%s\n' "https://api.anthropic.com/v1/messages" ;;
    openai) printf '%s\n' "https://api.openai.com/v1/chat/completions" ;;
    xai) printf '%s\n' "https://api.x.ai/v1/chat/completions" ;;
    *) return 1 ;;
  esac
}

default_model() {
  case "$1" in
    anthropic) printf '%s\n' "claude-haiku-4-5" ;;
    openai) printf '%s\n' "gpt-4o-mini" ;;
    xai) printf '%s\n' "grok-4" ;;
    *) return 1 ;;
  esac
}

load_review_settings() {
  local file=".github/review.conf"
  if [ -n "${OS_CHECK_TOOLS:-}" ]; then
    file="${OS_CHECK_TOOLS}/.github/review.conf"
  fi
  local line key val file_vendor="" file_model="" file_kind="" saw_file=0
  if [ -f "$file" ]; then
    saw_file=1
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(ci_trim "$line")
      case "$line" in
        ""|\#*) continue ;;
      esac
      case "$line" in
        *=*) ;;
        *) fail "model review failed: .github/review.conf is not valid" ;;
      esac
      key=$(ci_trim "${line%%=*}")
      val=$(ci_trim "${line#*=}")
      case "$key" in
        vendor) file_vendor=$val ;;
        model) file_model=$val ;;
        kind) file_kind=$val ;;
        *) fail "model review failed: .github/review.conf is not valid" ;;
      esac
    done < "$file"
  fi
  if [ -n "${OS_REVIEW_VENDOR:-}" ]; then
    vendor=$(ci_lower "$OS_REVIEW_VENDOR")
  else
    vendor=$(ci_lower "$file_vendor")
  fi
  if [ -n "${OS_REVIEW_MODEL:-}" ]; then
    model=$OS_REVIEW_MODEL
  else
    model=$file_model
  fi
  if [ -n "${OS_REVIEW_KIND:-}" ]; then
    file_kind=$OS_REVIEW_KIND
  fi
  case "$file_kind" in
    ""|second-vendor) file_kind=second-vendor ;;
    same-vendor) ;;
    *) fail "model review failed: .github/review.conf is not valid" ;;
  esac
  if [ "$file_kind" = "same-vendor" ]; then
    OS_REVIEW_KIND=same-vendor
  else
    OS_REVIEW_KIND=""
  fi
  export OS_REVIEW_KIND
  if [ -n "${OS_REVIEW_FAKE:-}" ]; then
    return 0
  fi
  if [ "$saw_file" -eq 0 ] && [ -z "${OS_REVIEW_VENDOR:-}" ]; then
    fail "model review failed: .github/review.conf is missing"
  fi
  case "$vendor" in
    anthropic|openai|xai) ;;
    *) fail "model review failed: vendor must be anthropic, openai, or xai" ;;
  esac
}

load_review_settings

if [ -n "${OS_REVIEW_FAKE:-}" ]; then
  fake_review "$OS_REVIEW_FAKE"
fi

# A pasted key can carry spaces or a line break. Either breaks the curl config.
# printf is a shell builtin, so the key is never a command argument.
OS_REVIEW_KEY=$(printf '%s' "${OS_REVIEW_KEY:-}" | tr -d ' \t\r\n')
if [ -z "${OS_REVIEW_KEY:-}" ]; then
  fail "no review key: every pull request fails the model review until you add one"
fi

if [ ! -f "$rules" ]; then
  fail "model review failed: review-rules.md is missing"
fi

if [ -z "${model:-}" ]; then
  model=$(default_model "$vendor")
fi

size=$(wc -c < "$diff_file" | tr -d ' ')
if [ "$size" -gt 100000 ]; then
  fail "model review failed: diff too large (${size} bytes, limit 100000); split the pull request or use /override <reason>"
fi
diff_cut=$diff_file

prompt=$(ci_mktemp)
{
  cat "$rules"
  printf '\n\nPull request title:\n'
  cat "$title_file"
  printf '\n\nPull request body:\n'
  cat "$body_file"
  printf '\n\nPull request diff:\n'
  cat "$diff_cut"
} > "$prompt"

json=$(ci_mktemp)
case "$vendor" in
  anthropic)
    jq -n --rawfile text "$prompt" --arg model "$model" \
      '{model:$model, max_tokens:1024, messages:[{role:"user", content:$text}]}' > "$json"
    ;;
  *)
    jq -n --rawfile text "$prompt" --arg model "$model" \
      '{model:$model, messages:[{role:"user", content:$text}]}' > "$json"
    ;;
esac

resp=$(ci_mktemp)
err=$(ci_mktemp)
cfg=$(ci_mktemp)
hdr=$(ci_mktemp)
url=$(vendor_url "$vendor")
{
  if [ "$vendor" = "anthropic" ]; then
    printf '%s\n' "header = \"x-api-key: ${OS_REVIEW_KEY}\""
    printf '%s\n' 'header = "anthropic-version: 2023-06-01"'
  else
    printf '%s\n' "header = \"Authorization: Bearer ${OS_REVIEW_KEY}\""
  fi
  printf '%s\n' 'header = "content-type: application/json"'
  printf '%s\n' "url = \"${url}\""
  printf '%s\n' 'request = "POST"'
  printf '%s\n' "data-binary = \"@${json}\""
  printf '%s\n' "output = \"${resp}\""
  printf '%s\n' "dump-header = \"${hdr}\""
  printf '%s\n' 'silent'
  printf '%s\n' 'show-error'
  printf '%s\n' 'connect-timeout = 10'
  printf '%s\n' 'max-time = 90'
  printf '%s\n' 'write-out = "%{http_code}"'
} > "$cfg"

# Seconds before the next try: the vendor's Retry-After (at most 60), else 20, then 40.
retry_wait() {
  local after
  after=$(tr -d '\r' < "$hdr" | awk -F': *' 'tolower($1) == "retry-after" { v = $2 } END { print v }')
  case "$after" in
    ""|*[!0-9]*) after=$(($1 * 20)) ;;
  esac
  [ "$after" -le 60 ] || after=60
  printf '%s\n' "$after"
}

# A busy vendor (HTTP 429 or 5xx) gets at most 3 tries, about 2 minutes in all.
try=1
while :; do
  : > "$hdr"
  set +e
  http=$(curl --config "$cfg" 2>"$err")
  curl_rc=$?
  set -e
  case "$curl_rc:$http" in
    0:429|0:5[0-9][0-9]) ;;
    *) break ;;
  esac
  if [ "$try" -ge 3 ]; then
    fail "the review service is busy: re-run the checks later"
  fi
  wait=$(retry_wait "$try")
  printf 'model review: the review service is busy (HTTP %s). Trying again in %s seconds.\n' "$http" "$wait" >&2
  sleep "$wait"
  try=$((try + 1))
done
if [ "$curl_rc" -eq 28 ]; then
  fail "model review failed: the review API timed out"
fi
if [ "$curl_rc" -ne 0 ] || [ -z "$http" ] || [ "$http" = "000" ]; then
  fail "model review failed: could not reach the review API (curl exit ${curl_rc})"
fi
case "$http" in
  200) ;;
  *)
    reason=$(vendor_error "$resp")
    if [ -n "$reason" ]; then
      fail "model review failed: the review API returned HTTP ${http}: ${reason}"
    fi
    fail "model review failed: the review API returned HTTP ${http}"
    ;;
esac

case "$vendor" in
  anthropic) text=$(jq -r '.content[0].text // empty' "$resp") ;;
  *) text=$(jq -r '.choices[0].message.content // empty' "$resp") ;;
esac
if [ -z "$text" ]; then
  fail "model review failed: no verdict"
fi
# A finding fails the review. Keep the review's own text in the comment and the job log,
# so people can see what it found (B36).
if printf '%s\n' "$text" | grep -q '^FINDING:'; then
  write_out "$text"
  printf '\n%s\n' "model review failed: the review reported a finding" >> "$out_file"
  printf '%s\n' "model review failed: the review reported a finding" >&2
  exit 1
fi
verdict=$(last_verdict "$text")
case "$verdict" in
  "VERDICT: PASS"|"VERDICT: FAIL") ;;
  *) fail "model review failed: no verdict" ;;
esac
text_file=$(ci_mktemp)
printf '%s\n' "$text" > "$text_file"
after=0
while IFS= read -r line; do
  line=$(ci_trim "$line")
  if [ "$after" -eq 1 ] && [ -n "$line" ]; then
    fail "model review failed: text after the verdict"
  fi
  case "$line" in
    "VERDICT: PASS"|"VERDICT: FAIL") after=1 ;;
  esac
done < "$text_file"
write_out "$text"
if [ "$verdict" = "VERDICT: FAIL" ]; then
  exit 1
fi
exit 0
