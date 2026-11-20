#!/usr/bin/env bash
# Unit tests for blobcom.sh's jq library (timestamps, actor keys, verification, streak, quiet hours).
# Pure bash + jq, no platform calls: runs locally and in Blob's own shell.
#   bash tests/core/test_jqlib.sh [path/to/blobcom.sh]
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$HERE/../../skills/blob-com/scripts/blobcom.sh}
BLOBCOM_SOURCE_ONLY=1 . "$SCRIPT"
pass=0; fail=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}

# timestamps
eq "ts Z" 1795161884 "$(jql -nr '"2026-11-20T08:04:44Z"|ts')"
eq "ts offset+fraction" 1795161884.219014 "$(jql -nr '"2026-11-20T00:04:44.219014-08:00"|ts')"
eq "ts +05:30" 1795161884 "$(jql -nr '"2026-11-20T13:34:44+05:30"|ts')"
eq "ts empty" 0 "$(jql -nr '""|ts')"
eq "ts leap day" 1709164800 "$(jql -nr '"2024-02-29T00:00:00Z"|ts')"
eq "ts order across offsets" true "$(jql -nr '("2026-11-20T00:05:00-08:00"|ts) > ("2026-11-20T08:04:59Z"|ts)')"

# actor keys
eq "key session" "computer:abc" "$(jql -nr '"session:abc:s1"|actorkey')"
eq "key command" "computer:abc" "$(jql -nr '"command:abc:c1"|actorkey')"
eq "key person" "person:123" "$(jql -nr '"person:u_123"|actorkey')"
eq "key null" "unknown" "$(jql -nr 'null|actorkey')"

ME='{"email":"kai@example.com","keys":["computer:mine1","person:111"],"names":["Kai","Kai'"'"'s Blob"]}'
ROW_KAI='{"id":"r1","kind":"text","author_email":"kai@example.com","author_kind":"person","created_by":"session:mine1:s","version":1}'
ROW_OTHER_CLAIM='{"id":"r2","kind":"text","author_email":"ana@example.com","author_kind":"person","created_by":"session:mine1:s","version":1}'
ROW_ANA='{"id":"r3","kind":"text","author_email":"ana@example.com","author_kind":"person","created_by":"session:anas:s","version":1}'
ROW_SPOOF_KAI='{"id":"r4","kind":"text","author_email":"kai@example.com","author_kind":"person","created_by":"session:anas:s","version":1}'
ROW_EDITED='{"id":"r5","kind":"text","author_email":"kai@example.com","author_kind":"person","created_by":"session:mine1:s","version":2}'
ROW_BLOB_FOR_OTHER='{"id":"r6","kind":"text","author_email":"kai@example.com","author_kind":"blob","for_email":"ana@example.com","created_by":"session:mine1:s","version":1}'
DIRECT='[{"email":"kai@example.com","status":"joined"},{"email":"ana@example.com","status":"joined"}]'
GROUP='[{"email":"kai@example.com"},{"email":"ana@example.com","actors":["computer:anas"]},{"email":"bo@example.com"}]'
v() { jql -nc --argjson row "$1" --argjson ev "${3:-[]}" --argjson me "$ME" --argjson m "$2" --arg k "${5:-direct}" '{row:$row, events:$ev, me:$me, members:$m, owner:"kai@example.com", kind:$k} | verify | '"${4:-.verified}"; }
vg() { v "$1" "$2" "${3:-[]}" "${4:-.verified}" group; }

eq "mine, my email -> verified" true "$(v "$ROW_KAI" "$DIRECT")"
eq "mine, other's email -> unverified" false "$(v "$ROW_OTHER_CLAIM" "$DIRECT")"
eq "other account in direct -> verified" true "$(v "$ROW_ANA" "$DIRECT")"
eq "direct chat needs no pin" null "$(v "$ROW_ANA" "$DIRECT" '[]' .pin)"
eq "other account claiming me -> unverified" false "$(v "$ROW_SPOOF_KAI" "$DIRECT")"
eq "edited flag from version" true "$(v "$ROW_EDITED" "$DIRECT" '[]' .edited)"
eq "edited flag from history" true "$(v "$ROW_KAI" "$DIRECT" '[{"op":"create","by":"session:mine1:s"},{"op":"change","by":"session:mine1:s"}]' .edited)"
eq "history beats created_by" false "$(v "$ROW_KAI" "$DIRECT" '[{"op":"create","by":"session:anas:s"}]')"
eq "my blob for someone else -> unverified" false "$(v "$ROW_BLOB_FOR_OTHER" "$DIRECT")"
eq "group: pinned device ok" true "$(vg "$ROW_ANA" "$GROUP")"
ROW_BO_FROM_ANA='{"id":"r7","kind":"text","author_email":"bo@example.com","author_kind":"person","created_by":"session:anas:s","version":1}'
eq "group: device pinned to another member -> unverified" false "$(vg "$ROW_BO_FROM_ANA" "$GROUP")"
ROW_BO='{"id":"r8","kind":"join","author_email":"bo@example.com","author_kind":"person","created_by":"session:bos:s","version":1}'
eq "group: first device TOFU" true "$(vg "$ROW_BO" "$GROUP")"
ROW_ANA_NEW='{"id":"r9","kind":"text","author_email":"ana@example.com","author_kind":"person","created_by":"session:anas2:s","version":1}'
eq "group: new device for pinned member -> unverified" false "$(vg "$ROW_ANA_NEW" "$GROUP")"
ROW_STRANGER='{"id":"r10","kind":"join","author_email":"eve@example.com","author_kind":"person","created_by":"session:eve:s","version":1}'
eq "join from non-member -> unverified" false "$(vg "$ROW_STRANGER" "$GROUP")"

