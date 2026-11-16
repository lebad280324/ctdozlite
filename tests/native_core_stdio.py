#!/usr/bin/env python3
"""Exercise the real JSONL worker in synthetic mode, without user data or Zalo."""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ.get("CTDOZLITE_TEST_CORE", ROOT / "target/debug/ctdozlite-core"))
PRIVATE_KEYS = {"zpw_sek", "zpw_enk", "imei", "cookies", "password", "session_key"}


class Worker:
    def __init__(self, core=None):
        core = core or CORE
        self.temporary = tempfile.TemporaryDirectory(prefix="ctdo-native-bridge-")
        self.frames = []
        self.output = queue.Queue()
        self.process = subprocess.Popen(
            [str(core), "--demo"], cwd=self.temporary.name,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1,
        )
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.ready = self.wait(lambda frame: frame.get("event") == "ready")

    def _read(self):
        try:
            for line in self.process.stdout:
                try:
                    self.output.put(json.loads(line))
                except (ValueError, TypeError):
                    self.output.put(AssertionError("Worker emitted non-JSON stdout"))
        finally:
            self.output.put(EOFError("Worker stdout closed"))

    def wait(self, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                frame = self.output.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if isinstance(frame, Exception):
                raise frame
            self.frames.append(frame)
            if predicate(frame):
                return frame
        raise AssertionError("Worker did not finish the requested operation before deadline")

    def request(self, command, **parameters):
        request_id = str(uuid.uuid4())
        return self.request_frame({"id": request_id, "command": command, **parameters})

    def request_frame(self, body):
        request_id = body["id"]
        self.process.stdin.write(json.dumps(
            body, ensure_ascii=False
        ) + "\n")
        self.process.stdin.flush()
        return self.wait(lambda frame: frame.get("event") == "result" and frame.get("id") == request_id)

    def latest(self, event):
        return next(frame for frame in reversed(self.frames) if frame.get("event") == event)

    def bootstrap(self):
        result = self.request("bootstrap")
        if not result.get("ok"):
            raise AssertionError("Synthetic bootstrap failed")
        return self.latest("threads")["data"]

    def close(self):
        try:
            if self.process.poll() is None:
                self.process.stdin.close()
                self.process.wait(timeout=5)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=3)
            if not self.process.stdin.closed:
                self.process.stdin.close()
            self.process.stdout.close()
            self.reader.join(timeout=1)
            self.temporary.cleanup()


