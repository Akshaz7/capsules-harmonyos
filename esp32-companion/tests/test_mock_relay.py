#!/usr/bin/env python3
"""Tests for mock_relay.py. Standard library only: python3 tests/test_mock_relay.py

They pin down the contract in RELAY.md as the fake implements it; test_relay.sh checks the
same flow from outside and can be pointed at the real backend.
"""

from __future__ import annotations

import http.client
import json
import logging
import sys
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import mock_relay  # noqa: E402
from mock_relay import Handler, Relay  # noqa: E402

SQUATS = {"type": "counter", "label": "Squats", "count": 3}
STATE = {"type": "counter", "label": "Squats", "count": 4, "seconds": 0, "remaining_seconds": 0,
         "running": False, "done": False, "motion": False, "version": 1}
INSTALL_ONE = "install-one-" + "a" * 24  # what the app sends in X-Harmoniser-Token: 32+ characters
INSTALL_TWO = "install-two-" + "b" * 24
Answer = Tuple[int, Any]


class RelayCase(unittest.TestCase):
    server: ThreadingHTTPServer
    install: Optional[str] = INSTALL_ONE  # the app's token; None: send no X-Harmoniser-Token

    @classmethod
    def setUpClass(cls) -> None:
        logging.disable(logging.CRITICAL)
        ThreadingHTTPServer.daemon_threads = True
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        logging.disable(logging.NOTSET)

    def setUp(self) -> None:
        Handler.relay = Relay()
        self.connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)

    def tearDown(self) -> None:
        self.connection.close()

    def request(self, method: str, path: str, body: Any = None, token: Optional[str] = None,
                headers: Optional[Dict[str, str]] = None) -> Answer:
        raw = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
        sent = dict(headers or {})
        if token is None and "Authorization" not in sent and "X-Harmoniser-Token" not in sent and self.install:
            sent["X-Harmoniser-Token"] = self.install  # a request from the app
        if token is not None:  # a request from the board
            sent["Authorization"] = "Bearer " + token
        try:
            self.connection.request(method, path, raw, sent)
            response = self.connection.getresponse()
        except (http.client.HTTPException, OSError):  # the fake closed a kept-alive connection
            self.connection.close()
            self.connection.request(method, path, raw, sent)
            response = self.connection.getresponse()
        data = response.read()
        self.content_type = response.getheader("Content-Type")
        if self.content_type and self.content_type.startswith("text/html"):
            return response.status, data.decode()
        return response.status, json.loads(data) if data else None

    def port(self) -> int:
        return int(self.server.server_address[1])

    def register(self, hw: str = "0123456789abcdef") -> Dict[str, str]:
        status, answer = self.request("POST", "/api/devices/register", {"hw": hw, "kind": "wrist", "fw": "test"})
        self.assertEqual(status, 201)
        return answer

    def claimed_device(self) -> Dict[str, str]:
        device = self.register()
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (200, {"id": device["id"], "kind": "wrist"}))
        return device

    def poll(self, device: Dict[str, str]) -> Dict[str, Any]:
        status, answer = self.request("GET", f"/api/devices/{device['id']}/capsule", token=device["token"])
        self.assertEqual(status, 200)
        return answer


