#!/usr/bin/env python3
"""Stand-in for the cloud device relay (/api/devices/**), for testing the wrist firmware and
the app before the real backend exists. The contract is in RELAY.md.

Device side (the board calls these):

    POST /api/devices/register        {"hw","kind","fw"} -> 201 {"id","token","code","pair_url"}
    GET  /api/devices/{id}/capsule    Bearer token -> 200 {"claimed","version","capsule","action_seq","action",
                                                           "code","pair_url"}
    POST /api/devices/{id}/state      Bearer token, the board's state + "version" -> 204

User side (the app calls these, with X-Harmoniser-Token: <token>, the anonymous token the
app or browser made up itself: 32 to 256 characters of A-Z a-z 0-9 _ -, as on the real
backend. A device belongs to the token that claimed it):

    POST   /api/devices/claim         {"code":"brave-otter-lamp"} -> 200 {"id","kind"}
    GET    /api/devices               -> 200 {"devices":[{"id","kind","last_seen_ms_ago"}]}
    PUT    /api/devices/{id}/capsule  like the board's POST /capsule -> 200 {"version"}
    POST   /api/devices/{id}/action   {"action":"increment"} -> 200 {"action_seq"}
    GET    /api/devices/{id}/state    -> 200 last reported state + "last_seen_ms_ago"
    DELETE /api/devices/{id}          unpair -> 204
    GET  /pair?code=brave-otter-lamp  a small web page with a "Pair this device" button: what the
                                      QR code on the board opens in a phone's browser

Python 3.8+, standard library only (plus mock_esp32.py next to it, for the capsule rules):

    python3 mock_relay.py --port 8090 --host 0.0.0.0

Everything is kept in memory: a restart forgets every device, and a board that still holds
a token gets 401 and registers again. Tokens are never written to the log.

The pairing code is three words from WORDS below ("brave-otter-lamp"). It works once and
for --code-ttl seconds (default 600); after that the board gets a new one with its next poll.
pair_url is http://<the Host header of the board's request>/pair?code=<the code>, so it
points at this fake by the address the board reached it on (--public-url overrides that).
"""

from __future__ import annotations

import argparse
import hmac
import html
import json
import logging
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlsplit

import mock_esp32
from mock_esp32 import ApiError, parse_json_object

MAX_BODY_BYTES = mock_esp32.MAX_BODY_BYTES
HW_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}")
CODE_PATTERN = re.compile(r"[a-z]{3,5}(-[a-z]{3,5}){2}")
CODE_TTL_SECONDS = 600.0
MAX_FAILED_CLAIMS = 10  # wrong codes one install may send ...
CLAIM_WINDOW_SECONDS = 60.0  # ... within this time, before it gets 429
USER_TOKEN_HEADER = "X-Harmoniser-Token"
USER_TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_-]{32,256}")  # the real backend's lib/ownership.ts
HOST_PATTERN = re.compile(r"[A-Za-z0-9.\-\[\]:]{1,100}")
ACTIONS = mock_esp32.TIMER_ACTIONS + mock_esp32.COUNTER_ACTIONS

ERR_BAD_HW = "hw must be 1 to 64 letters, digits, _ or -"
ERR_BAD_KIND = "kind must be a string of 1 to 32 characters"
ERR_BAD_FW = "fw must be a string of 1 to 64 characters"
ERR_BAD_CODE = "code must be three words"
ERR_BAD_STATE = "state must have a type and a numeric version"
ERR_UNKNOWN_CODE = "no unclaimed device has this code (it works once, for 10 minutes)"
ERR_UNKNOWN_DEVICE = "no such device"
ERR_NO_INSTALL_TOKEN = "Send your device token in the X-Harmoniser-Token header."
ERR_TOO_MANY_CLAIMS = "too many wrong codes, wait a minute"
ERR_UNAUTHORIZED = "unknown device or token"

