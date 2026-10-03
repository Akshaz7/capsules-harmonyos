#!/usr/bin/env bash
# Exercises the cloud device relay (RELAY.md) with curl: the user-side routes and a simulated
# board. Works against the fake and, later, against the real backend:
#
#   ./test_relay.sh                          # http://localhost:8090 (mock_relay.py)
#   ./test_relay.sh https://example.vercel.app
#
# The user-side requests carry "Authorization: Bearer <install token>". The fake takes any
# token; the script makes one up per run. For a backend that wants a real one:
#
#   RELAY_INSTALL_TOKEN=... ./test_relay.sh https://...
#
# RELAY_OTHER_TOKEN is a second install, used to check that it cannot see the first one's
# device; set it to empty to skip those checks where a second real token is not at hand.
#
# Not covered: a pairing code running out after 10 minutes, and the 429 after too many wrong
# codes (tests/test_mock_relay.py does both for the fake). The simulated board registers under a hardware id of its own (RELAY_TEST_HW, default
# "test-relay-sh"), so a real board on the same relay is left alone. Tokens are not printed.
# Needs bash and curl. Exits non-zero if any check fails.

BASE=${1:-http://localhost:8090}
BASE=${BASE%/}
API=$BASE/api/devices
HW=${RELAY_TEST_HW:-test-relay-sh}
INSTALL_TOKEN=${RELAY_INSTALL_TOKEN:-test-relay-sh-$$-$RANDOM}
OTHER_TOKEN=${RELAY_OTHER_TOKEN-test-relay-sh-other-$$-$RANDOM}
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
PASSED=0
FAILED=0
STATUS=""
BODY=""

# call WHO METHOD PATH [JSON]: runs curl, prints the exchange, sets STATUS and BODY.
# WHO is "user", "other" (a second install of the app), "none" (no credentials at all) or a
# device token.
call() {
    local who=$1 method=$2 path=$3 json=${4-}
    local header shown
    case $who in
    user) header="Authorization: Bearer $INSTALL_TOKEN" shown="app" ;;
    other) header="Authorization: Bearer $OTHER_TOKEN" shown="another app" ;;
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
PAIR_URL=$(field pair_url)
case $PAIR_URL in
http://*"/pair?code=$CODE" | https://*"code=$CODE"*) ok "pair_url holds the code ($PAIR_URL)" ;;
*) bad "pair_url is '$PAIR_URL', wanted an http(s) URL with code=$CODE in it" ;;
esac
[ ${#PAIR_URL} -le 200 ] && ok "pair_url is at most 200 bytes" || bad "pair_url is ${#PAIR_URL} bytes, the board takes 200"
[ -n "$ID" ] && ok "id present" || bad "no id"
[ ${#TOKEN} -ge 16 ] && ok "token present" || bad "no token"

echo
echo "== Board, before anyone claimed it"
call "$TOKEN" GET "/$ID/capsule"
expect_status 200
expect_field claimed false
expect_field code "$CODE"
expect_field pair_url "$PAIR_URL"
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
echo "== The page behind the QR code"
echo "\$ [phone] GET $PAIR_URL"
STATUS=$(curl -s -m 10 -o "$BODY_FILE" -w '%{http_code} %{content_type}' "$PAIR_URL")
echo "$STATUS"
case $STATUS in "200 text/html"*) ok "pair_url answers with a web page" ;; *) bad "pair_url gave '$STATUS', wanted 200 text/html" ;; esac
if grep -q "$CODE" "$BODY_FILE"; then ok "the page shows the code"; else bad "the page does not show the code"; fi
call "$TOKEN" GET "/$ID/capsule"
expect_field claimed false

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
call none POST /claim "{\"code\":\"$CODE\"}"
expect_status 401
call user POST /claim "{\"code\":\"  $TYPED \"}"
expect_status 200
expect_field id "$ID"
expect_field kind wrist
call user GET ""
expect_status 200
expect_has "\"id\":\"$ID\""
call "$TOKEN" GET "/$ID/capsule"
expect_field claimed true
expect_has '"code":null'
expect_has '"pair_url":null'
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

if [ -n "$OTHER_TOKEN" ]; then
    echo
    echo "== Another install cannot see or touch the device"
    call other GET "/$ID/state"
    expect_status 404
    call other PUT "/$ID/capsule" '{"type":"counter","label":"Not mine","count":1}'
    expect_status 404
    call other POST "/$ID/action" '{"action":"reset"}'
    expect_status 404
    call other DELETE "/$ID"
    expect_status 404
    call other GET ""
    expect_status 200
    case $BODY in *"$ID"*) bad "another install's list has the device" ;; *) ok "another install's list does not have the device" ;; esac
    call "$TOKEN" GET "/$ID/capsule"
    expect_field version "$VERSION"
fi
call none GET "/$ID/state"
expect_status 401
call none PUT "/$ID/capsule" '{"type":"counter","label":"Nobody","count":1}'
expect_status 401

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
echo "== Unpair: the board keeps its token and gets a fresh code"
call user DELETE "/$ID"
expect_status 204
call "$TOKEN" GET "/$ID/capsule"
expect_status 200
expect_field claimed false
expect_has '"capsule":null'
NEW_CODE=$(field code)
expect_differs code "$NEW_CODE" "$CODE"
case $(field pair_url) in *"code=$NEW_CODE"*) ok "pair_url holds the new code" ;; *) bad "pair_url is '$(field pair_url)', wanted code=$NEW_CODE in it" ;; esac
call user GET "/$ID/state"
expect_status 404
call user POST /claim "{\"code\":\"$NEW_CODE\"}"
expect_status 200
CODE=$NEW_CODE

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