class Registration(RelayCase):
    def test_register_answers_with_id_token_and_a_three_word_code(self) -> None:
        device = self.register()
        self.assertEqual(sorted(device), ["code", "id", "pair_url", "token"])
        self.assertRegex(device["code"], r"^[a-z]{3,5}-[a-z]{3,5}-[a-z]{3,5}$")
        self.assertLessEqual(len(device["code"]), 32)
        self.assertRegex(device["id"], r"^[A-Za-z0-9_-]{1,64}$")
        self.assertRegex(device["token"], r"^[A-Za-z0-9._~+/=-]{16,128}$")

    def test_a_new_device_is_unclaimed_and_has_nothing_to_show(self) -> None:
        device = self.register()
        self.assertEqual(self.poll(device), {"claimed": False, "version": 0, "capsule": None, "action_seq": 0,
                                             "action": None, "code": device["code"],
                                             "pair_url": device["pair_url"]})

    def test_registering_again_keeps_the_id_and_kills_the_old_token_and_code(self) -> None:
        first = self.claimed_device()
        self.request("PUT", f"/api/devices/{first['id']}/capsule", SQUATS)
        second = self.register()
        self.assertEqual(second["id"], first["id"])
        self.assertNotEqual(second["token"], first["token"])
        self.assertNotEqual(second["code"], first["code"])
        status, _ = self.request("GET", f"/api/devices/{first['id']}/capsule", token=first["token"])
        self.assertEqual(status, 401)
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": first["code"]})[0], 404)
        answer = self.poll(second)
        self.assertEqual((answer["claimed"], answer["capsule"]), (False, None))  # has to be claimed again

    def test_two_boards_get_two_devices(self) -> None:
        one, two = self.register("board-one"), self.register("board-two")
        self.assertNotEqual(one["id"], two["id"])
        self.assertNotEqual(one["code"], two["code"])

    def test_bad_registrations(self) -> None:
        for body, message in (
            ({"kind": "wrist", "fw": "1"}, mock_relay.ERR_BAD_HW),
            ({"hw": "", "kind": "wrist", "fw": "1"}, mock_relay.ERR_BAD_HW),
            ({"hw": "aa:bb:cc:dd:ee:ff", "kind": "wrist", "fw": "1"}, mock_relay.ERR_BAD_HW),  # a raw MAC
            ({"hw": "x" * 65, "kind": "wrist", "fw": "1"}, mock_relay.ERR_BAD_HW),
            ({"hw": "abc", "fw": "1"}, mock_relay.ERR_BAD_KIND),
            ({"hw": "abc", "kind": "wrist"}, mock_relay.ERR_BAD_FW),
            ({"hw": "abc", "kind": "wrist", "fw": 1}, mock_relay.ERR_BAD_FW),
        ):
            with self.subTest(body=body):
                self.assertEqual(self.request("POST", "/api/devices/register", body), (400, mock_relay.error_body(400, message)))
        self.assertEqual(self.request("POST", "/api/devices/register", b"[1]")[0], 400)
        self.assertEqual(self.request("POST", "/api/devices/register", b"{" * 300)[0], 400)
        self.assertEqual(self.request("POST", "/api/devices/register", b"x" * 1025)[0], 413)


