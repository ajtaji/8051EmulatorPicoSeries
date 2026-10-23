#!/usr/bin/env bash
# Upload and capture on the shared Pico W, holding the board lease only while
# the compiler is on the board. The lease is taken from Bash: the PowerShell
# tool's sandbox cannot see lease files other sessions create.
#   tools/board.sh <source> <output.uf2> <port> <seconds> [required verdict...]
set -u
LEASE_DIR=/c/PMFBuild/board-leases
LEASE=$LEASE_DIR/COM7.lease
ROOT=$(cd "$(dirname "$0")/.." && pwd)
src=$1; out=$2; port=$3; secs=$4; shift 4
req=""
for r in "$@"; do req="$req,'${r//\'/\'\'}'"; done
req=${req#,}
# Compile first, off the board, so a compile error never holds the lease.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/tools/build.ps1")" -Source "$src" -Output "$out" || exit 1
mkdir -p $LEASE_DIR
set -o noclobber
until echo "cg-8051 $(date -Iseconds) upload+capture $secs s" > $LEASE 2>/dev/null; do
  age=$(( $(date +%s) - $(stat -c %Y $LEASE 2>/dev/null || date +%s) ))
  [ $((age % 60)) -lt 3 ] && echo "lease held ($age s): $(cat $LEASE 2>/dev/null)"
  sleep 3
done
set +o noclobber
trap 'rm -f $LEASE' EXIT
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$(cygpath -w "$ROOT/tools/build.ps1")' -Source '$src' -Output '$out' -Port $port -Seconds $secs ${req:+-Require @($req)}"
rc=$?
rm -f $LEASE
trap - EXIT
exit $rc