class NativeCoreStdioTests(unittest.TestCase):
    def setUp(self):
        self.worker = Worker()
        self.addCleanup(self.worker.close)

    def test_bootstrap_exposes_public_snapshots_and_capabilities(self):
        self.assertEqual(self.worker.ready["data"]["protocol_version"], 1)
        self.assertIn("send_message", self.worker.ready["data"]["capabilities"])
        threads = self.worker.bootstrap()
        self.assertGreater(len(threads), 0)
        self.assertTrue(self.worker.latest("session")["data"]["logged_in"])
        for thread in threads:
            self.assertTrue(thread["id"])
            self.assertIn("is_group", thread)

        def inspect(value):
            if isinstance(value, dict):
                self.assertFalse(PRIVATE_KEYS.intersection(value), "Secret field crossed IPC")
                for item in value.values():
                    inspect(item)
            elif isinstance(value, list):
                for item in value:
                    inspect(item)
        inspect(self.worker.frames)

    def test_unicode_multiline_message_roundtrips_and_is_acknowledged(self):
        thread = self.worker.bootstrap()[0]
        text = "Tiếng Việt: chào bạn 👋\nDòng thứ hai — thử IME"
        sent = self.worker.request("send_message", thread_id=thread["id"],
                                   is_group=thread["is_group"], text=text)
        self.assertTrue(sent["ok"])
        loaded = self.worker.request("load_messages", thread_id=thread["id"],
                                     is_group=thread["is_group"], limit=300)
        self.assertTrue(loaded["ok"])
        messages = self.worker.latest("messages")["data"]["messages"]
        matches = [message for message in messages if message.get("text") == text]
        self.assertEqual(len(matches), 1, "A single send must create one message (INV-4)")
        self.assertTrue(matches[0]["is_outgoing"])

    def test_local_history_page_is_bounded_and_cursor_is_exclusive(self):
        thread = self.worker.bootstrap()[0]
        result = self.worker.request("load_message_page", thread_id=thread["id"],
                                     is_group=thread["is_group"], limit=2)
        self.assertTrue(result["ok"])
        page = self.worker.latest("message_page")["data"]
        self.assertLessEqual(len(page["messages"]), 2)
        cursor = page["cursor"]
        first_ids = {message["id"] for message in page["messages"]}
        result = self.worker.request("load_message_page", thread_id=thread["id"],
                                     is_group=thread["is_group"], before=cursor, limit=2)
        self.assertTrue(result["ok"])
        second_ids = {message["id"] for message in self.worker.latest("message_page")["data"]["messages"]}
        self.assertFalse(first_ids & second_ids)
        self.assertTrue(self.worker.request("logout")["ok"])
        self.assertFalse(self.worker.request("load_message_page", thread_id=thread["id"],
                                            is_group=thread["is_group"])["ok"])

    def test_unknown_command_returns_correlated_failure_and_worker_survives(self):
        failed = self.worker.request("not_a_supported_command")
        self.assertFalse(failed["ok"])
        self.assertTrue(failed.get("error"))
        self.assertTrue(self.worker.request("bootstrap")["ok"])

    def test_malformed_input_does_not_corrupt_the_stream(self):
        self.worker.process.stdin.write("{invalid json}\n")
        self.worker.process.stdin.flush()
        self.worker.wait(lambda frame: frame.get("event") in {"result", "error"})
        self.assertTrue(self.worker.request("bootstrap")["ok"])

    def test_closed_parent_pipe_shuts_down_child(self):
        self.worker.bootstrap()
        self.worker.process.stdin.close()
        self.assertEqual(self.worker.process.wait(timeout=5), 0)

    def test_duplicate_request_does_not_send_twice(self):
        thread = self.worker.bootstrap()[0]
        request = {"id": "repeat-once", "command": "send_message", "thread_id": thread["id"],
                   "is_group": thread["is_group"], "text": "Một lần gửi duy nhất"}
        first = self.worker.request_frame(request)
        second = self.worker.request_frame(request)
        self.assertTrue(first["ok"])
        self.assertEqual(first, second)
        conflicting = self.worker.request_frame({**request, "text": "Nội dung khác"})
        self.assertFalse(conflicting["ok"])
        self.assertTrue(self.worker.request("load_messages", thread_id=thread["id"],
                                            is_group=thread["is_group"])["ok"])
        messages = self.worker.latest("messages")["data"]["messages"]
        self.assertEqual(sum(message["text"] == request["text"] for message in messages), 1)

    def test_oversized_frame_is_rejected_and_next_request_survives(self):
        self.worker.process.stdin.write("x" * (512 * 1_024) + "\n")
        self.worker.process.stdin.flush()
        failed = self.worker.wait(lambda frame: frame.get("event") == "result")
        self.assertFalse(failed["ok"])
        self.assertTrue(self.worker.request("bootstrap")["ok"])

    def test_demo_auth_is_disabled_and_creates_no_persistent_data(self):
        self.worker.bootstrap()
        self.assertFalse(self.worker.request("request_qr")["ok"])
        self.assertTrue(self.worker.request("logout")["ok"])
        self.assertFalse(self.worker.request("refresh_threads")["ok"])
        self.assertEqual(list(Path(self.worker.temporary.name).iterdir()), [])

    def test_typed_ba_families_share_safe_correlated_boundary(self):
        thread = self.worker.bootstrap()[0]
        guard = self.worker.request("set_privacy_guard", block_typing=True, block_delivered=False, block_seen=True)
        self.assertTrue(guard["ok"])
        self.assertEqual(guard["data"]["scope"], "device")
        settings = self.worker.request("set_account_setting", key="view_birthday", value=2)
        self.assertTrue(settings["ok"])
        self.assertEqual(settings["data"]["settings"]["view_birthday"], 2)
        self.assertFalse(self.worker.request("set_account_setting", key="session_key", value=1)["ok"])
        self.assertTrue(self.worker.request("get_workspace_features")["ok"])
        contact = self.worker.request("send_contact", thread_id=thread["id"], contact_id="contact-fixture")
        self.assertTrue(contact["ok"])
        self.assertEqual(contact["data"]["contact_id"], "contact-fixture")
        self.assertFalse(self.worker.request("send_contact", thread_id="missing-thread", contact_id="contact-fixture")["ok"])
        files = self.worker.request("search_history", query="no-such-file.pdf", files_only=True)
        self.assertTrue(files["ok"])
        self.assertEqual(files["data"]["items"], [])
        self.assertTrue(self.worker.request("data_usage")["ok"])
        self.assertFalse(self.worker.request("start_call", thread_id=thread["id"], is_group=thread["is_group"])["ok"])
        self.assertEqual(list(Path(self.worker.temporary.name).iterdir()), [])

    def test_shutdown_acknowledges_before_exit(self):
        self.assertTrue(self.worker.request("shutdown")["ok"])
        self.assertEqual(self.worker.process.wait(timeout=5), 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, default=CORE)
    arguments, remaining = parser.parse_known_args()
    CORE = arguments.core.resolve()
    unittest.main(argv=[__file__, *remaining])