class DeviceSide(RelayCase):
    def test_unknown_id_or_token_is_401(self) -> None:
        device = self.register()
        path = f"/api/devices/{device['id']}/capsule"
        unauthorized = (401, mock_relay.error_body(401, mock_relay.ERR_UNAUTHORIZED))
        self.assertEqual(self.request("GET", path, headers={"Authorization": ""}), unauthorized)
        self.assertEqual(self.request("GET", path, token="wrong"), unauthorized)
        self.assertEqual(self.request("GET", path, token=self.install), unauthorized)  # the app is not the board
        self.assertEqual(self.request("GET", path, token=device["token"] + "x"), unauthorized)
        self.assertEqual(self.request("GET", path, headers={"Authorization": "Basic " + device["token"]}),
                         unauthorized)
        # A device the relay has never heard of (it was restarted, say): 401, not 404.
        self.assertEqual(self.request("GET", "/api/devices/dev_gone/capsule", token=device["token"]), unauthorized)
        self.assertEqual(self.request("POST", "/api/devices/dev_gone/state", STATE, token=device["token"]),
                         unauthorized)
        self.assertEqual(self.request("POST", f"/api/devices/{device['id']}/state", STATE, token="wrong"),
                         unauthorized)

    def test_always_401_registers_but_refuses_every_device_request(self) -> None:
        Handler.relay = Relay(always_401=True)
        device = self.register()
        unauthorized = (401, mock_relay.error_body(401, mock_relay.ERR_UNAUTHORIZED))
        self.assertEqual(self.request("GET", f"/api/devices/{device['id']}/capsule", token=device["token"]),
                         unauthorized)
        self.assertEqual(self.request("POST", f"/api/devices/{device['id']}/state", STATE, token=device["token"]),
                         unauthorized)
        self.assertEqual(self.register()["id"], device["id"])  # and registering again still works

    def test_state_report_is_204_without_a_body(self) -> None:
        device = self.claimed_device()
        self.assertEqual(self.request("POST", f"/api/devices/{device['id']}/state", STATE, token=device["token"]),
                         (204, None))
        status, state = self.request("GET", f"/api/devices/{device['id']}/state")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(state.pop("last_seen_ms_ago"), 0)
        self.assertEqual(state, STATE)

    def test_bad_state_reports(self) -> None:
        device = self.claimed_device()
        path = f"/api/devices/{device['id']}/state"
        for body in (b"[]", b"{}", b'{"type":"counter"}', b'{"type":"counter","version":"1"}',
                     b'{"type":"counter","version":true}', b"not json"):
            with self.subTest(body=body):
                self.assertEqual(self.request("POST", path, body, token=device["token"])[0], 400)
        self.assertEqual(self.request("POST", path, b"x" * 2000, token=device["token"])[0], 413)
        self.assertEqual(self.request("GET", path)[1].keys(), {"last_seen_ms_ago"})  # nothing was stored

    def test_keep_alive_survives_a_204_and_an_error(self) -> None:
        device = self.claimed_device()
        socket_before = self.connection.sock
        self.request("POST", f"/api/devices/{device['id']}/state", STATE, token=device["token"])
        self.poll(device)
        self.request("GET", "/api/devices/dev_gone/capsule", token="x")
        self.poll(device)
        self.assertIs(self.connection.sock, socket_before)  # one connection throughout