# Pairing words: 3 to 5 letters, common, spelled the way they sound, no two that sound alike.
# Enough for a fake (about 25 bits for three words). The real backend should use the EFF
# short word list instead (1,296 words, about 31 bits; CC BY 3.0, it needs attribution).
WORDS = (
    "otter", "tiger", "panda", "koala", "llama", "camel", "zebra", "hippo", "rhino", "lemur", "sloth", "bison",
    "mouse", "mole", "frog", "snail", "gecko", "cobra", "viper", "puppy", "pony", "goat", "sheep", "hen", "chick",
    "colt", "calf", "yak", "dove", "hawk", "crow", "swan", "robin", "eagle", "finch", "goose", "heron", "owl",
    "lark", "crane", "moth", "wasp", "crab", "clam", "squid", "trout", "shark", "fox", "wolf", "duck", "lion",
    "bat", "cat", "dog", "elk", "emu", "pug", "kiwi", "orca", "puma", "apple", "grape", "lemon", "mango", "melon",
    "peach", "olive", "onion", "basil", "mint", "honey", "toast", "pizza", "pasta", "salad", "soup", "rice", "corn",
    "kale", "fig", "lime", "nut", "oat", "milk", "cake", "candy", "cocoa", "curry", "bagel", "bacon", "cream",
    "sugar", "salt", "herb", "maple", "tulip", "daisy", "lilac", "lotus", "fern", "moss", "ivy", "oak", "elm",
    "pine", "palm", "birch", "aspen", "bush", "leaf", "stem", "twig", "vine", "bloom", "grass", "river", "lake",
    "pond", "ocean", "hill", "cliff", "cave", "rock", "sand", "stone", "cloud", "storm", "wind", "snow", "frost",
    "ice", "fog", "moon", "star", "comet", "orbit", "solar", "lunar", "dusk", "sky", "field", "marsh", "brook",
    "delta", "reef", "ridge", "glen", "grove", "trail", "path", "mesa", "dune", "lava", "ember", "flame", "spark",
    "smoke", "steam", "lamp", "desk", "chair", "table", "sofa", "couch", "shelf", "clock", "door", "wall", "roof",
    "tile", "brick", "book", "page", "pen", "paper", "card", "map", "flag", "tent", "rope", "boat", "raft", "canoe",
    "kayak", "train", "truck", "bike", "car", "bus", "jet", "sled", "wagon", "drum", "flute", "piano", "banjo",
    "harp", "horn", "tuba", "organ", "radio", "phone", "robot", "laser", "pixel", "cable", "wire", "plug", "fan",
    "oven", "stove", "fork", "spoon", "plate", "cup", "mug", "jar", "pan", "pot", "lid", "tray", "brush", "broom",
    "soap", "towel", "comb", "shirt", "sock", "boot", "hat", "cap", "coat", "scarf", "glove", "belt", "vest",
    "coin", "gem", "gold", "iron", "zinc", "brass", "glass", "cork", "wool", "silk", "linen", "felt", "box", "bag",
    "crate", "chest", "tool", "nail", "drill", "clamp", "hook", "lens", "torch", "brave", "calm", "happy", "jolly",
    "kind", "proud", "quick", "quiet", "rapid", "shiny", "smart", "sunny", "warm", "cool", "fresh", "giant", "tiny",
    "grand", "royal", "noble", "lucky", "fancy", "fuzzy", "witty", "zesty", "vivid", "solid", "sharp", "soft",
    "loud", "swift", "eager", "clean", "clear", "crisp", "green", "amber", "azure", "ivory", "pink", "ruby", "teal",
    "jade", "navy", "jump", "dance", "sing", "laugh", "smile", "climb", "paint", "build", "cook", "bake", "hike",
    "swim", "plant", "print", "spin", "hop", "skip", "clap", "wink", "nod", "hug", "zoom", "glide", "float",
    "drift", "march", "study", "learn", "teach",
)

