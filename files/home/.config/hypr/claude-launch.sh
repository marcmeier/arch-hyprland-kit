#!/usr/bin/env bash
# Menu for Claude Code: new session, continue the last one, or pick from the session list.
choice=$(printf '%s\n' "New session" "Continue last" "Browse sessions" | walker --dmenu -p "Claude") || exit 0
case "$choice" in
  "New session") args=(claude) ;;
  "Continue last") args=(claude -c) ;;
  "Browse sessions") args=(claude -r) ;;
  *) exit 0 ;;
esac
exec ghostty --working-directory="$HOME" -e "${args[@]}"
