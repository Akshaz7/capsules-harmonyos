#!/usr/bin/env python3
"""Tests for mock_esp32.py. Standard library only: python3 tests/test_mock.py

The vector files in tests/vectors/ are the same ones the C tests run against the firmware's
copy_label(), utf8_valid() and json_scan(), which is what shows the two sides agree.
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
from typing import Iterator, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import mock_esp32  # noqa: E402
from mock_esp32 import ApiError, Capsule, Handler, clean_label, cut_label_bytes, json_scan, utf8_valid  # noqa: E402

TEA = {"type": "timer", "label": "Tea", "seconds": 180, "running": False}


def vector_lines(name: str) -> Iterator[bytes]:
    for line in (HERE / "vectors" / name).read_bytes().split(b"\n"):
        if line and not line.startswith(b"#"):
            yield line


def vector_bytes(text: str) -> bytes:
    """'61*3 c3a9' -> b'aaa\\xc3\\xa9'; '-' is nothing."""
    out = b""
    for token in text.replace("-", " ").split():
        digits, _, repeat = token.partition("*")
        out += bytes.fromhex(digits) * int(repeat or 1)
    return out


class LabelVectors(unittest.TestCase):
    def test_labels_are_judged_and_cut_like_the_firmware(self) -> None:
        count = 0
        for line in vector_lines("labels.txt"):
            valid, label, stored = (part.strip() for part in line.decode("ascii").split("|"))
            raw = vector_bytes(label)
            with self.subTest(label=label):
                self.assertEqual(utf8_valid(raw), valid == "1")
                self.assertEqual(cut_label_bytes(raw), vector_bytes(stored))
                # What a request with this label does: stored cut, or refused.
                as_parsed = raw.decode("utf-8", "surrogateescape")
                if valid == "1":
                    self.assertEqual(clean_label(as_parsed).encode("utf-8"), vector_bytes(stored))
                else:
                    with self.assertRaises(ApiError) as caught:
                        clean_label(as_parsed)
                    self.assertEqual(caught.exception.status, 400)
            count += 1
        self.assertGreaterEqual(count, 40)  # the file was really read

    def test_labels_that_json_can_produce_but_utf8_cannot_hold(self) -> None:
        for label in ("\ud83d", "\ude00", "a\ud83db", "a\x00b", "\x00"):
            with self.subTest(label=repr(label)):
                with self.assertRaises(ApiError) as caught:
                    clean_label(label)
                self.assertEqual(caught.exception.status, 400)
        self.assertEqual(clean_label("\U0001f600"), "\U0001f600")
        self.assertEqual(clean_label(""), "")


class JsonScanVectors(unittest.TestCase):
    def test_scan_agrees_with_the_firmware(self) -> None:
        count = 0
        for line in vector_lines("json_scan.txt"):
            wanted, _, body = line.partition(b"\t")
            if body.startswith(b"hex:"):
                body = vector_bytes(body[4:].decode("ascii"))
            with self.subTest(body=body):
                self.assertEqual(json_scan(body), wanted.decode("ascii"))
            count += 1
        self.assertGreaterEqual(count, 30)

    def test_long_bodies(self) -> None:
        self.assertEqual(json_scan(b"[" * 300), "deep")
        self.assertEqual(json_scan(b"{" * 1024), "deep")
        self.assertEqual(json_scan(b'"' + b"[" * 1022 + b'"'), "ok")
        self.assertEqual(json_scan(b"[]" * 500), "ok")

    def test_ends_and_limit(self) -> None:
        self.assertEqual(json_scan(b'"\\'), "ok")
        self.assertEqual(json_scan(b'"\\u000'), "ok")
        self.assertEqual(json_scan(b'"\\u0000'), "nul")
        self.assertEqual(json_scan(b"[[", 1), "deep")
        self.assertEqual(json_scan(b"[[", 2), "ok")
        self.assertEqual(json_scan(b"{}", 0), "deep")


class CapsuleState(unittest.TestCase):
    """A refused request must leave the capsule exactly as it was (finding 2)."""

    def setUp(self) -> None:
        self.capsule = Capsule(motion_interval=0)
        self.capsule.set_capsule(dict(TEA))
        self.before = self.capsule.state()

    def refused(self, body: dict, status: int = 400) -> None:
        with self.assertRaises(ApiError) as caught:
            self.capsule.set_capsule(body)
        self.assertEqual(caught.exception.status, status)
        self.assertEqual(self.capsule.state(), self.before)
        self.assertFalse(self.capsule.lock.locked())

    def test_lone_surrogate_label_changes_nothing(self) -> None:
        self.refused({"type": "counter", "label": "\ud83d"})
        self.refused({"type": "timer", "label": "\ud83d", "seconds": 5})

    def test_other_bad_labels_change_nothing(self) -> None:
        self.refused({"type": "counter", "label": "a\x00b"})
        self.refused({"type": "counter", "label": "caf\udcc3"})  # a raw 0xC3 byte in the body
        self.refused({"type": "counter", "label": 5})
        self.refused({"type": "counter", "label": None})

    def test_bad_fields_after_a_good_label_change_nothing(self) -> None:
        self.refused({"type": "counter", "label": "ok", "count": -1})
        self.refused({"type": "counter", "label": "ok", "motion": "yes"})
        self.refused({"type": "timer", "label": "ok"})
        self.refused({"type": "timer", "label": "ok", "seconds": 5, "running": 1})
        self.refused({"type": "stopwatch", "label": "ok"})

    def test_long_label_is_cut(self) -> None:
        state = self.capsule.set_capsule({"type": "counter", "label": "a" * 46 + "\xe9"})
        self.assertEqual(state["label"], "a" * 46)
        state = self.capsule.set_capsule({"type": "counter", "label": "\U0001f600" * 12})
        self.assertEqual(state["label"], "\U0001f600" * 11)

    def test_motion_on_only_applies_to_a_counter(self) -> None:
        with self.assertRaises(ApiError) as caught:
            self.capsule.apply({"action": "motion_on"})  # the Tea timer
        self.assertEqual(caught.exception.status, 409)
        idle = Capsule(motion_interval=0)
        with self.assertRaises(ApiError) as caught:
            idle.apply({"action": "motion_on"})
        self.assertEqual(caught.exception.status, 409)
        self.capsule.set_capsule({"type": "counter"})
        self.assertTrue(self.capsule.apply({"action": "motion_on"})["motion"])


class OverHttp(unittest.TestCase):
    """The handler itself: methods, Content-Length, bodies that are not text, and bugs."""

    server: ThreadingHTTPServer
    thread: threading.Thread

    @classmethod
    def setUpClass(cls) -> None:
        logging.disable(logging.CRITICAL)
        Handler.capsule = Capsule(motion_interval=0)
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        logging.disable(logging.NOTSET)

    def setUp(self) -> None:
        Handler.capsule = Capsule(motion_interval=0)
        self.request("POST", "/capsule", json.dumps(TEA).encode())

    def request(self, method: str, path: str, body: Optional[bytes] = None,
                headers: Optional[dict] = None) -> Tuple[int, dict]:
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        try:
            connection.putrequest(method, path)
            sent: List[str] = []
            for name, value in (headers or {}).items():
                connection.putheader(name, value)
                sent.append(name.lower())
            if body is not None and "content-length" not in sent:
                connection.putheader("Content-Length", str(len(body)))
            connection.endheaders(body)
            response = connection.getresponse()
            self.assertEqual(response.getheader("Content-Type"), "application/json")
            # Like the board, the mock sends a body even for HEAD; http.client will not read
            # one, so take it off the socket directly.
            raw = response.fp.read() if method == "HEAD" else response.read()
            return response.status, json.loads(raw)
        finally:
            connection.close()

    def assert_tea_untouched(self) -> None:
        status, state = self.request("GET", "/state")
        self.assertEqual(status, 200)
        self.assertEqual((state["type"], state["label"], state["remaining_seconds"]), ("timer", "Tea", 180))

    def assert_refused(self, raw: bytes, message: str, path: str = "/capsule") -> None:
        status, answer = self.request("POST", path, raw)
        self.assertEqual((status, answer), (400, {"error": message}))
        self.assert_tea_untouched()

    def test_lone_surrogate_gets_an_answer(self) -> None:
        # Used to raise UnicodeEncodeError half-way: no response, type already "counter".
        self.assert_refused(b'{"type":"counter","label":"\\ud83d"}', mock_esp32.ERR_BAD_JSON)
        self.assert_refused(b'{"type":"counter","note":"\\ud83d"}', mock_esp32.ERR_BAD_JSON)

    def test_bytes_that_are_not_utf8(self) -> None:
        self.assert_refused(b'{"type":"counter","label":"a\xffb"}', mock_esp32.ERR_BAD_LABEL)
        self.assert_refused(b'{"type":"counter","label":"\xed\xa0\xbd"}', mock_esp32.ERR_BAD_LABEL)
        # Outside the label they are ignored, as on the board.
        status, state = self.request("POST", "/capsule", b'{"type":"counter","label":"ok","note":"\xff"}')
        self.assertEqual((status, state["label"]), (200, "ok"))

    def test_nul(self) -> None:
        self.assert_refused(b'{"type":"counter","label":"a\\u0000b"}', mock_esp32.ERR_HAS_NUL)
        self.assert_refused(b'{"type":"counter","label":"a\x00b"}', mock_esp32.ERR_HAS_NUL)
        self.assert_refused(b'{"action":"reset\\u0000"}', mock_esp32.ERR_HAS_NUL, "/action")

    def test_nesting(self) -> None:
        self.assert_refused(b"[" * 300, mock_esp32.ERR_TOO_DEEP)
        self.assert_refused(b"{" * 1024, mock_esp32.ERR_TOO_DEEP, "/action")
        self.assert_refused(b'{"type":"counter","x":[[[[[[[[1]]]]]]]]}', mock_esp32.ERR_TOO_DEEP)
        status, _ = self.request("POST", "/capsule", b'{"type":"counter","x":[[[[[[[1]]]]]]]}')
        self.assertEqual(status, 200)
        status, state = self.request("POST", "/capsule", b'{"type":"counter","label":"a\\"[[[[[[[[[[{{{{"}')
        self.assertEqual((status, state["label"]), (200, 'a"[[[[[[[[[[{{{{'))

    def test_what_python_accepts_and_the_board_does_not(self) -> None:
        self.assert_refused(b'{"type":"counter","x":NaN}', mock_esp32.ERR_BAD_JSON)
        self.assert_refused(b'{"type":"counter","x":-Infinity}', mock_esp32.ERR_BAD_JSON)

    def test_control_characters_in_strings_are_allowed_as_on_the_board(self) -> None:
        status, state = self.request("POST", "/capsule", b'{"type":"counter","label":"a\tb"}')
        self.assertEqual((status, state["label"]), (200, "a\tb"))

    def test_head_and_options_get_the_json_405(self) -> None:
        for method in ("OPTIONS", "HEAD", "PUT", "DELETE", "PATCH"):
            with self.subTest(method=method):
                self.assertEqual(self.request(method, "/state"), (405, {"error": "method not allowed"}))
                self.assertEqual(self.request(method, "/nope"), (404, {"error": "not found"}))
        self.assertEqual(self.request("HEAD", "/capsule"), (405, {"error": "method not allowed"}))

    def test_content_length(self) -> None:
        for bad in ("-1", "-9999999999", "abc", ""):
            with self.subTest(content_length=bad):
                status, answer = self.request("POST", "/capsule", b"{}", {"Content-Length": bad})
                self.assertEqual((status, answer), (400, {"error": mock_esp32.ERR_BAD_LENGTH}))
        status, _ = self.request("POST", "/capsule", b"x" * 1025)
        self.assertEqual(status, 413)
        status, _ = self.request("POST", "/capsule", json.dumps(TEA).encode().ljust(1024))
        self.assertEqual(status, 200)
        self.assert_tea_untouched()

    def test_a_bug_in_the_mock_is_answered_with_500(self) -> None:
        class Broken(Capsule):
            def state(self) -> dict:
                raise RuntimeError("boom")

        Handler.capsule = Broken(motion_interval=0)
        self.assertEqual(self.request("GET", "/state"), (500, {"error": "internal error"}))
        self.assertFalse(Handler.capsule.lock.locked())


if __name__ == "__main__":
    unittest.main()