# Error codes, as in the real backend's lib/devices/errors.ts. Where a message is not listed,
# the status decides; a 400 that is not listed is a capsule the board would refuse.
ERROR_CODES_BY_MESSAGE = {
    ERR_BAD_HW: "invalid_registration",
    ERR_BAD_KIND: "invalid_registration",
    ERR_BAD_FW: "invalid_registration",
    ERR_BAD_CODE: "invalid_code",
    ERR_BAD_STATE: "invalid_state",
    ERR_UNKNOWN_CODE: "code_not_found",
    mock_esp32.ERR_BAD_ACTION: "invalid_action",
    mock_esp32.ERR_BAD_JSON: "invalid_json",
    mock_esp32.ERR_TOO_DEEP: "invalid_json",
    mock_esp32.ERR_HAS_NUL: "invalid_json",
    mock_esp32.ERR_BAD_LENGTH: "invalid_json",
}
ERROR_CODES_BY_STATUS = {
    400: "invalid_capsule",
    401: "unauthorized",
    404: "not_found",
    405: "method_not_allowed",
    413: "payload_too_large",
    429: "rate_limited",
    500: "internal_error",
}

Json = Dict[str, Any]
log = logging.getLogger("mock_relay")


def error_body(status: int, message: str) -> Json:
    """The error envelope of the real backend: {"error":{"code","message"}}."""
    code = ERROR_CODES_BY_MESSAGE.get(message) or ERROR_CODES_BY_STATUS.get(status, "error")
    return {"error": {"code": code, "message": message}}


class Device:
    def __init__(self, device_id: str, hw: str) -> None:
        self.id = device_id
        self.hw = hw
        self.kind = ""
        self.fw = ""
        self.token = ""
        self.code = ""
        self.code_issued = 0.0  # time.monotonic() when the code was made
        self.pair_url = ""  # the page that claims the device with this code
        self.claimed = False
        self.owner = ""  # install token of the app that claimed it
        self.version = 0  # goes up with every PUT .../capsule; 0: nothing was ever sent
        self.capsule: Optional[Json] = None
        self.action_seq = 0  # goes up with every POST .../action
        self.action: Optional[str] = None
        self.state: Optional[Json] = None  # what the board last reported
        self.last_seen = time.monotonic()  # last request from the board


def normalise_code(text: str) -> str:
    """'Brave  Otter-Lamp ' -> 'brave-otter-lamp': what a person types, as the relay stores it."""
    return "-".join(part for part in re.split(r"[\s-]+", text.strip().lower()) if part)


def clean_capsule(body: Json) -> Json:
    """The capsule as the relay stores it and hands it to the board. Raises ApiError(400) for
    one the board would refuse: the rules are those of the board's POST /capsule."""
    state = mock_esp32.Capsule(motion_interval=0).set_capsule(body)
    capsule: Json = {"type": state["type"], "label": state["label"]}
    if state["type"] == "timer":
        capsule["seconds"] = state["seconds"]
        if "running" in body:
            capsule["running"] = body["running"]
    else:
        capsule["count"] = state["count"]
        if "motion" in body:
            capsule["motion"] = body["motion"]
    return capsule


