#!/usr/bin/env python3
"""Stand-in for the Harmoniser wrist companion (ESP32-S3), for wiring the app without hardware.

Same HTTP API, same JSON and same status codes as the firmware in main/ (see README.md):

    POST /capsule   {"type":"timer","label":"Pasta","seconds":540}
                    {"type":"counter","label":"Squats","count":0}
    GET  /state     {"type","label","count","seconds","remaining_seconds","running","done","motion"}
    POST /action    {"action":"start|pause|toggle|reset|increment|motion_on|motion_off"}

Python 3.8+, standard library only:

    python3 mock_esp32.py                 # listens on 0.0.0.0:8080
    python3 mock_esp32.py --port 9000

The real board serves on port 80. The mock has no motion sensor, so while a counter is in
motion mode it adds one rep every --motion-interval seconds (0 switches that off).
"""

from __future__ import annotations

import argparse
import json
import logging
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, Optional, Tuple
from urllib.parse import urlsplit

LABEL_MAX_BYTES = 47  # UTF-8 bytes; longer labels are cut, as on the board
MAX_SECONDS = 359999  # 99:59:59
MAX_COUNT = 999999
MAX_BODY_BYTES = 1024

ERR_BAD_JSON = "body must be a JSON object"
ERR_BAD_TYPE = 'type must be "timer" or "counter"'
ERR_BAD_LABEL = "label must be a string"
ERR_BAD_SECONDS = "seconds must be a number from 1 to 359999"
ERR_BAD_COUNT = "count must be a number from 0 to 999999"
ERR_BAD_RUNNING = "running must be true or false"
ERR_BAD_MOTION = "motion must be true or false"
ERR_BAD_ACTION = "action must be one of start, pause, toggle, reset, increment, motion_on, motion_off"
ERR_WRONG_CAPSULE = "action does not apply to the current capsule"

TIMER_ACTIONS = ("start", "pause", "toggle", "reset")
COUNTER_ACTIONS = ("increment", "reset", "motion_on", "motion_off")

Json = Dict[str, Any]
log = logging.getLogger("mock_esp32")


class ApiError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def cut_label(label: str) -> str:
    raw = label.encode("utf-8")
    end = len(raw)
    if end > LABEL_MAX_BYTES:
        end = LABEL_MAX_BYTES
        while end > 0 and (raw[end] & 0xC0) == 0x80:  # do not cut a UTF-8 sequence in half
            end -= 1
    return raw[:end].decode("utf-8")


def read_int(body: Json, key: str, low: int, high: int, default: Optional[int], error: str) -> Optional[int]:
    if key not in body:
        return default
    value = body[key]
    is_number = isinstance(value, (int, float)) and not isinstance(value, bool)
    if not is_number or not low <= value <= high:
        raise ApiError(400, error)
    return int(value)


def read_bool(body: Json, key: str, default: bool, error: str) -> bool:
    value = body.get(key, default)
    if not isinstance(value, bool):
        raise ApiError(400, error)
    return value


