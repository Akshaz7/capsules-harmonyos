#!/bin/sh
# Fails (exit 1) if the capsule screen no longer mounts T4's "Add to home screen" button with the open
# capsule's id. T1 runs it after every UI change:  sh scripts/check-add-to-home.sh
cd "$(dirname "$0")/.." || exit 1
PAGE=entry/src/main/ets/pages/Index.ets
BUTTON=entry/src/main/ets/widget/AddToHomeButton.ets
fail() { echo "check-add-to-home: FAIL: $1" >&2; exit 1; }
[ -f "$BUTTON" ] || fail "$BUTTON is missing"
grep -q '@Require @Param capsuleId: string' "$BUTTON" || fail "AddToHomeButton must take capsuleId as a required @Param"
grep -q "import { AddToHomeButton } from '../widget/AddToHomeButton'" "$PAGE" || fail "$PAGE does not import AddToHomeButton"
grep -q 'AddToHomeButton({ capsuleId: entry.capsule.id' "$PAGE" || fail "$PAGE does not mount AddToHomeButton({ capsuleId: entry.capsule.id, ... })"
grep -q 'PROTECTED: owned by T4. Do not remove or modify. See /tmp/hy-tasks.' "$PAGE" || fail "the PROTECTED comment at the mount point is gone"
# The mount must not sit inside a condition that hides it for some capsules (e.g. route.widget).
LINE=$(grep -n 'AddToHomeButton({ capsuleId: entry.capsule.id' "$PAGE" | head -1 | cut -d: -f1)
PREV=$(sed -n "$((LINE - 3)),$((LINE - 1))p" "$PAGE")
echo "$PREV" | grep -q 'if (' && fail "the mount is inside an if: it must show for every capsule"
echo "check-add-to-home: OK"