class Relay:
    """All devices. Every public method is one route; they raise ApiError."""

    def __init__(self, code_ttl: float = CODE_TTL_SECONDS, public_url: str = "") -> None:
        self.code_ttl = code_ttl
        self.public_url = public_url.rstrip("/")  # empty: use the Host header of each request
        self.lock = threading.Lock()
        self.by_id: Dict[str, Device] = {}
        self.by_hw: Dict[str, Device] = {}
        self.failed_claims: Dict[str, List[float]] = {}  # install token -> times of wrong codes

    # ---- device side ----

    def register(self, body: Json, host: Optional[str] = None) -> Json:
        hw, kind, fw = body.get("hw"), body.get("kind"), body.get("fw")
        if not isinstance(hw, str) or not HW_PATTERN.fullmatch(hw):
            raise ApiError(400, ERR_BAD_HW)
        if not isinstance(kind, str) or not 1 <= len(kind) <= 32:
            raise ApiError(400, ERR_BAD_KIND)
        if not isinstance(fw, str) or not 1 <= len(fw) <= 64:
            raise ApiError(400, ERR_BAD_FW)
        with self.lock:
            device = self.by_hw.get(hw)
            if device is None:
                device = Device("dev_" + secrets.token_hex(8), hw)
                self.by_hw[hw] = device
                self.by_id[device.id] = device
            # Registering again: same id, but the old token and code are dead, the device has
            # to be claimed again, and what was queued for the previous owner is dropped.
            device.kind, device.fw = kind, fw
            device.token = secrets.token_urlsafe(32)
            self._issue_code(device, host)
            device.claimed = False
            device.owner = ""
            device.capsule = None
            device.action = None
            device.state = None
            device.last_seen = time.monotonic()
            return {"id": device.id, "token": device.token, "code": device.code, "pair_url": device.pair_url}

    def _issue_code(self, device: Device, host: Optional[str]) -> None:
        taken = {other.code for other in self.by_id.values() if not other.claimed}
        while True:
            code = "-".join(secrets.choice(WORDS) for _ in range(3))
            if code not in taken:
                break
        device.code = code
        device.code_issued = time.monotonic()
        base = self.public_url
        if not base:  # a Host header that is not a plain host[:port] is not echoed into a URL
            base = "http://" + (host if host and HOST_PATTERN.fullmatch(host) else "localhost")
        device.pair_url = f"{base}/pair?code={code}"

    def _code_expired(self, device: Device) -> bool:
        return time.monotonic() - device.code_issued >= self.code_ttl

    def _device_for(self, device_id: str, authorization: Optional[str]) -> Device:
        """The device a board's request is about. The lock must be held."""
        device = self.by_id.get(device_id)
        scheme, _, token = (authorization or "").partition(" ")
        if device is None or scheme.lower() != "bearer" or not token:
            raise ApiError(401, ERR_UNAUTHORIZED)
        if not hmac.compare_digest(token.strip().encode(), device.token.encode()):
            raise ApiError(401, ERR_UNAUTHORIZED)
        device.last_seen = time.monotonic()
        return device

    def poll(self, device_id: str, authorization: Optional[str], host: Optional[str] = None) -> Json:
        with self.lock:
            device = self._device_for(device_id, authorization)
            if not device.claimed and self._code_expired(device):
                self._issue_code(device, host)  # the board shows it from now on
            return {
                "claimed": device.claimed,
                "code": None if device.claimed else device.code,
                "pair_url": None if device.claimed else device.pair_url,
                "version": device.version,
                "capsule": device.capsule,
                "action_seq": device.action_seq,
                "action": device.action,
            }

    def report(self, device_id: str, authorization: Optional[str], read_body: Callable[[], Json]) -> None:
        with self.lock:
            self._device_for(device_id, authorization)  # 401 before the body is looked at
        body = read_body()
        version = body.get("version")
        if not isinstance(body.get("type"), str) or isinstance(version, bool) or not isinstance(version, (int, float)):
            raise ApiError(400, ERR_BAD_STATE)
        with self.lock:
            device = self._device_for(device_id, authorization)
            device.state = body

    # ---- user side ----

    @staticmethod
    def install_token(header: Optional[str]) -> str:
        """Who a user-side request comes from: the value of X-Harmoniser-Token. There are no
        accounts; the app (or a browser) made the token up, and a device belongs to the token
        that claimed it. Missing or not of the right shape: 401."""
        token = (header or "").strip()
        if not USER_TOKEN_PATTERN.fullmatch(token):
            raise ApiError(401, ERR_NO_INSTALL_TOKEN)
        return token

    def _count_failed_claim(self, user: str) -> None:
        """The lock must be held."""
        self.failed_claims.setdefault(user, []).append(time.monotonic())

    def claim(self, user_token: Optional[str], read_body: Callable[[], Json]) -> Json:
        user = self.install_token(user_token)
        with self.lock:
            now = time.monotonic()
            recent = [at for at in self.failed_claims.get(user, []) if now - at < CLAIM_WINDOW_SECONDS]
            self.failed_claims[user] = recent
            if len(recent) >= MAX_FAILED_CLAIMS:
                raise ApiError(429, ERR_TOO_MANY_CLAIMS)
        code = read_body().get("code")
        if not isinstance(code, str) or len(code) > 64 or not CODE_PATTERN.fullmatch(normalise_code(code)):
            with self.lock:
                self._count_failed_claim(user)
            raise ApiError(400, ERR_BAD_CODE)
        code = normalise_code(code)
        with self.lock:
            for device in self.by_id.values():
                if not device.claimed and device.code == code and not self._code_expired(device):
                    device.claimed = True
                    device.owner = user
                    return {"id": device.id, "kind": device.kind}
            self._count_failed_claim(user)
        raise ApiError(404, ERR_UNKNOWN_CODE)

    def _owned(self, device_id: str, user: str) -> Device:
        """The device a user's request is about. The lock must be held. A device that is
        someone else's, or nobody's, looks exactly like one that does not exist."""
        device = self.by_id.get(device_id)
        if device is None or not device.claimed or device.owner != user:
            raise ApiError(404, ERR_UNKNOWN_DEVICE)
        return device

    def list_devices(self, user_token: Optional[str]) -> Json:
        user = self.install_token(user_token)
        with self.lock:
            now = time.monotonic()
            return {"devices": [
                {"id": device.id, "kind": device.kind, "last_seen_ms_ago": int((now - device.last_seen) * 1000)}
                for device in self.by_id.values() if device.claimed and device.owner == user
            ]}

    def put_capsule(self, device_id: str, user_token: Optional[str], read_body: Callable[[], Json]) -> Json:
        user = self.install_token(user_token)
        with self.lock:
            self._owned(device_id, user)  # 404 before the body is looked at
        capsule = clean_capsule(read_body())
        with self.lock:
            device = self._owned(device_id, user)
            device.version += 1
            device.capsule = capsule
            device.action = None  # an action meant for the previous capsule must not hit this one
            return {"version": device.version}

    def post_action(self, device_id: str, user_token: Optional[str], read_body: Callable[[], Json]) -> Json:
        user = self.install_token(user_token)
        with self.lock:
            self._owned(device_id, user)
        action = read_body().get("action")
        if action not in ACTIONS:
            raise ApiError(400, mock_esp32.ERR_BAD_ACTION)
        with self.lock:
            device = self._owned(device_id, user)
            device.action_seq += 1
            device.action = action
            return {"action_seq": device.action_seq}

    def get_state(self, device_id: str, user_token: Optional[str]) -> Json:
        user = self.install_token(user_token)
        with self.lock:
            device = self._owned(device_id, user)
            answer = dict(device.state or {})
            answer["last_seen_ms_ago"] = int((time.monotonic() - device.last_seen) * 1000)
            return answer

    def unpair(self, device_id: str, user_token: Optional[str], host: Optional[str]) -> None:
        """The device keeps its id and token, loses its owner and what was queued for it, and
        gets a new code: the board shows a fresh QR code after its next poll."""
        user = self.install_token(user_token)
        with self.lock:
            device = self._owned(device_id, user)
            device.claimed = False
            device.owner = ""
            device.capsule = None
            device.action = None
            self._issue_code(device, host)


