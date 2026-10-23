#!/usr/bin/env bash
# Several uploads and captures on the shared Pico W under ONE lease. Every
# image is compiled first, off the board; the lease is held only while the
# compiler uploads and captures, and is deleted at once afterwards.
#   tools/board_batch.sh <port> <source>:<output.uf2>:<seconds> ...
set -u
LEASE_DIR=/c/PMFBuild/board-leases
LEASE=$LEASE_DIR/COM7.lease
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$(cygpath -w "$ROOT/tools/build.ps1")
port=$1; shift
total=0
for job in "$@"; do
  IFS=: read -r src out secs <<< "$job"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BUILD" -Source "$src" -Output "$out" > /dev/null || { echo "compile failed: $src"; exit 1; }
  total=$((total + secs + 40))
done
mkdir -p $LEASE_DIR
set -o noclobber
until echo "cg-8051 $(date -Iseconds) $# upload+capture jobs, about $total s" > $LEASE 2>/dev/null; do
  sleep 3
done
set +o noclobber
trap 'rm -f $LEASE' EXIT
echo "lease taken $(date -Iseconds)"
for job in "$@"; do
  IFS=: read -r src out secs <<< "$job"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$BUILD' -Source '$src' -Output '$out' -Port $port -Seconds $secs" > /dev/null
  echo "$src -> rc=$?"
done
rm -f $LEASE
trap - EXIT
echo "lease released $(date -Iseconds)"
