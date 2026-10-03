#!/usr/bin/env bash
# Exercises the cloud device relay (RELAY.md) with curl: the user-side routes and a simulated
# board. Works against the fake and, later, against the real backend:
#
#   ./test_relay.sh                          # http://localhost:8090 (mock_relay.py)
#   ./test_relay.sh https://example.vercel.app
#
# The real backend will want its own login on the user-side routes. Give it as one header:
#
#   RELAY_USER_HEADER='Cookie: session=...' ./test_relay.sh https://...
#
# Not covered: a pairing code running out after 10 minutes (tests/test_mock_relay.py does
# that for the fake). The simulated board registers under a hardware id of its own (RELAY_TEST_HW, default
# "test-relay-sh"), so a real board on the same relay is left alone. Tokens are not printed.
# Needs bash and curl. Exits non-zero if any check fails.

BASE=${1:-http://localhost:8090}
BASE=${BASE%/}
API=$BASE/api/devices
HW=${RELAY_TEST_HW:-test-relay-sh}
USER_HEADER=${RELAY_USER_HEADER:-X-Relay-Test: 1}
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
PASSED=0
FAILED=0
STATUS=""
BODY=""

# call WHO METHOD PATH [JSON]: runs curl, prints the exchange, sets STATUS and BODY.
# WHO is "user", "none" (no credentials at all) or a device token.
call() {
    local who=$1 method=$2 path=$3 json=${4-}
    local header=$USER_HEADER shown="user"
    case $who in
    user) ;;
    none) header="X-Relay-Test: 1" shown="nobody" ;;
    *) header="Authorization: Bearer $who" shown="board" ;;
    esac
    local args=(-s -m 10 -o "$BODY_FILE" -w '%{http_code}' -X "$method" "$API$path" -H "$header")
    [ -z "$json" ] || args+=(-H 'Content-Type: application/json' -d "$json")
    echo "\$ [$shown] $method /api/devices$path${json:+ $json}"
    STATUS=$(curl "${args[@]}")
    BODY=$(cat "$BODY_FILE")
    echo "$STATUS $(printf '%s' "$BODY" | sed 's/"token":"[^"]*"/"token":"<hidden>"/')"
}

# field NAME: value of a field in BODY (compact JSON; the names used here occur once).
field() {
    local value
    value=$(printf '%s' "$BODY" | sed -n 's/.*"'"$1"'": *"\([^"]*\)".*/\1/p')
    [ -n "$value" ] || value=$(printf '%s' "$BODY" | sed -n 's/.*"'"$1"'": *\([^,}" ]*\).*/\1/p')
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

expect() { # expect WHAT ACTUAL WANTED
    if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1 is '$2', wanted '$3'"; fi
}

expect_status() { expect "status" "$STATUS" "$1"; }
expect_field() { expect "$1" "$(field "$1")" "$2"; }

expect_differs() { # expect_differs WHAT ACTUAL OTHER
    if [ -n "$2" ] && [ "$2" != "$3" ]; then ok "$1 changed"; else bad "$1 did not change"; fi
}

expect_has() { # expect_has TEXT
    case $BODY in *"$1"*) ok "answer has $1" ;; *) bad "answer lacks $1" ;; esac
}

STATE='{"type":"counter","label":"Squats","count":4,"seconds":0,"remaining_seconds":0,"running":false,"done":false,"motion":false,"version":'

echo "== Device relay test against $BASE"
call none POST /register "{\"hw\":\"$HW\",\"kind\":\"wrist\",\"fw\":\"test_relay.sh\"}"
if [ "$STATUS" = "000" ]; then
    echo "Nothing answers at $BASE. Start the fake: python3 mock_relay.py"
    exit 2
fi
expect_status 201
ID=$(field id)
TOKEN=$(field token)
CODE=$(field code)
if printf '%s' "$CODE" | grep -Eq '^[a-z]{3,5}-[a-z]{3,5}-[a-z]{3,5}$'; then
    ok "code is three words ($CODE)"
else
    bad "code is '$CODE', wanted three lower-case words of 3 to 5 letters joined by hyphens"
