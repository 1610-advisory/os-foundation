"""#69: the checks-on-main lift never lets a queued auto-merge pull request merge.

At team level, upgrade --refresh lifts protection on main for one push. While it is off,
the host merges an open pull request with auto-merge on, even with failing checks. The
fake host here does just that: at unprotect, each pull request with auto-merge still on
merges. The refresh must turn auto-merge off before the lift and back on after protect.
"""
from __future__ import annotations

import json
import unittest

import test_refresh
from test_refresh import run, TEMPLATE


# A host with state: pull requests in prs.json, and what merged in merged.log.
FAKE_HOST = r"""#!/bin/bash
S=STATE
printf '%s\n' "$*" >> "$S/calls.log"
prs() { cat "$S/prs.json"; }
set_auto() { jq --argjson n "$1" --argjson v "$2" '[.[] | if .number == $n then .auto_merge = $v else . end]' "$S/prs.json" > "$S/prs.tmp" && mv "$S/prs.tmp" "$S/prs.json"; }
case "$1" in
  whoami) printf '%s\n' '{"login":"acme-admin"}' ;;
  get-token) printf '%s\n' local-token ;;
  open-pr) printf '%s\n' '{"number":7,"url":"http://example.test/7"}' ;;
  open-prs)
    [ ! -f "$S/list-fails" ] || exit 3
    # list-null: a host whose list cannot say (Forgejo).
    if [ -f "$S/list-null" ]; then am=null; else am=.auto_merge; fi
    prs | jq -c --arg repo "$2" "{prs: [.[] | select(.repo == \$repo and .merged != true) | {number, head, base, auto_merge:($am), body:\"\"}]}"
    ;;
  auto-merge-off)
    [ ! -f "$S/off-fails" ] || exit 3
    was=$(prs | jq -r --argjson n "$3" '.[] | select(.number == $n) | if .auto_merge then "on" else "off" end')
    set_auto "$3" false
    printf '{"ok":true,"auto_merge":"off","was":"%s"}\n' "${was:-off}"
    ;;
  auto-merge)
    if prs | jq -e --argjson n "$3" 'any(.[]; .number == $n)' >/dev/null; then set_auto "$3" true; fi
    printf '%s\n' '{"ok":true}'
    ;;
  unprotect)
    # The lift: every pull request into main of this repo with auto-merge on merges now,
    # failing checks or not. Then, if asked, main moves (another merge) during the push.
    jq --arg repo "$2" '[.[] | if .repo == $repo and .base == "main" and .auto_merge and .merged != true then .merged = true else . end]' \
      "$S/prs.json" > "$S/prs.tmp" && mv "$S/prs.tmp" "$S/prs.json"
    if [ -f "$S/move-main" ]; then
      rm -f "$S/move-main"
      b=$(cat "$S/bare")
      tree=$(git --git-dir="$b" rev-parse 'main^{tree}')
      c=$(git --git-dir="$b" commit-tree "$tree" -p main -m "moved during the lift")
      git --git-dir="$b" update-ref refs/heads/main "$c"
      printf '%s\n' "$c" > "$S/moved"
    fi
    printf '%s\n' '{"ok":true}'
    ;;
  protect)
    [ ! -f "$S/protect-fails" ] || exit 3
    printf '%s\n' '{"ok":true}'
    ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
"""

QUEUED = {"repo": "acme-os", "number": 12, "head": "review/2026-11-24", "base": "main",
          "auto_merge": True, "checks": "failure"}


