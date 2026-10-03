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
Answer = Tuple[int, Any]


class RelayCase(unittest.TestCase):
    server: ThreadingHTTPServer

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
        if token is not None:
            sent["Authorization"] = "Bearer " + token
        try:
            self.connection.request(method, path, raw, sent)
            response = self.connection.getresponse()
        except (http.client.HTTPException, OSError):  # the fake closed a kept-alive connection
            self.connection.close()
            self.connection.request(method, path, raw, sent)
            response = self.connection.getresponse()
        data = response.read()
        return response.status, json.loads(data) if data else None

    def register(self, hw: str = "0123456789abcdef") -> Dict[str, str]:
        status, answer = self.request("POST", "/api/devices/register", {"hw": hw, "kind": "wrist", "fw": "test"})
        self.assertEqual(status, 201)
        return answer

    def claimed_device(self) -> Dict[str, str]:
        device = self.register()
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (200, {"id": device["id"]}))
        return device

    def poll(self, device: Dict[str, str]) -> Dict[str, Any]:
        status, answer = self.request("GET", f"/api/devices/{device['id']}/capsule", token=device["token"])
        self.assertEqual(status, 200)
        return answer


class Registration(RelayCase):
    def test_register_answers_with_id_token_and_a_three_word_code(self) -> None:
        device = self.register()
        self.assertEqual(sorted(device), ["code", "id", "token"])
        self.assertRegex(device["code"], r"^[a-z]{3,5}-[a-z]{3,5}-[a-z]{3,5}$")
        self.assertLessEqual(len(device["code"]), 32)
        self.assertRegex(device["id"], r"^[A-Za-z0-9_-]{1,64}$")
        self.assertRegex(device["token"], r"^[A-Za-z0-9._~+/=-]{16,128}$")

    def test_a_new_device_is_unclaimed_and_has_nothing_to_show(self) -> None:
        device = self.register()
        self.assertEqual(self.poll(device), {"claimed": False, "version": 0, "capsule": None, "action_seq": 0,
                                             "action": None, "code": device["code"]})

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
                self.assertEqual(self.request("POST", "/api/devices/register", body), (400, {"error": message}))
        self.assertEqual(self.request("POST", "/api/devices/register", b"[1]")[0], 400)
        self.assertEqual(self.request("POST", "/api/devices/register", b"{" * 300)[0], 400)
        self.assertEqual(self.request("POST", "/api/devices/register", b"x" * 1025)[0], 413)