fi
[ -n "$ID" ] && ok "id present" || bad "no id"
[ ${#TOKEN} -ge 16 ] && ok "token present" || bad "no token"

echo
echo "== Board, before anyone claimed it"
call "$TOKEN" GET "/$ID/capsule"
expect_status 200
expect_field claimed false
expect_field code "$CODE"
expect_has '"capsule":null'
expect_has '"action":null'
BASE_VERSION=$(field version)
BASE_SEQ=$(field action_seq)
call wrong-token GET "/$ID/capsule"
expect_status 401
call none GET "/$ID/capsule"
expect_status 401
call "$TOKEN" GET "/no-such-device/capsule"
expect_status 401
call wrong-token POST "/$ID/state" "${STATE}0}"
expect_status 401

echo
echo "== Claim"
call user POST /claim '{"code":"not-the-code"}'
expect_status 404
call user POST /claim '{"code":"123456"}'
expect_status 400
call user POST /claim '{"code":"only-two"}'
expect_status 400
# As a person types it: capitals, spaces instead of hyphens.
TYPED=$(printf '%s' "$CODE" | tr 'a-z-' 'A-Z ')
call user POST /claim "{\"code\":\"  $TYPED \"}"
expect_status 200
expect_field id "$ID"
call "$TOKEN" GET "/$ID/capsule"
expect_field claimed true
expect_has '"code":null'
call user POST /claim "{\"code\":\"$CODE\"}"
expect_status 404

echo
echo "== Capsule: user -> relay -> board"
call user PUT "/$ID/capsule" '{"type":"counter","label":"Squats","count":3}'
expect_status 200
VERSION=$(field version)
expect_differs version "$VERSION" "$BASE_VERSION"
call "$TOKEN" GET "/$ID/capsule"
expect_status 200
expect_field version "$VERSION"
expect_field type counter
expect_field label Squats
expect_field count 3
call "$TOKEN" GET "/$ID/capsule"
expect_field version "$VERSION"
call user PUT "/$ID/capsule" '{"type":"timer","label":"No seconds"}'
expect_status 400
call user PUT "/$ID/capsule" '{"type":"counter","count":-1}'
expect_status 400
call user PUT "/$ID/capsule" '{"type":"counter","x":[[[[[[[[1]]]]]]]]}'
expect_status 400
call "$TOKEN" GET "/$ID/capsule"
expect_field version "$VERSION"
expect_field label Squats

echo
echo "== Action: user -> relay -> board"
call user POST "/$ID/action" '{"action":"increment"}'
expect_status 200
SEQ=$(field action_seq)
expect_differs action_seq "$SEQ" "$BASE_SEQ"
call "$TOKEN" GET "/$ID/capsule"
expect_field action_seq "$SEQ"
expect_field action increment
expect_field version "$VERSION"
call user POST "/$ID/action" '{"action":"explode"}'
expect_status 400
call "$TOKEN" GET "/$ID/capsule"
expect_field action_seq "$SEQ"

echo
echo "== State: board -> relay -> user"
call "$TOKEN" POST "/$ID/state" "${STATE}${VERSION}}"
expect_status 204
expect "body" "$BODY" ""
call user GET "/$ID/state"
expect_status 200
expect_field type counter
expect_field count 4
expect_field version "$VERSION"
SEEN=$(field last_seen_ms_ago)
if [ -n "$SEEN" ] && [ "$SEEN" -ge 0 ] 2>/dev/null && [ "$SEEN" -le 10000 ]; then
    ok "last_seen_ms_ago = $SEEN (allowed 0..10000)"
else
    bad "last_seen_ms_ago is '$SEEN', wanted 0..10000"
fi

echo
echo "== Timer, and a new capsule drops the pending action"
call user PUT "/$ID/capsule" '{"type":"timer","label":"Pasta","seconds":540}'
expect_status 200
TIMER_VERSION=$(field version)
expect_differs version "$TIMER_VERSION" "$VERSION"
call "$TOKEN" GET "/$ID/capsule"
expect_field type timer
expect_field seconds 540
expect_has '"action":null'
expect_field action_seq "$SEQ"

echo
echo "== Registering again: same device, new token and code, unclaimed"
OLD_TOKEN=$TOKEN
call none POST /register "{\"hw\":\"$HW\",\"kind\":\"wrist\",\"fw\":\"test_relay.sh\"}"
expect_status 201
expect_field id "$ID"
TOKEN=$(field token)
expect_differs token "$TOKEN" "$OLD_TOKEN"
expect_differs code "$(field code)" "$CODE"
call "$OLD_TOKEN" GET "/$ID/capsule"
expect_status 401
call "$TOKEN" GET "/$ID/capsule"
expect_status 200
expect_field claimed false
expect_has '"capsule":null'

echo
echo "== $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