class LiftAutoMergeTests(unittest.TestCase):
    def setUp(self):
        test_refresh.RefreshTests.setUp(self)
        self.state = self.tmp / "state"
        self.state.mkdir()
        (self.state / "bare").write_text(str(self.bare))
        self.set_prs([QUEUED, dict(QUEUED, number=13, auto_merge=False, head="sync/ada"),
                      dict(QUEUED, number=14, base="other", head="x")])
        host = self.tmp / "host" / "host.sh"
        host.write_text(FAKE_HOST.replace("STATE", str(self.state)))
        host.chmod(0o755)

    tearDown = test_refresh.RefreshTests.tearDown
    refresh = test_refresh.RefreshTests.refresh

    def set_prs(self, prs):
        (self.state / "prs.json").write_text(json.dumps(prs))

    def prs(self):
        return {p["number"]: p for p in json.loads((self.state / "prs.json").read_text())}

    def calls(self):
        return (self.state / "calls.log").read_text().splitlines()

    def flag(self, name):
        (self.state / name).write_text("")

    def test_queued_auto_merge_with_failing_checks_does_not_merge_across_a_refresh(self):
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, out)
        pr = self.prs()[12]
        self.assertNotEqual(pr.get("merged"), True, out)
        # Auto-merge is back on once protection is back.
        self.assertTrue(pr["auto_merge"], out)
        self.assertIn("auto-merge: paused acme-os#12", result.stdout)
        self.assertIn("auto-merge: restored acme-os#12", result.stdout)
        # Only the one that had it on: not #13 (off), not #14 (another base).
        self.assertNotIn("acme-os#13", out)
        self.assertNotIn("acme-os#14", out)
        self.assertFalse(self.prs()[13]["auto_merge"])
        calls = self.calls()
        order = [calls.index(c) for c in ("auto-merge-off acme-os 12", "unprotect acme-os",
                                          "protect acme-os --code-owners --approvals 0",
                                          "auto-merge acme-os 12")]
        self.assertEqual(order, sorted(order), calls)
        lines = result.stdout.splitlines()
        self.assertLess(lines.index("auto-merge: paused acme-os#12"),
                        next(i for i, l in enumerate(lines) if l.startswith("checks-on-main: acme-os")))
        self.assertLess(lines.index("protected: acme-os"), lines.index("auto-merge: restored acme-os#12"))

    def test_without_the_pause_the_fake_host_merges_it(self):
        # The fake is a fair model: a lift with auto-merge on merges the pull request.
        run([str(self.tmp / "host" / "host.sh"), "unprotect", "acme-os"], env=self.env, check=True)
        self.assertTrue(self.prs()[12].get("merged"))

    def test_dry_run_lists_what_it_would_pause_and_changes_nothing(self):
        result = self.refresh("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("auto-merge: would pause acme-os#12", result.stdout)
        self.assertNotIn("acme-os#13", result.stdout)
        calls = self.calls()
        self.assertFalse([c for c in calls if c.startswith(("auto-merge", "unprotect", "protect"))], calls)
        self.assertTrue(self.prs()[12]["auto_merge"])

    def test_dry_run_on_a_host_that_cannot_say_lists_each_with_a_note(self):
        self.flag("list-null")
        result = self.refresh("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("auto-merge: would pause acme-os#12 if a merge is scheduled on it", result.stdout)
        self.assertIn("auto-merge: would pause acme-os#13 if a merge is scheduled on it", result.stdout)

    def test_unknown_state_pauses_only_what_the_cancel_says_was_on(self):
        # Forgejo: the list says null for each; auto-merge-off's "was" decides.
        self.flag("list-null")
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, out)
        self.assertIn("auto-merge-off acme-os 13", self.calls())
        self.assertIn("auto-merge: paused acme-os#12", result.stdout)
        self.assertIn("auto-merge: restored acme-os#12", result.stdout)
        self.assertNotIn("acme-os#13", out)
        self.assertNotIn("auto-merge acme-os 13", self.calls())
        self.assertFalse(self.prs()[13]["auto_merge"])
        self.assertNotEqual(self.prs()[12].get("merged"), True)

    def test_protect_fails_auto_merge_stays_off_and_it_says_so(self):
        self.flag("protect-fails")
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, out)
        self.assertIn("PROTECTION IS OFF on acme-os", out)
        self.assertIn("auto-merge: not restored acme-os#12, because protection on acme-os is off", out)
        self.assertNotIn("auto-merge: restored", out)
        self.assertNotIn("auto-merge acme-os 12", self.calls())
        self.assertFalse(self.prs()[12]["auto_merge"])
        self.assertNotEqual(self.prs()[12].get("merged"), True)

    def test_cannot_turn_auto_merge_off_stops_before_the_lift(self):
        self.flag("off-fails")
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, out)
        self.assertIn("stopped before lifting protection on acme-os: could not turn auto-merge off on acme-os#12", out)
        self.assertNotIn("unprotect acme-os", self.calls())
        self.assertNotEqual(self.prs()[12].get("merged"), True)

    def test_cannot_list_stops_before_the_lift(self):
        self.flag("list-fails")
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, out)
        self.assertIn("stopped before lifting protection on acme-os: could not list its open pull requests", out)
        self.assertNotIn("unprotect acme-os", self.calls())

    def test_main_moves_during_the_lift_the_push_is_built_again_once(self):
        # The pilot's second failure: a merge moved main, and the push was not a fast-forward.
        self.flag("move-main")
        result = self.refresh()
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, out)
        self.assertIn("checks-on-main: acme-os: main moved during the push. Building again on the new main.", out)
        moved = (self.state / "moved").read_text().strip()
        # The new main holds the moved commit and this release's check tools.
        self.assertEqual(run(["git", "--git-dir", str(self.bare), "merge-base", "--is-ancestor", moved, "main"],
                             env=self.env).returncode, 0)
        want = run(["git", "hash-object", str(TEMPLATE / ".github/scripts/stock-current.txt")],
                   env=self.env).stdout.strip()
        self.assertEqual(self.host_blob("main", ".github/scripts/stock-current.txt"), want)
        self.assertIn("protected: acme-os", result.stdout)
        self.assertIn("auto-merge: restored acme-os#12", result.stdout)

    host_blob = test_refresh.RefreshTests.host_blob


if __name__ == "__main__":
    unittest.main()
