#!/bin/bash
# B82 on a Windows runner, in Git Bash: join stops when git cannot write in its home
# folder, and says so in one line. Each check prints one PASS, FAIL or SKIP line.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
lib="$root/template/skills/add-teammate/lib.sh"
base=$(mktemp -d)
ro="$base/ro"
rw="$base/rw"
# The runner's own temp folder is on another drive (D:) than the system drive.
if [ -n "${RUNNER_TEMP:-}" ]; then
  rw="$(cygpath -u "$RUNNER_TEMP")/b82-rw-$$"
fi
mkdir -p "$ro" "$rw"
user=${USERNAME:-$(whoami)}
# shellcheck disable=SC2329  # run by the EXIT trap
cleanup() {
  MSYS2_ARG_CONV_EXCL='*' icacls "$(cygpath -w "$ro")" /remove:d "$user" > /dev/null 2>&1 || true
  rm -rf "$base" "$rw"
}
trap cleanup EXIT
fail=0

stop_line() {
  printf 'home: git uses %s as your home folder and cannot write there; set the user environment variable HOME to %%USERPROFILE%% (Settings, Environment Variables, User variables), open a new terminal, then run join again' "$1"
}

# A folder this user cannot write in: deny "write" (add file, write data) on it.
MSYS2_ARG_CONV_EXCL='*' icacls "$(cygpath -w "$ro")" /deny "${user}:(OI)(CI)(W)" > /dev/null
# git.exe, a native program, honours the deny (a Git Bash write may not: backup intent).
if git config --file "$ro/probe" a.b 1 > /dev/null 2>&1; then
  printf '%s\n' "B82 FAIL setup: git can still write in the denied folder"
  exit 1
fi

# The check itself.
set +e
out=$(unset GIT_CONFIG_GLOBAL; HOME="$ro" bash -c '. "$1"; os_home_check' _ "$lib" 2>&1)
rc=$?
set -e
want=$(stop_line "$(cygpath -w "$ro")")
if [ "$rc" -eq 2 ] && [ "$out" = "$want" ]; then
  printf '%s\n' "B82 PASS check: $out"
else
  printf 'B82 FAIL check: exit %s: %s\n' "$rc" "$out"
  fail=1
fi

# join.sh stops there, before it reads the clone.
printf '%s\n' "me=ada" > "$base/answers"
set +e
out=$(unset GIT_CONFIG_GLOBAL; HOME="$ro" bash "$root/template/skills/add-teammate/join.sh" --answers "$base/answers" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 2 ] && [ "$out" = "$want" ]; then
  printf '%s\n' "B82 PASS join stops with the home line"
else
  printf 'B82 FAIL join: exit %s: %s\n' "$rc" "$out"
  fail=1
fi

# A writable home on the system drive: no line.
sys_home=$(cygpath -u "$USERPROFILE")
set +e
out=$(unset GIT_CONFIG_GLOBAL; HOME="$sys_home" bash -c '. "$1"; os_home_check' _ "$lib" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  printf '%s\n' "B82 PASS writable home on the system drive: no line"
else
  printf 'B82 FAIL writable home: exit %s: %s\n' "$rc" "$out"
  fail=1
fi

# A writable home on another drive: one warning, and it goes on.
rw_win=$(cygpath -w "$rw")
sys=${SYSTEMDRIVE:-C:}
case "$rw_win" in
  "${sys%%:*}":*|"$(printf '%s' "${sys%%:*}" | tr '[:upper:]' '[:lower:]')":*)
    printf '%s\n' "B82 SKIP other drive: the runner temp folder is on the system drive"
    ;;
  *)
    set +e
    out=$(unset GIT_CONFIG_GLOBAL; HOME="$rw" bash -c '. "$1"; os_home_check' _ "$lib" 2>&1)
    rc=$?
    set -e
    case "$out" in
      "home: git uses ${rw_win} as your home folder, not a folder on "*)
        if [ "$rc" -eq 0 ]; then
          printf '%s\n' "B82 PASS other drive: $out"
        else
          printf 'B82 FAIL other drive: exit %s\n' "$rc"
          fail=1
        fi
        ;;
      *)
        printf 'B82 FAIL other drive: exit %s: %s\n' "$rc" "$out"
        fail=1
        ;;
    esac
    ;;
esac

exit "$fail"