class UserSide(RelayCase):
    def test_claim(self) -> None:
        device = self.register()
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": "not-the-code"}),
                         (404, mock_relay.error_body(404, mock_relay.ERR_UNKNOWN_CODE)))
        for bad in ({"code": 123456}, {"code": "123456"}, {"code": "brave-otter"}, {"code": "a-b-c"},
                    {"code": "brave-otter-lamp-drum"}, {"code": "brave_otter_lamp"}, {"code": ""},
                    {"code": "x" * 200}, {}):
            with self.subTest(body=bad):
                self.assertEqual(self.request("POST", "/api/devices/claim", bad),
                                 (400, mock_relay.error_body(400, mock_relay.ERR_BAD_CODE)))
        self.assertFalse(self.poll(device)["claimed"])
        Handler.relay.failed_claims.clear()  # that was ten wrong codes: see test_too_many_wrong_codes_get_429
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (200, {"id": device["id"], "kind": "wrist"}))
        answer = self.poll(device)
        self.assertEqual((answer["claimed"], answer["code"], answer["pair_url"]), (True, None, None))
        # A code works once.
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]})[0], 404)

    def test_claim_takes_the_phrase_as_a_person_types_it(self) -> None:
        for number, typed in enumerate((str.upper, str.title, lambda code: code.replace("-", " "),
                                        lambda code: "  " + code.replace("-", "  ").title() + " ",
                                        lambda code: code.replace("-", " - "))):
            device = self.register(f"board-{number}")
            with self.subTest(typed=typed(device["code"])):
                self.assertEqual(self.request("POST", "/api/devices/claim", {"code": typed(device["code"])}),
                                 (200, {"id": device["id"], "kind": "wrist"}))

    def test_a_code_expires_and_the_board_is_given_a_new_one(self) -> None:
        device = self.register()
        relay_device = Handler.relay.by_id[device["id"]]
        relay_device.code_issued -= mock_relay.CODE_TTL_SECONDS - 5
        self.assertEqual(self.poll(device)["code"], device["code"])  # 5 seconds left: still the same
        relay_device.code_issued -= 5
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (404, mock_relay.error_body(404, mock_relay.ERR_UNKNOWN_CODE)))
        fresh = self.poll(device)["code"]
        self.assertNotEqual(fresh, device["code"])
        self.assertRegex(fresh, r"^[a-z]{3,5}-[a-z]{3,5}-[a-z]{3,5}$")
        self.assertEqual(self.poll(device)["pair_url"], f"http://127.0.0.1:{self.port()}/pair?code={fresh}")
        self.assertEqual(self.poll(device)["code"], fresh)  # and it stays for its own 10 minutes
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]})[0], 404)
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": fresh}), (200, {"id": device["id"], "kind": "wrist"}))

    def test_a_claimed_device_keeps_its_owner_when_the_old_code_would_have_expired(self) -> None:
        device = self.claimed_device()
        Handler.relay.by_id[device["id"]].code_issued -= 2 * mock_relay.CODE_TTL_SECONDS
        answer = self.poll(device)
        self.assertEqual((answer["claimed"], answer["code"]), (True, None))

    def test_user_routes_need_a_device_this_install_claimed(self) -> None:
        device = self.register()
        base = f"/api/devices/{device['id']}"
        no_device = (404, mock_relay.error_body(404, mock_relay.ERR_UNKNOWN_DEVICE))

        def refused_everywhere(what: str) -> None:
            with self.subTest(what=what):
                self.assertEqual(self.request("PUT", base + "/capsule", SQUATS), no_device)
                self.assertEqual(self.request("POST", base + "/action", {"action": "increment"}), no_device)
                self.assertEqual(self.request("GET", base + "/state"), no_device)
                self.assertEqual(self.request("DELETE", base), no_device)
                self.assertEqual(self.request("GET", "/api/devices"), (200, {"devices": []}))

        refused_everywhere("not claimed by anyone")
        self.assertEqual(self.poll(device)["version"], 0)
        self.request("POST", "/api/devices/claim", {"code": device["code"]})
        self.assertEqual(self.request("PUT", base + "/capsule", SQUATS), (200, {"version": 1}))
        self.install = INSTALL_TWO
        refused_everywhere("claimed by another install")  # and it looks no different from "no such device"
        self.assertEqual(self.poll(device)["version"], 1)
        base = "/api/devices/dev_gone"
        refused_everywhere("no such device")

    def test_user_routes_need_an_install_token(self) -> None:
        device = self.claimed_device()
        base = f"/api/devices/{device['id']}"
        self.install = None
        missing = (401, mock_relay.error_body(401, mock_relay.ERR_NO_INSTALL_TOKEN))
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": "brave-otter-lamp"}), missing)
        self.assertEqual(self.request("GET", "/api/devices"), missing)
        self.assertEqual(self.request("PUT", base + "/capsule", SQUATS), missing)
        self.assertEqual(self.request("POST", base + "/action", {"action": "reset"}), missing)
        self.assertEqual(self.request("GET", base + "/state"), missing)
        self.assertEqual(self.request("DELETE", base), missing)
        # The old way, and the board's token, are not the app's token.
        self.assertEqual(self.request("GET", base + "/state", headers={"Authorization": "Bearer " + INSTALL_ONE}),
                         missing)
        self.assertEqual(self.request("GET", base + "/state", token=device["token"]), missing)
        for malformed in ("", "short", "a" * 31, "a" * 257, "a" * 31 + "!", "a" * 20 + " " + "a" * 20):
            with self.subTest(token=malformed):
                self.assertEqual(self.request("GET", base + "/state", headers={"X-Harmoniser-Token": malformed}),
                                 missing)
        for fine in ("a" * 32, "A-b_9" * 51 + "x"):  # 32 and 256 characters
            with self.subTest(token=fine):  # well-formed, but not the one that claimed the device
                self.assertEqual(self.request("GET", base + "/state", headers={"X-Harmoniser-Token": fine})[0], 404)

    def test_list_devices(self) -> None:
        first = self.claimed_device()
        second = self.register("board-two")
        self.request("POST", "/api/devices/claim", {"code": second["code"]})
        self.register("board-three")  # never claimed: not listed
        status, answer = self.request("GET", "/api/devices")
        self.assertEqual(status, 200)
        self.assertEqual([(device["id"], device["kind"]) for device in answer["devices"]],
                         [(first["id"], "wrist"), (second["id"], "wrist")])
        self.assertGreaterEqual(answer["devices"][0]["last_seen_ms_ago"], 0)
        self.install = INSTALL_TWO
        self.assertEqual(self.request("GET", "/api/devices"), (200, {"devices": []}))

    def test_unpair_gives_the_board_a_fresh_code(self) -> None:
        device = self.claimed_device()
        base = f"/api/devices/{device['id']}"
        self.request("PUT", base + "/capsule", SQUATS)
        self.request("POST", base + "/action", {"action": "increment"})
        self.assertEqual(self.request("DELETE", base), (204, None))
        answer = self.poll(device)  # same token: the board is not thrown out, it is only unpaired
        self.assertEqual((answer["claimed"], answer["capsule"], answer["action"]), (False, None, None))
        self.assertNotEqual(answer["code"], device["code"])
        self.assertEqual(answer["pair_url"], f"http://127.0.0.1:{self.port()}/pair?code={answer['code']}")
        self.assertEqual(self.request("GET", base + "/state")[0], 404)
        self.assertEqual(self.request("GET", "/api/devices"), (200, {"devices": []}))
        self.assertEqual(self.request("DELETE", base)[0], 404)
        # Anyone can pair it again with the new code.
        self.install = INSTALL_TWO
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": answer["code"]}),
                         (200, {"id": device["id"], "kind": "wrist"}))

    def test_too_many_wrong_codes_get_429(self) -> None:
        device = self.register()
        for _ in range(mock_relay.MAX_FAILED_CLAIMS):
            self.assertEqual(self.request("POST", "/api/devices/claim", {"code": "not-the-code"})[0], 404)
        too_many = (429, mock_relay.error_body(429, mock_relay.ERR_TOO_MANY_CLAIMS))
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": "not-the-code"}), too_many)
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}), too_many)  # even the right one
        self.assertFalse(self.poll(device)["claimed"])
        # Another install is not held up, and the first is let in again after the window.
        self.install = INSTALL_TWO
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": "not-the-code"})[0], 404)
        self.install = INSTALL_ONE
        Handler.relay.failed_claims[INSTALL_ONE] = [
            at - mock_relay.CLAIM_WINDOW_SECONDS for at in Handler.relay.failed_claims[INSTALL_ONE]]
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]})[0], 200)

    def test_put_capsule_bumps_the_version_and_reaches_the_board(self) -> None:
        device = self.claimed_device()
        path = f"/api/devices/{device['id']}/capsule"
        self.assertEqual(self.request("PUT", path, SQUATS), (200, {"version": 1}))
        answer = self.poll(device)
        self.assertEqual((answer["version"], answer["capsule"]), (1, SQUATS))
        timer = {"type": "timer", "label": "Pasta", "seconds": 540}
        self.assertEqual(self.request("PUT", path, timer), (200, {"version": 2}))
        self.assertEqual(self.poll(device)["capsule"], timer)
        # The extras are passed on when given, and unknown fields are not.
        self.request("PUT", path, {**timer, "running": False, "colour": "red"})
        self.assertEqual(self.poll(device)["capsule"], {**timer, "running": False})
        self.request("PUT", path, {"type": "counter", "motion": True})
        self.assertEqual(self.poll(device)["capsule"], {"type": "counter", "label": "", "count": 0, "motion": True})

    def test_put_capsule_applies_the_boards_rules(self) -> None:
        device = self.claimed_device()
        path = f"/api/devices/{device['id']}/capsule"
        self.request("PUT", path, SQUATS)
        for body, message in (
            ({"type": "stopwatch"}, mock_relay.mock_esp32.ERR_BAD_TYPE),
            ({"type": "timer", "label": "x"}, mock_relay.mock_esp32.ERR_BAD_SECONDS),
            ({"type": "timer", "seconds": 0}, mock_relay.mock_esp32.ERR_BAD_SECONDS),
            ({"type": "timer", "seconds": 360000}, mock_relay.mock_esp32.ERR_BAD_SECONDS),
            ({"type": "counter", "count": -1}, mock_relay.mock_esp32.ERR_BAD_COUNT),
            ({"type": "counter", "label": 7}, mock_relay.mock_esp32.ERR_BAD_LABEL),
            ({"type": "timer", "seconds": 5, "running": "yes"}, mock_relay.mock_esp32.ERR_BAD_RUNNING),
        ):
            with self.subTest(body=body):
                self.assertEqual(self.request("PUT", path, body), (400, mock_relay.error_body(400, message)))
        self.assertEqual(self.request("PUT", path, b'{"type":"counter","x":[[[[[[[[1]]]]]]]]}')[0], 400)
        answer = self.poll(device)
        self.assertEqual((answer["version"], answer["capsule"]), (1, SQUATS))  # a refused PUT changes nothing
        # A long label is cut the way the board cuts it.
        self.request("PUT", path, {"type": "counter", "label": "é" * 40})
        self.assertEqual(self.poll(device)["capsule"]["label"], "é" * 23)

    def test_actions(self) -> None:
        device = self.claimed_device()
        base = f"/api/devices/{device['id']}"
        self.request("PUT", base + "/capsule", SQUATS)
        self.assertEqual(self.request("POST", base + "/action", {"action": "increment"}), (200, {"action_seq": 1}))
        answer = self.poll(device)
        self.assertEqual((answer["action_seq"], answer["action"]), (1, "increment"))
        self.assertEqual(self.poll(device)["action_seq"], 1)  # reading it does not use it up
        self.assertEqual(self.request("POST", base + "/action", {"action": "increment"}), (200, {"action_seq": 2}))
        for bad in ({"action": "explode"}, {"action": 1}, {}):
            with self.subTest(body=bad):
                self.assertEqual(self.request("POST", base + "/action", bad)[0], 400)
        self.assertEqual(self.poll(device)["action_seq"], 2)
        # A new capsule drops the pending action but never reuses its number.
        self.request("PUT", base + "/capsule", SQUATS)
        answer = self.poll(device)
        self.assertEqual((answer["action_seq"], answer["action"]), (2, None))
        self.assertEqual(self.request("POST", base + "/action", {"action": "reset"}), (200, {"action_seq": 3}))

    def test_last_seen_follows_the_boards_requests(self) -> None:
        device = self.claimed_device()
        relay_device = Handler.relay.by_id[device["id"]]
        relay_device.last_seen -= 60
        status, state = self.request("GET", f"/api/devices/{device['id']}/state")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(state["last_seen_ms_ago"], 60000)
        self.poll(device)
        self.assertLess(self.request("GET", f"/api/devices/{device['id']}/state")[1]["last_seen_ms_ago"], 5000)


