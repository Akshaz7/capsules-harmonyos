#!/usr/bin/env bash
# Finds the wrist companion on the local network without a serial cable.
# Prints its IP address and writes it to esp32_ip.txt. Works on Linux and macOS.
#
#   ./find_esp32.sh                     # mDNS, then the neighbour table, then a ping sweep of this /24
#   ./find_esp32.sh 10.250.170          # sweep another /24 as well (venue networks are often bigger)
#   ESP32_MAC=aa:bb:cc:dd:ee:ff ./find_esp32.sh
#
# The MAC is the board's Wi-Fi station address, printed at boot ("net: station MAC ...").

# Set it with ESP32_MAC, or put it on one line in esp32_mac.local (git-ignored) next to this script.
HERE="$(cd "$(dirname "$0")" && pwd)"
MAC=${ESP32_MAC:-$(cat "$HERE/esp32_mac.local" 2>/dev/null)}
OUT="$HERE/esp32_ip.txt"

# macOS prints MAC octets without leading zeros, so compare in that form.
normalise() { tr '[:upper:]' '[:lower:]' | sed -E 's/(^|[: ])0([0-9a-f])/\1\2/g'; }

answers_api() { curl -s -m 3 "http://$1/state" 2>/dev/null | grep -q '"type"'; }

# found IP [unconfirmed]: saves and prints the address, and ends the script.
found() {
    echo "$1" > "$OUT"
    if [ -z "${2-}" ]; then
        echo "found the board at $1 (API answers; address saved to esp32_ip.txt)" >&2
    else
        echo "found the board's MAC at $1, but http://$1/state does not answer" >&2
    fi
    echo "$1"
    exit 0
}

neighbours() {
    if command -v ip >/dev/null 2>&1; then ip -4 neigh show; else arp -an; fi
}

from_neighbour_table() {
    local wanted
    wanted=$(printf '%s' "$MAC" | normalise)
    # -w: the whole address, so that 1:2:3:4:5:6 is not found inside 11:2:3:4:5:6
    neighbours | normalise | grep -wF "$wanted" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1
}

local_address() {
    if command -v ip >/dev/null 2>&1; then
        ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p'
    else
        ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
    fi
}

sweep() { # sweep A.B.C: one ping to every host so they show up in the neighbour table
    local timeout_flag="-W 1"
    [ "$(uname)" = "Darwin" ] && timeout_flag="-t 1"
    echo "pinging $1.1-254 ..." >&2
    for host in $(seq 1 254); do
        ping -c 1 $timeout_flag "$1.$host" >/dev/null 2>&1 &
    done
    wait
}

# 1. mDNS (works where the OS resolves .local names and the network passes multicast)
# -4: the board has no IPv6 address, and waiting for an AAAA answer can use up the timeout
address=$(curl -4 -s -m 4 -o /dev/null -w '%{remote_ip}' http://harmoniser.local/state 2>/dev/null)
[ -n "$address" ] && answers_api "$address" && found "$address"
if [ -z "$MAC" ]; then
    echo "harmoniser.local did not resolve and no MAC is set (ESP32_MAC or esp32_mac.local)" >&2
    exit 1
fi
echo "harmoniser.local did not resolve, looking for MAC $MAC instead" >&2

# 2. Already known to this machine? The entry can be stale (the board has moved to another
# address since, or is off), so it only counts if the API answers there.
address=$(from_neighbour_table)
[ -n "$address" ] && answers_api "$address" && found "$address"

# 3. Ping sweep, then look again
own=$(local_address)
[ -n "$own" ] || { echo "could not work out this machine's IP address" >&2; exit 1; }
for prefix in "${own%.*}" "$@"; do
    sweep "$prefix"
    address=$(from_neighbour_table)
    [ -n "$address" ] && answers_api "$address" && found "$address"
    [ -n "$address" ] && silent=$address
done

# The MAC is on the network but nothing serves the API there: still worth knowing.
[ -n "${silent-}" ] && found "$silent" unconfirmed

echo "not found. Is the board powered and on this network? Its screen and serial log show the IP." >&2
exit 1
