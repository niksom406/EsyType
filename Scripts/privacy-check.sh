#!/bin/zsh
# Privacy checks for the PRD: no network use outside model downloads, no transcripts or whisper output in logs,
# no audio on disk, private history file. Run with EsyType open; ideally right after a few dictations.
# Usage: Scripts/privacy-check.sh
set -uo pipefail
cd "${0:A:h}/.."
SUPPORT="$HOME/Library/Application Support/EsyType"
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

PID=$(pgrep -x EsyType | head -1)
if [[ -n "$PID" ]]; then
  check "EsyType (pid $PID) has no open network sockets" '[[ -z "$(lsof -nP -i -a -p $PID 2>/dev/null)" ]]'
else
  echo "SKIP  EsyType isn't running, so its sockets weren't checked"
fi
check "Only ModelStore uses the network in the source" \
  '[[ "$(grep -rlE "URLSession|NWConnection|CFSocket|URLRequest" Sources)" == "Sources/EsyTypeCore/ModelStore.swift" ]]'
check "No print() in app or engine code" '! grep -rn "print(" Sources --include="*.swift" | grep -v "Snapshots.swift" | grep -q .'
check "whisper.cpp and ggml wrote nothing to the system log in the last hour" \
  '[[ $(/usr/bin/log show --last 1h --predicate "process == \"EsyType\"" 2>/dev/null | grep -ciE "whisper_|ggml_") -eq 0 ]]'
check "No audio files in Application Support" \
  '[[ -z "$(find "$SUPPORT" -type f \( -iname "*.wav" -o -iname "*.caf" -o -iname "*.m4a" -o -iname "*.aiff" -o -iname "*.mp3" \) 2>/dev/null)" ]]'
if [[ -f "$SUPPORT/history.sqlite" ]]; then
  check "History files are readable only by you (0600)" \
    '[[ -z "$(find "$SUPPORT" -maxdepth 1 -name "history.sqlite*" ! -perm 600)" ]]'
fi
exit $fail
