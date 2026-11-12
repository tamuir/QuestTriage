#!/bin/sh
# Syntax-check every file and run tests.lua under Lua 5.1 (WoW's Lua) in Docker. Project is mounted read-only.
MSYS_NO_PATHCONV=1 docker run --rm -v "$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd):/w:ro" -w /w alpine:3.20 sh -c \
  'apk add --no-cache lua5.1 >/dev/null 2>&1 && for f in *.lua Libs/*/*.lua; do luac5.1 -p "$f" || exit 1; done && lua5.1 tests.lua'
