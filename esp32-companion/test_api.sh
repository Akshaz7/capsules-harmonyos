#!/usr/bin/env bash
# Exercises the wrist companion HTTP API with curl and checks the answers.
# Works against the mock and against the real board:
#
#   ./test_api.sh                         # http://localhost:8080 (mock_esp32.py)
#   ./test_api.sh http://harmoniser.local # the board (or http://<ip shown on its screen>)
#
# Takes about 10 seconds. Exits non-zero if any check fails.
# On the board the last step lets a 2 second timer run out: the screen should flash and beep.

BASE=${1:-http://localhost:8080}
BASE=${BASE%/}
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
PASSED=0
FAILED=0
STATUS=""
BODY=""

# call METHOD PATH [JSON]: runs curl, prints the exchange, sets STATUS and BODY.
call() {
    local method=$1 path=$2 json=${3-}
    if [ -n "$json" ]; then
        echo "\$ curl -s -X $method $BASE$path -d '$json'"
        STATUS=$(curl -s -m 5 -o "$BODY_FILE" -w '%{http_code}' -X "$method" "$BASE$path" \
            -H 'Content-Type: application/json' -d "$json")
    else
        echo "\$ curl -s -X $method $BASE$path"
        STATUS=$(curl -s -m 5 -o "$BODY_FILE" -w '%{http_code}' -X "$method" "$BASE$path")
    fi
    BODY=$(cat "$BODY_FILE")
    echo "$STATUS $BODY"
}

# field NAME: value of a top-level field in BODY (the API always answers with flat, compact JSON).
field() {
    local value
    value=$(printf '%s' "$BODY" | sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p')
    [ -n "$value" ] || value=$(printf '%s' "$BODY" | sed -n 's/.*"'"$1"'":\([^,}"]*\).*/\1/p')
    printf '%s' "$value"
}

ok() {
    PASSED=$((PASSED + 1))
    echo "  ok    $1"
}

bad() {
    FAILED=$((FAILED + 1))
    echo "  FAIL  $1"
}

# expect WHAT ACTUAL WANTED
expect() {
    if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1 is '$2', wanted '$3'"; fi
}

# expect_between WHAT ACTUAL LOW HIGH
expect_between() {
    if [ -n "$2" ] && [ "$2" -ge "$3" ] 2>/dev/null && [ "$2" -le "$4" ]; then
        ok "$1 = $2 (allowed $3..$4)"
    else
        bad "$1 is '$2', wanted $3..$4"
    fi
}

expect_status() { expect "status" "$STATUS" "$1"; }
expect_field() { expect "$1" "$(field "$1")" "$2"; }

echo "== Wrist companion API test against $BASE"
call GET /state
if [ "$STATUS" = "000" ]; then
    echo "Nothing answers at $BASE. Start the mock (python3 mock_esp32.py) or check the board's IP."
    exit 2
fi
expect_status 200

echo
echo "== Counter"
call POST /capsule '{"type":"counter","label":"Squats","count":0}'
expect_status 200
expect_field type counter
expect_field label Squats
expect_field count 0
expect_field motion false
call POST /action '{"action":"increment"}'
call POST /action '{"action":"increment"}'
expect_field count 2
call GET /state
expect_status 200
expect_field count 2
call POST /action '{"action":"reset"}'
expect_field count 0
call POST /action '{"action":"start"}'
expect_status 409
call POST /capsule '{"type":"counter","label":"Reps","count":41}'
expect_field count 41
call POST /capsule '{"type":"counter","label":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}'
expect_field label abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstu

echo
echo "== Motion mode (experimental)"
call POST /action '{"action":"motion_on"}'
if [ "$STATUS" = "503" ]; then
    echo "  skip  this board has no working motion sensor"
else
    expect_status 200
    expect_field motion true
    call POST /action '{"action":"motion_off"}'
    expect_field motion false
fi

echo
echo "== Timer"
call POST /capsule '{"type":"timer","label":"Pasta","seconds":540}'
expect_status 200
expect_field type timer
expect_field label Pasta
expect_field seconds 540
expect_field running true
expect_field done false
expect_between remaining_seconds "$(field remaining_seconds)" 539 540
sleep 2
call GET /state
expect_between remaining_seconds "$(field remaining_seconds)" 536 538
call POST /action '{"action":"pause"}'
expect_field running false
PAUSED_AT=$(field remaining_seconds)
sleep 1.2
call GET /state
expect_field remaining_seconds "$PAUSED_AT"
call POST /action '{"action":"toggle"}'
expect_field running true
call POST /action '{"action":"reset"}'
expect_field running false
expect_field remaining_seconds 540
call POST /action '{"action":"increment"}'
expect_status 409
call POST /capsule '{"type":"timer","label":"Tea","seconds":180,"running":false}'
expect_field running false
expect_field remaining_seconds 180

echo
echo "== Bad requests leave the capsule alone"
call POST /capsule '{"type":"timer","label":'
expect_status 400
call POST /capsule '[1,2,3]'
expect_status 400
call POST /capsule '{"type":"stopwatch","label":"x"}'
expect_status 400
call POST /capsule '{"type":"timer","label":"no seconds"}'
expect_status 400
call POST /capsule '{"type":"timer","label":"zero","seconds":0}'
expect_status 400
call POST /capsule '{"type":"timer","label":"text","seconds":"540"}'
expect_status 400
call POST /capsule '{"type":"counter","label":"negative","count":-1}'
expect_status 400
call POST /capsule '{"type":"counter","label":5}'
expect_status 400
call POST /action '{"action":"explode"}'
expect_status 400
call GET /nope
expect_status 404
call GET /capsule
expect_status 405
call POST /state '{}'
expect_status 405
call GET /state
expect_field label Tea
expect_field remaining_seconds 180

echo
echo "== Timer end (on the board: screen flashes, speaker beeps)"
call POST /capsule '{"type":"timer","label":"Done test","seconds":2}'
expect_field running true
sleep 3
call GET /state
expect_field done true
expect_field running false
expect_field remaining_seconds 0

echo
echo "== $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
