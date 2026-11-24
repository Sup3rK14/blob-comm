#!/usr/bin/env bash
# Regression test: sync's per-row jq program must compile and match mentions (a precedence slip in
# addresses_me once broke every sync with new rows, so sends showed as failed).  bash tests/core/test_sync_mentions.sh [blobcom.sh]
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$HERE/../../skills/blob-com/scripts/blobcom.sh}
T=$(mktemp -d 2>/dev/null || echo /tmp/bcsync.$$); mkdir -p "$T"
# the jq program that builds sync's newlist row
awk '/newlist=\$\(echo "\$newlist" \| jq -c --argjson row/{f=1; sub(/^[^'"'"']*'"'"'/,""); print; next} f{ if (index($0,"'"'"')")) { sub(/'"'"'\).*/,""); print; exit } print }' "$SCRIPT" > "$T/nl.jq"
pass=0 fail=0
check() { # text mentions expect_pings expect_addresses
  local got; got=$(echo '[]' | jq -c --argjson row "$(jq -nc --arg t "$1" --arg m "$2" '{id:"r1",text:$t,mentions:$m,author_email:"sam@example.com"}')" \
    --argjson v '{"verified":true,"edited":false,"reason":"ok"}' --arg me alex@example.com --arg bn "Alex's Blob" -f "$T/nl.jq" 2>&1 | jq -c '.[0] | [.pings_me, .addresses_me]' 2>&1)
  if [ "$got" = "[$3,$4]" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: [$1|$2] got $got want [$3,$4]"; fi
}
check "hello" "" false false
check "hi Alex's Blob" "" false true
check "hey alexs blob" "" false true
check "@Alex" "alex@example.com" true false
check "@Alex's Blob" "blob:alex@example.com" false true
check "everyone" "all-blobs" false true
check "hi Alexandra's Blob" "" false false
rm -rf "$T"
echo "sync mentions: $pass passed, $fail failed"
[ $fail -eq 0 ]
