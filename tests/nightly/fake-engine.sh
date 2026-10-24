#!/bin/bash
# Deterministic engine for nightly tests. Keys off markers in stdin.
set -euo pipefail

input=$(cat)

if printf '%s' "$input" | grep -q 'kind: fold'; then
  printf '%s\n' '{"ok":true,"summary":"Folded the old logs."}'
  exit 0
fi

if printf '%s' "$input" | grep -q 'kind: report'; then
  jq -nc '{
    ok: true,
    people: [
      {slug: "mia", actions: ["Filed the widget note.", "leaderboard"], results: ["The note is on main."]}
    ]
  }'
  exit 0
fi

findings='[]'
if printf '%s' "$input" | grep -q 'CLEAR-ERROR'; then
  findings=$(printf '%s' "$findings" | jq -c '. + [{
    kind: "clear-error",
    path: "notes/widget.md",
    summary: "Broken link.",
    author: "mia",
    fix: {action: "replace", old: "[[Ada]]", new: "[[Ada Admin]]"}
  }]')
fi
if printf '%s' "$input" | grep -q 'JUDGMENT-CALL'; then
  findings=$(printf '%s' "$findings" | jq -c '. + [{
    kind: "judgment",
    path: "notes/widget.md",
    summary: "Confirm the price.",
    author: "mia"
  }]')
fi
if printf '%s' "$input" | grep -q 'RULES-BROKEN'; then
  findings=$(printf '%s' "$findings" | jq -c '. + [{
    kind: "clear-error",
    path: "AGENTS.md",
    summary: "Do not auto-edit a rules file.",
    author: "mia",
    fix: {action: "replace", old: "RULES-BROKEN", new: "FIXED"}
  }]')
fi
if printf '%s' "$input" | grep -q 'POSSIBLE-LEAK'; then
  findings=$(printf '%s' "$findings" | jq -c '. + [{
    kind: "clear-error",
    path: "notes/leak.md",
    summary: "Possible leak: a token is in the note.",
    author: "mia",
    fix: {action: "replace", old: "SECRET-LINE", new: "gone"}
  }]')
fi
if printf '%s' "$input" | grep -q 'MANY-FLAGS'; then
  findings=$(jq -nc '[
    {kind:"judgment", path:"notes/a.md", summary:"Flag one.", author:"mia"},
    {kind:"judgment", path:"notes/b.md", summary:"Flag two.", author:"mia"},
    {kind:"judgment", path:"notes/c.md", summary:"Flag three.", author:"mia"},
    {kind:"judgment", path:"notes/d.md", summary:"Flag four.", author:"mia"}
  ]')
fi

jq -nc --argjson findings "$findings" '{ok: true, findings: $findings}'