class PairPage(RelayCase):
    def test_pair_url_points_at_the_fake_by_the_address_the_board_used(self) -> None:
        device = self.register()
        self.assertEqual(device["pair_url"], f"http://127.0.0.1:{self.port()}/pair?code={device['code']}")
        self.assertLessEqual(len(device["pair_url"]), 200)
        status, answer = self.request("POST", "/api/devices/register", {"hw": "b2", "kind": "wrist", "fw": "1"},
                                      headers={"Host": "relay.example:8090"})
        self.assertEqual(answer["pair_url"], f"http://relay.example:8090/pair?code={answer['code']}")

    def test_a_host_header_that_is_not_a_host_is_not_echoed(self) -> None:
        _, answer = self.request("POST", "/api/devices/register", {"hw": "b3", "kind": "wrist", "fw": "1"},
                                 headers={"Host": "evil.example/x?y=<script>"})
        self.assertEqual(answer["pair_url"], f"http://localhost/pair?code={answer['code']}")

    def test_public_url_overrides_the_host_header(self) -> None:
        Handler.relay = Relay(public_url="https://relay.example/")
        device = self.register()
        self.assertEqual(device["pair_url"], f"https://relay.example/pair?code={device['code']}")

    def test_the_page_from_the_qr_code_claims_the_device(self) -> None:
        device = self.register()
        status, page = self.request("GET", device["pair_url"][len(f"http://127.0.0.1:{self.port()}"):])
        self.assertEqual(status, 200)
        self.assertEqual(self.content_type, "text/html; charset=utf-8")
        self.assertIn("Pair this device", page)
        self.assertIn(f'data-code="{device["code"]}"', page)
        self.assertIn('fetch("/api/devices/claim"', page)
        self.assertIn('"X-Harmoniser-Token": deviceToken()', page)
        self.assertIn('localStorage.getItem("harmoniser.deviceToken")', page)
        self.assertNotIn("Bearer", page)
        self.assertFalse(self.poll(device)["claimed"])  # opening the page pairs nothing; the button does
        # What the button sends:
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (200, {"id": device["id"], "kind": "wrist"}))

    def test_the_page_takes_the_code_as_typed_and_does_not_say_whether_it_is_live(self) -> None:
        status, page = self.request("GET", "/pair?code=Brave%20Otter%20Lamp")
        self.assertEqual(status, 200)
        self.assertIn('data-code="brave-otter-lamp"', page)

    def test_the_page_refuses_what_is_not_a_code(self) -> None:
        for query in ("", "?code=", "?code=123456", "?code=a-b", "?code=%3Cscript%3Ealert(1)%3C/script%3E",
                      "?code=%22onmouseover%3D%22x", "?code=brave-otter-lamp&code=calm-owl-jar", "?code=" + "a" * 500):
            with self.subTest(query=query):
                status, page = self.request("GET", "/pair" + query)
                self.assertEqual(status, 400)
                self.assertNotIn("script>alert", page)
                self.assertNotIn("onmouseover", page)
                self.assertNotIn("Pair this device", page)
        self.assertEqual(self.request("POST", "/pair?code=brave-otter-lamp", {}),
                         (405, mock_relay.error_body(405, "method not allowed")))