class DeviceSide(RelayCase):
    def test_unknown_id_or_token_is_401(self) -> None:
        device = self.register()
        path = f"/api/devices/{device['id']}/capsule"
        unauthorized = (401, {"error": mock_relay.ERR_UNAUTHORIZED})
        self.assertEqual(self.request("GET", path), unauthorized)
        self.assertEqual(self.request("GET", path, token="wrong"), unauthorized)
        self.assertEqual(self.request("GET", path, token=device["token"] + "x"), unauthorized)
        self.assertEqual(self.request("GET", path, headers={"Authorization": "Basic " + device["token"]}),
                         unauthorized)
        # A device the relay has never heard of (it was restarted, say): 401, not 404.
        self.assertEqual(self.request("GET", "/api/devices/dev_gone/capsule", token=device["token"]), unauthorized)
        self.assertEqual(self.request("POST", "/api/devices/dev_gone/state", STATE, token=device["token"]),
                         unauthorized)
        self.assertEqual(self.request("POST", f"/api/devices/{device['id']}/state", STATE, token="wrong"),
                         unauthorized)

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
                         (404, {"error": mock_relay.ERR_UNKNOWN_CODE}))
        for bad in ({"code": 123456}, {"code": "123456"}, {"code": "brave-otter"}, {"code": "a-b-c"},
                    {"code": "brave-otter-lamp-drum"}, {"code": "brave_otter_lamp"}, {"code": ""},
                    {"code": "x" * 200}, {}):
            with self.subTest(body=bad):
                self.assertEqual(self.request("POST", "/api/devices/claim", bad),
                                 (400, {"error": mock_relay.ERR_BAD_CODE}))
        self.assertFalse(self.poll(device)["claimed"])
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (200, {"id": device["id"]}))
        answer = self.poll(device)
        self.assertEqual((answer["claimed"], answer["code"]), (True, None))
        # A code works once.
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]})[0], 404)

    def test_claim_takes_the_phrase_as_a_person_types_it(self) -> None:
        for number, typed in enumerate((str.upper, str.title, lambda code: code.replace("-", " "),
                                        lambda code: "  " + code.replace("-", "  ").title() + " ",
                                        lambda code: code.replace("-", " - "))):
            device = self.register(f"board-{number}")
            with self.subTest(typed=typed(device["code"])):
                self.assertEqual(self.request("POST", "/api/devices/claim", {"code": typed(device["code"])}),
                                 (200, {"id": device["id"]}))

    def test_a_code_expires_and_the_board_is_given_a_new_one(self) -> None:
        device = self.register()
        relay_device = Handler.relay.by_id[device["id"]]
        relay_device.code_issued -= mock_relay.CODE_TTL_SECONDS - 5
        self.assertEqual(self.poll(device)["code"], device["code"])  # 5 seconds left: still the same
        relay_device.code_issued -= 5
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]}),
                         (404, {"error": mock_relay.ERR_UNKNOWN_CODE}))
        fresh = self.poll(device)["code"]
        self.assertNotEqual(fresh, device["code"])
        self.assertRegex(fresh, r"^[a-z]{3,5}-[a-z]{3,5}-[a-z]{3,5}$")
        self.assertEqual(self.poll(device)["code"], fresh)  # and it stays for its own 10 minutes
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": device["code"]})[0], 404)
        self.assertEqual(self.request("POST", "/api/devices/claim", {"code": fresh}), (200, {"id": device["id"]}))

    def test_a_claimed_device_keeps_its_owner_when_the_old_code_would_have_expired(self) -> None:
        device = self.claimed_device()
        Handler.relay.by_id[device["id"]].code_issued -= 2 * mock_relay.CODE_TTL_SECONDS
        answer = self.poll(device)
        self.assertEqual((answer["claimed"], answer["code"]), (True, None))

    def test_user_routes_need_a_claimed_device(self) -> None:
        device = self.register()
        base = f"/api/devices/{device['id']}"
        not_claimed = (409, {"error": mock_relay.ERR_NOT_CLAIMED})
        self.assertEqual(self.request("PUT", base + "/capsule", SQUATS), not_claimed)
        self.assertEqual(self.request("POST", base + "/action", {"action": "increment"}), not_claimed)
        self.assertEqual(self.request("GET", base + "/state"), not_claimed)
        self.assertEqual(self.poll(device)["version"], 0)
        no_device = (404, {"error": mock_relay.ERR_UNKNOWN_DEVICE})
        self.assertEqual(self.request("PUT", "/api/devices/dev_gone/capsule", SQUATS), no_device)
        self.assertEqual(self.request("POST", "/api/devices/dev_gone/action", {"action": "reset"}), no_device)
        self.assertEqual(self.request("GET", "/api/devices/dev_gone/state"), no_device)

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
                self.assertEqual(self.request("PUT", path, body), (400, {"error": message}))
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


class Routing(RelayCase):
    def test_unknown_paths_and_wrong_methods(self) -> None:
        device = self.register()
        not_found = (404, {"error": "not found"})
        wrong_method = (405, {"error": "method not allowed"})
        for path in ("/", "/state", "/api/devices", "/api/devices/", f"/api/devices/{device['id']}",
                     f"/api/devices/{device['id']}/nope", f"/api/devices/{device['id']}/capsule/x"):
            with self.subTest(path=path):
                self.assertEqual(self.request("GET", path), not_found)
        self.assertEqual(self.request("GET", "/api/devices/register"), wrong_method)
        self.assertEqual(self.request("PUT", "/api/devices/claim", {"code": device["code"]}), wrong_method)
        self.assertEqual(self.request("DELETE", f"/api/devices/{device['id']}/capsule"), wrong_method)
        self.assertEqual(self.request("PUT", f"/api/devices/{device['id']}/state", {}), wrong_method)
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
