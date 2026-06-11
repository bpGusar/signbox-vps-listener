#!/bin/sh
set -e

cd "$(dirname "$0")"

: "${VPS_TOKEN:=test-secret-change-me}"
: "${PUBLIC_URL:=http://127.0.0.1:${PORT:-8080}}"
: "${HOST:=0.0.0.0}"
: "${PORT:=8080}"

export VPS_TOKEN PUBLIC_URL HOST PORT

exec python3 ./server.py