class Words(unittest.TestCase):
    def test_the_word_list_is_big_enough_and_every_word_fits_the_contract(self) -> None:
        self.assertGreaterEqual(len(mock_relay.WORDS), 256)
        self.assertEqual(len(set(mock_relay.WORDS)), len(mock_relay.WORDS))
        for word in mock_relay.WORDS:
            self.assertRegex(word, r"^[a-z]{3,5}$")

    def test_words_that_sound_like_another_word_are_not_in_it(self) -> None:
        sound_alikes = {"bear", "bare", "pear", "pair", "sea", "see", "sun", "son", "deer", "dear", "flour",
                        "night", "knight", "mail", "male", "tail", "tale", "steel", "steal", "rose", "week",
                        "weak", "wood", "bee", "two", "four", "eight", "red", "read", "blue", "new", "sail",
                        "sale", "meat", "meet", "rain", "wait", "whale", "peak", "piece", "peace", "toad",
                        "plum", "berry", "bean", "beet", "leek", "tea", "fir", "fur", "ring", "write", "right"}
        self.assertEqual(sound_alikes & set(mock_relay.WORDS), set())

    def test_normalise_code(self) -> None:
        for typed in ("brave-otter-lamp", "Brave Otter Lamp", " BRAVE  otter - Lamp ", "brave\totter\nlamp"):
            self.assertEqual(mock_relay.normalise_code(typed), "brave-otter-lamp")