class Capsule:
    """The one capsule the wrist shows. Mirrors main/capsule.c."""

    def __init__(self, motion_interval: float) -> None:
        self.lock = threading.Lock()
        self.motion_interval = motion_interval
        self._clear("idle", "")

    def _clear(self, kind: str, label: str) -> None:
        self.type = kind
        self.label = cut_label(label)
        self.count = 0
        self.seconds = 0
        self.remaining = 0.0  # timer: seconds left while paused
        self.deadline = 0.0  # timer: monotonic time at which it ends while running
        self.running = False
        self.done = False
        self.motion = False
        self.last_rep = 0.0

    def _sync(self) -> None:
        """Nothing ticks in the background: catch up whenever the state is read or changed."""
        now = time.monotonic()
        if self.type == "timer" and self.running and now >= self.deadline:
            self.remaining = 0.0
            self.running = False
            self.done = True
        if self.type == "counter" and self.motion and self.motion_interval > 0:
            reps = int((now - self.last_rep) / self.motion_interval)
            self.count = min(MAX_COUNT, self.count + reps)
            self.last_rep += reps * self.motion_interval

    def _timer_reset(self) -> None:
        self.remaining = float(self.seconds)
        self.running = False
        self.done = False

    def _timer_start(self) -> None:
        if self.done:
            self._timer_reset()
        if not self.running:
            self.deadline = time.monotonic() + self.remaining
            self.running = True

    def _timer_pause(self) -> None:
        if self.running:
            self.remaining = max(0.001, self.deadline - time.monotonic())
            self.running = False

    def _timer_action(self, action: str) -> None:
        if action == "start":
            self._timer_start()
        elif action == "pause":
            self._timer_pause()
        elif action == "reset":
            self._timer_reset()
        elif self.done:  # toggle
            self._timer_reset()
        elif self.running:
            self._timer_pause()
        else:
            self._timer_start()

    def _counter_action(self, action: str) -> None:
        if action == "increment":
            self.count = min(MAX_COUNT, self.count + 1)
        elif action == "reset":
            self.count = 0
        elif action == "motion_on":
            if not self.motion:
                self.last_rep = time.monotonic()
            self.motion = True
        else:
            self.motion = False

    def _state(self) -> Json:
        remaining = 0
        if self.type == "timer":
            left = self.deadline - time.monotonic() if self.running else self.remaining
            remaining = max(0, int((left * 1000 + 999) // 1000))  # rounded up to whole seconds
        return {
            "type": self.type,
            "label": self.label,
            "count": self.count,
            "seconds": self.seconds,
            "remaining_seconds": remaining,
            "running": self.running,
            "done": self.done,
            "motion": self.motion,
        }

    def state(self) -> Json:
        with self.lock:
            self._sync()
            return self._state()

    def set_capsule(self, body: Json) -> Json:
        kind = body.get("type")
        label = body.get("label", "")
        if kind not in ("timer", "counter"):
            raise ApiError(400, ERR_BAD_TYPE)
        if not isinstance(label, str):
            raise ApiError(400, ERR_BAD_LABEL)
        if kind == "timer":
            seconds = read_int(body, "seconds", 1, MAX_SECONDS, None, ERR_BAD_SECONDS)
            if seconds is None:
                raise ApiError(400, ERR_BAD_SECONDS)
            running = read_bool(body, "running", True, ERR_BAD_RUNNING)
            with self.lock:
                self._clear(kind, label)
                self.seconds = seconds
                self._timer_reset()
                if running:
                    self._timer_start()
                return self._state()
        count = read_int(body, "count", 0, MAX_COUNT, 0, ERR_BAD_COUNT)
        motion = read_bool(body, "motion", False, ERR_BAD_MOTION)
        with self.lock:
            self._clear(kind, label)
            self.count = count or 0
            self.motion = motion
            self.last_rep = time.monotonic()
            return self._state()

    def apply(self, body: Json) -> Json:
        action = body.get("action")
        if action not in TIMER_ACTIONS and action not in COUNTER_ACTIONS:
            raise ApiError(400, ERR_BAD_ACTION)
        with self.lock:
            self._sync()
            if self.type == "timer" and action in TIMER_ACTIONS:
                self._timer_action(action)
            elif self.type == "counter" and action in COUNTER_ACTIONS:
                self._counter_action(action)
            else:
                raise ApiError(409, ERR_WRONG_CAPSULE)
            return self._state()


class Handler(BaseHTTPRequestHandler):
    server_version = "harmoniser-mock"
    capsule: Capsule  # set in main()

    def _send(self, status: int, payload: Json) -> None:
        data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        log.info("%s %s -> %d %s", self.command, self.path, status, data.decode("utf-8"))

    def _read_json_object(self) -> Json:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise ApiError(400, ERR_BAD_JSON)
        if length > MAX_BODY_BYTES:
            self.close_connection = True
            raise ApiError(413, "body too large")
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:  # bad UTF-8 or bad JSON
            raise ApiError(400, ERR_BAD_JSON)
        if not isinstance(body, dict):
            raise ApiError(400, ERR_BAD_JSON)
        return body

    def _screenshot(self) -> Json:
        raise ApiError(503, "display not available")  # the board answers with a BMP

    def _route(self) -> None:
        routes: Dict[str, Tuple[str, Callable[[], Json]]] = {
            "/state": ("GET", self.capsule.state),
            "/capsule": ("POST", lambda: self.capsule.set_capsule(self._read_json_object())),
            "/action": ("POST", lambda: self.capsule.apply(self._read_json_object())),
            "/screenshot": ("GET", self._screenshot),
        }
        try:
            method, handler = routes.get(urlsplit(self.path).path, ("", None))
            if handler is None:
                raise ApiError(404, "not found")
            if method != self.command:
                raise ApiError(405, "method not allowed")
            self._send(200, handler())
        except ApiError as error:
            self._send(error.status, {"error": error.message})

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _route

    def log_message(self, format: str, *args: Any) -> None:  # _send() logs one line per request
        pass


def lan_address() -> Optional[str]:
    """Best guess at this machine's LAN address, for the start-up hint. Sends nothing."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 9))
            return str(probe.getsockname()[0])
    except OSError:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Mock of the Harmoniser ESP32 wrist companion HTTP API.")
    parser.add_argument("--host", default="0.0.0.0", help="address to listen on (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="port to listen on (default: 8080)")
    parser.add_argument("--motion-interval", type=float, default=2.0, metavar="SECONDS",
                        help="in motion mode, add a rep this often (default: 2.0, 0 = never)")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    Handler.capsule = Capsule(args.motion_interval)
    ThreadingHTTPServer.daemon_threads = True
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("mock ESP32 listening on http://%s:%d", args.host, args.port)
    address = lan_address()
    if address:
        log.info("from other devices on this network: http://%s:%d", address, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("stopped")


if __name__ == "__main__":
    main()
