#!/usr/bin/env bash
# Unit tests for decide's gate (H2/N2) with a mock `blob`: the card, decision, and text come only from
# an outbox row the person wrote. No platform calls.  bash tests/core/test_decide.sh [blobcom.sh]
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$HERE/../../skills/blob-com/scripts/blobcom.sh}
T=$(mktemp -d 2>/dev/null || echo /tmp/bcdecide.$$); mkdir -p "$T"
cat > "$T/blob" <<'MOCK'
#!/usr/bin/env bash
# mock: blob platform NAME --json JSON
op=$2; in=$4; D=$(dirname "$0")
echo "$op $in" >> "$D/calls.log"
case "$op" in
  readTable)
    t=$(echo "$in" | jq -r .table); w=$(echo "$in" | jq -r '.where // ""')
    case "$t:$w" in
      blobcom_outbox:id=r_obperson) echo '{"records":[{"id":"r_obperson","action":"decide","created_by":"person:u_111","payload":"{\"private_id\":\"r_card\",\"decision\":\"declined\"}"}]}';;
      blobcom_outbox:id=r_obsession) echo '{"records":[{"id":"r_obsession","action":"decide","created_by":"session:c1:s1","payload":"{\"private_id\":\"r_card\",\"decision\":\"approved\"}"}]}';;
      blobcom_private:id=r_card) echo '{"records":[{"id":"r_card","version":1,"chat_id":"t_0123456789abcdef","status":"pending","title":"SEND AS YOU?","text":"hi","action":"{\"do\":\"post\",\"text\":\"hi\"}"}]}';;
      blobcom_profile:*) echo '{"records":[{"id":"r_p","person_email":"kai@example.com","person_name":"Kai","blob_name":"Kai'"'"'s Blob"}]}';;
      *) echo '{"records":[],"total":0}';;
    esac;;
  listComputers) echo '{"computers":[{"computerId":"c1"}]}';;
  listAutomations) echo '{"automations":[{"id":"chat","owner":{"user":"u_111"}}]}';;
  writeRecords) echo '{"ids":[],"records":1}';;
  *) echo '{}';;
esac
MOCK
chmod +x "$T/blob"
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: expected [$2] got [$3]"; fi; }
run() { BLOBCOM_BLOB="$T/blob" bash "$SCRIPT" "$@" 2>"$T/err"; echo "rc=$?"; }

eq "no --outbox refused" "rc=4" "$(run decide r_card approve | tail -1)"
eq "session-written outbox row refused" "rc=4" "$(run decide --outbox r_obsession | tail -1)"
grep -q "not by your person" "$T/err"; eq "says why" 0 $?
eq "card mismatch refused" "rc=4" "$(run decide r_other approve --outbox r_obperson | tail -1)"
out=$(run decide r_card approve --outbox r_obperson)
eq "person row: decision taken from the row (declined), not the argument (approve)" '"declined"' "$(echo "$out" | head -1 | jq '.status')"
grep -q '"status":"declined"' "$T/calls.log"; eq "wrote declined to the card" 0 $?
grep -q '"op":"create"' "$T/calls.log"; eq "decline posted nothing" 1 $?

echo "decide: $pass passed, $fail failed"
rm -rf "$T"
[ $fail -eq 0 ]