class ErrorShape(RelayCase):
    def test_errors_use_the_backends_envelope_and_codes(self) -> None:
        device = self.claimed_device()
        base = f"/api/devices/{device['id']}"
        other = self.register("board-two")
        for expected_status, code, method, path, body in (
            (400, "invalid_code", "POST", "/api/devices/claim", {"code": "nope"}),
            (404, "code_not_found", "POST", "/api/devices/claim", {"code": "not-the-code"}),
            (400, "invalid_capsule", "PUT", base + "/capsule", {"type": "timer"}),
            (400, "invalid_capsule", "PUT", base + "/capsule", {"type": "stopwatch"}),
            (400, "invalid_json", "PUT", base + "/capsule", b"[1]"),
            (400, "invalid_json", "PUT", base + "/capsule", b"{" * 300),
            (413, "payload_too_large", "PUT", base + "/capsule", b"x" * 2000),
            (400, "invalid_action", "POST", base + "/action", {"action": "explode"}),
            (404, "not_found", "GET", f"/api/devices/{other['id']}/state", None),
            (404, "not_found", "GET", "/nope", None),
            (405, "method_not_allowed", "PATCH", base + "/capsule", None),
            (400, "invalid_registration", "POST", "/api/devices/register", {"hw": "", "kind": "wrist", "fw": "1"}),
        ):
            with self.subTest(code=code, path=path):
                status, answer = self.request(method, path, body)
                self.assertEqual((status, answer["error"]["code"]), (expected_status, code))
                self.assertEqual(sorted(answer["error"]), ["code", "message"])
                self.assertIsInstance(answer["error"]["message"], str)
        self.install = None
        status, answer = self.request("GET", base + "/state")
        self.assertEqual((status, answer["error"]["code"]), (401, "unauthorized"))
        status, answer = self.request("GET", base + "/capsule", token="wrong")  # the board's side too
        self.assertEqual((status, answer["error"]["code"]), (401, "unauthorized"))

    def test_too_many_wrong_codes_is_rate_limited(self) -> None:
        for _ in range(mock_relay.MAX_FAILED_CLAIMS):
            self.request("POST", "/api/devices/claim", {"code": "not-the-code"})
        status, answer = self.request("POST", "/api/devices/claim", {"code": "not-the-code"})
        self.assertEqual((status, answer["error"]["code"]), (429, "rate_limited"))