PAIR_PAGE = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pair your Harmoniser wrist companion</title>
<style>
  body {{ font: 1.1rem system-ui, sans-serif; max-width: 26rem; margin: 3rem auto; padding: 0 1rem; text-align: center; }}
  code {{ display: block; font-size: 1.5rem; margin: 1rem 0; }}
  button {{ font: inherit; padding: 0.8rem 1.6rem; border: 0; border-radius: 0.6rem; background: #00877a; color: #fff; }}
  button:disabled {{ background: #9aa0a6; }}
</style>
<h1>Harmoniser</h1>
<p>Pair the wrist companion that shows</p>
<code id="code" data-code="{code}">{code}</code>
<button id="pair">Pair this device</button>
<p id="result" role="status"></p>
<script>
  const button = document.getElementById("pair");
  const result = document.getElementById("result");
  // The app sends its own token. A browser makes one up and keeps it, under the same key
  // and of the same shape as the real site (32 random bytes, base64url).
  function deviceToken() {{
    let token = null;
    try {{ token = localStorage.getItem("harmoniser.deviceToken"); }} catch (error) {{}}
    if (!token || !/^[A-Za-z0-9_-]{{32,256}}$/.test(token)) {{
      const bytes = crypto.getRandomValues(new Uint8Array(32));
      token = btoa(String.fromCharCode(...bytes)).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
      try {{ localStorage.setItem("harmoniser.deviceToken", token); }} catch (error) {{}}
    }}
    return token;
  }}
  button.addEventListener("click", async () => {{
    button.disabled = true;
    result.textContent = "Pairing...";
    try {{
      const response = await fetch("/api/devices/claim", {{
        method: "POST",
        headers: {{"Content-Type": "application/json", "X-Harmoniser-Token": deviceToken()}},
        body: JSON.stringify({{code: document.getElementById("code").dataset.code}}),
      }});
      const answer = await response.json();
      if (response.ok) {{
        result.textContent = "Paired. The code on the wrist goes away within a few seconds.";
        return;
      }}
      result.textContent = "Not paired: " + answer.error.message;
    }} catch (error) {{
      result.textContent = "Not paired: the relay did not answer.";
    }}
    button.disabled = false;
  }});
</script>
</html>
"""

BAD_PAIR_PAGE = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Not a pairing code</title>
<p>This link has no pairing code in it. Scan the QR code on the wrist companion again,
or type the three words it shows into the app.</p>
</html>
"""


def pair_page(query: str) -> Tuple[int, str]:
    """The page GET /pair answers with: (status, HTML). It does not say whether the code is
    a live one; the claim does, when the button is pressed."""
    codes = parse_qs(query).get("code", [])
    code = normalise_code(codes[0]) if len(codes) == 1 and len(codes[0]) <= 64 else ""
    if not CODE_PATTERN.fullmatch(code):
        return 400, BAD_PAIR_PAGE
    return 200, PAIR_PAGE.format(code=html.escape(code, quote=True))


class Handler(BaseHTTPRequestHandler):
    server_version = "harmoniser-mock-relay"
    protocol_version = "HTTP/1.1"  # keep-alive: the board polls on one connection
    wbufsize = 65536  # headers and body leave in one packet; unbuffered, keep-alive costs 40 ms a request
    relay: Relay  # set in main()

    def _send(self, status: int, payload: Optional[Json]) -> None:
        data = b"" if payload is None else json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        self._send_bytes(status, "application/json", data, has_body=payload is not None)

    def _send_bytes(self, status: int, content_type: str, data: bytes, has_body: bool = True) -> None:
        self.send_response(status)
        if has_body:
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        # Never the body: the answer to a registration holds a token.
        log.info("%s %s -> %d", self.command, self.path, status)

    def _read_json_object(self) -> Json:
        self._body_read = True
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY_BYTES:
            self.close_connection = True  # the body, if there is one, stays unread
            if length < 0:
                raise ApiError(400, mock_esp32.ERR_BAD_LENGTH)
            raise ApiError(413, "body too large")
        return parse_json_object(self.rfile.read(length))

    def _routes(self, parts: List[str]) -> Dict[str, Tuple[int, Callable[[], Optional[Json]]]]:
        """Method -> (status on success, handler) for a path below /api/devices/."""
        relay, read = self.relay, self._read_json_object
        authorization = self.headers.get("Authorization")  # the board's
        user_token = self.headers.get(USER_TOKEN_HEADER)  # the app's
        host = self.headers.get("Host")
        if parts == ["register"]:
            return {"POST": (201, lambda: relay.register(read(), host))}
        if parts == ["claim"]:
            return {"POST": (200, lambda: relay.claim(user_token, read))}
        if len(parts) == 1 and parts[0]:
            return {"DELETE": (204, lambda: relay.unpair(parts[0], user_token, host))}
        if len(parts) != 2:
            return {}
        device_id, leaf = parts
        if leaf == "capsule":  # the board reads it, the user writes it
            return {
                "GET": (200, lambda: relay.poll(device_id, authorization, host)),
                "PUT": (200, lambda: relay.put_capsule(device_id, user_token, read)),
            }
        if leaf == "state":  # the board writes it, the user reads it
            return {
                "GET": (200, lambda: relay.get_state(device_id, user_token)),
                "POST": (204, lambda: relay.report(device_id, authorization, read)),
            }
        if leaf == "action":
            return {"POST": (200, lambda: relay.post_action(device_id, user_token, read))}
        return {}

    def _route(self) -> None:
        self._body_read = False
        try:
            url = urlsplit(self.path)
            path = url.path
            if path == "/pair":
                if self.command != "GET":
                    raise ApiError(405, "method not allowed")
                self._drop_unread_body()
                status, page = pair_page(url.query)
                self._send_bytes(status, "text/html; charset=utf-8", page.encode())
                return
            if path == "/api/devices":
                routes = {"GET": (200, lambda: self.relay.list_devices(self.headers.get(USER_TOKEN_HEADER)))}
            elif path.startswith("/api/devices/"):
                routes = self._routes(path[len("/api/devices/"):].split("/"))
            else:
                routes = {}
            if not routes:
                raise ApiError(404, "not found")
            if self.command not in routes:
                raise ApiError(405, "method not allowed")
            status, handler = routes[self.command]
            payload = handler()
            self._drop_unread_body()
            self._send(status, payload)
        except ApiError as error:
            self._drop_unread_body()
            self._send(error.status, error_body(error.status, error.message))
        except Exception:  # a bug in the mock: say so instead of dropping the connection
            log.exception("%s %s failed", self.command, self.path)
            self.close_connection = True
            self._send(500, error_body(500, "internal error"))

    def _drop_unread_body(self) -> None:
        # On a kept-alive connection an unread body would be taken for the next request.
        if not self._body_read and self.headers.get("Content-Length", "0") != "0":
            self.close_connection = True

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = _route

    def log_message(self, format: str, *args: Any) -> None:  # _send() logs one line per request
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Mock of the Harmoniser cloud device relay.")
    parser.add_argument("--host", default="0.0.0.0", help="address to listen on (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8090, help="port to listen on (default: 8090)")
    parser.add_argument("--code-ttl", type=float, default=CODE_TTL_SECONDS, metavar="SECONDS",
                        help="how long a pairing code works (default: 600)")
    parser.add_argument("--public-url", default="", metavar="URL",
                        help="base of pair_url (default: http://<Host header of the board's request>)")
    parser.add_argument("--quiet-polls", action="store_true",
                        help="do not log the board's polls and reports (one or two lines a second)")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    if args.quiet_polls:
        log.addFilter(lambda record: not _is_device_chatter(record))

    Handler.relay = Relay(args.code_ttl, args.public_url)
    ThreadingHTTPServer.daemon_threads = True
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("mock relay listening on http://%s:%d", args.host, args.port)
    address = mock_esp32.lan_address()
    if address:
        log.info("RELAY_URL for the board on this network: http://%s:%d", address, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("stopped")


def _is_device_chatter(record: logging.LogRecord) -> bool:
    text = record.getMessage()
    return (text.startswith("GET ") and "/capsule -> 200" in text) or (text.startswith("POST ") and "/state -> 204" in text)


if __name__ == "__main__":
    main()