# M3: labels must fit the author
NAMED='[{"email":"kai@example.com"},{"email":"ana@example.com","name":"Ana","blob_name":"Ana'"'"'s Blob"}]'
ROW_ANA_BLOB_FOR_SAM='{"id":"m1","kind":"text","author_email":"ana@example.com","author_name":"Sam'"'"'s Blob","author_kind":"blob","for_email":"sam@example.com","created_by":"session:anas:s","version":1}'
eq "M3 blob row for someone else -> unverified" false "$(v "$ROW_ANA_BLOB_FOR_SAM" "$NAMED")"
ROW_ANA_WRONGNAME='{"id":"m2","kind":"text","author_email":"ana@example.com","author_name":"Sam","author_kind":"person","created_by":"session:anas:s","version":1}'
eq "M3 name mismatch -> unverified" false "$(v "$ROW_ANA_WRONGNAME" "$NAMED")"
ROW_ANA_OK='{"id":"m3","kind":"text","author_email":"ana@example.com","author_name":"Ana'"'"'s Blob","author_kind":"blob","for_email":"ana@example.com","created_by":"session:anas:s","version":1}'
eq "M3 matching blob row -> verified" true "$(v "$ROW_ANA_OK" "$NAMED")"
ROW_OUT_PERSON='{"id":"m4","kind":"outcome","author_email":"ana@example.com","author_name":"Ana","author_kind":"person","created_by":"session:anas:s","version":1}'
eq "M3 outcome from a person label -> unverified" false "$(v "$ROW_OUT_PERSON" "$NAMED")"
ROW_SYS_ANA='{"id":"m5","kind":"system","author_email":"ana@example.com","author_name":"Ana","author_kind":"person","created_by":"session:anas:s","version":1}'
eq "M3 system row not from owner -> unverified" false "$(v "$ROW_SYS_ANA" "$NAMED")"
ROW_SYS_KAI_EDITED='{"id":"m6","kind":"system","author_email":"kai@example.com","author_name":"Kai","author_kind":"person","created_by":"session:mine1:s","version":2}'
eq "M11 changed system row -> unverified" false "$(v "$ROW_SYS_KAI_EDITED" "$NAMED")"
ROW_KAI_WRONGNAME='{"id":"m7","kind":"text","author_email":"kai@example.com","author_name":"Sam","author_kind":"person","created_by":"session:mine1:s","version":1}'
eq "M3 my account with another name -> unverified" false "$(v "$ROW_KAI_WRONGNAME" "$NAMED")"
# M4: in groups, pin only from the member's own join row
ROW_BO_TEXT='{"id":"m8","kind":"text","author_email":"bo@example.com","author_kind":"person","created_by":"session:bos:s","version":1}'
eq "M4 group text before any join -> unverified" false "$(vg "$ROW_BO_TEXT" "$GROUP")"
eq "M4 join row pins" '"computer:bos"' "$(vg "$ROW_BO" "$GROUP" '[]' .pin)"

# streak
eq "streak verified person resets" 0 "$(jql -nc '[{kind:"text",author_kind:"blob",verified:true},{kind:"text",author_kind:"person",verified:true}] | {rows:., start:1} | streak')"
eq "M2 unverified person row does not reset" 3 "$(jql -nc '[{kind:"text",author_kind:"blob",verified:true},{kind:"text",author_kind:"person",verified:false}] | {rows:., start:1} | streak')"
eq "streak counts blobs" 2 "$(jql -nc '[{kind:"text",author_kind:"person",verified:true},{kind:"text",author_kind:"blob",verified:true},{kind:"request",author_kind:"blob",verified:true}] | {rows:., start:0} | streak')"
eq "streak ignores outcome/system" 1 "$(jql -nc '[{kind:"outcome",author_kind:"blob"},{kind:"system",author_kind:"person"}] | {rows:., start:1} | streak')"

# quiet hours
eq "quiet overnight 23:00" true "$(jql -n '{from:"22:00", to:"08:00", now:"23:00"} | inquiet')"
eq "quiet overnight 07:59" true "$(jql -n '{from:"22:00", to:"08:00", now:"07:59"} | inquiet')"
eq "quiet overnight 08:00" false "$(jql -n '{from:"22:00", to:"08:00", now:"08:00"} | inquiet')"
eq "quiet daytime window" true "$(jql -n '{from:"12:00", to:"13:00", now:"12:30"} | inquiet')"
eq "quiet none" false "$(jql -n '{from:"", to:"", now:"10:00"} | inquiet')"

# pj
eq "pj string" 1 "$(jql -nc '"{\"a\":1}" | pj | .a')"
eq "pj bad" null "$(jql -nc '"{bad" | pj')"
eq "pj null" null "$(jql -nc 'null | pj')"

echo "jqlib: $pass passed, $fail failed"
[ $fail -eq 0 ]