class Routing(RelayCase):
    def test_unknown_paths_and_wrong_methods(self) -> None:
        device = self.register()
        not_found = (404, mock_relay.error_body(404, "not found"))
        wrong_method = (405, mock_relay.error_body(405, "method not allowed"))
        for path in ("/", "/state", "/api/device", "/api/devices/", f"/api/devices/{device['id']}/nope", f"/api/devices/{device['id']}/capsule/x"):
            with self.subTest(path=path):
                self.assertEqual(self.request("GET", path), not_found)
        self.assertEqual(self.request("GET", "/api/devices/register"), wrong_method)
        self.assertEqual(self.request("PUT", "/api/devices/claim", {"code": device["code"]}), wrong_method)
        self.assertEqual(self.request("DELETE", f"/api/devices/{device['id']}/capsule"), wrong_method)
        self.assertEqual(self.request("PUT", f"/api/devices/{device['id']}/state", {}), wrong_method)
        self.assertEqual(self.request("POST", "/api/devices", {}), wrong_method)
        self.assertEqual(self.request("GET", f"/api/devices/{device['id']}"), wrong_method)
        self.assertEqual(self.request("GET", f"/api/devices/{device['id']}/action"), wrong_method)

    def test_the_log_never_holds_a_token(self) -> None:
        logging.disable(logging.NOTSET)
        try:
            with self.assertLogs("mock_relay", level="INFO") as captured:
                device = self.register()
                self.poll(device)
        finally:
            logging.disable(logging.CRITICAL)
        self.assertTrue(captured.output)
        self.assertFalse([line for line in captured.output if device["token"] in line])


if __name__ == "__main__":
    unittest.main()
