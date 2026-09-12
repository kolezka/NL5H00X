#!/usr/bin/python3
"""Focused syscall and clock seam tests for the bounded supervisor."""

import contextlib
import importlib.util
import io
import os
import signal
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SUPERVISOR_PATH = Path(__file__).with_name("supervise.py")
SPEC = importlib.util.spec_from_file_location("supervise_under_test", SUPERVISOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SUPERVISOR_PATH}")
SUPERVISE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUPERVISE)


class FakeClock:
    def __init__(self) -> None:
        self.now = 10.0

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


class ReapTimeoutTests(unittest.TestCase):
    def run_with_reap_timeout(self, requested_signal=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        state_path = Path(temporary.name) / "state"
        supervisor = SUPERVISE.BoundedSupervisor(
            ["unused"], timeout=1.0, grace=0.05, state_path=state_path
        )
        read_fd, write_fd = os.pipe()
        os.close(write_fd)
        clock = FakeClock()
        wait_calls = []

        def spawn_group() -> bool:
            supervisor.leader_pid = 43210
            supervisor.status_fd = read_fd
            supervisor.command_status = 0
            supervisor.requested_signal = requested_signal
            return True

        def waitpid(pid: int, options: int):
            wait_calls.append((pid, options))
            return 0, 0

        supervisor.spawn_group = spawn_group
        stderr = io.StringIO()
        with mock.patch.object(SUPERVISE.signal, "signal"), mock.patch.object(
            supervisor, "signal_group", return_value=True
        ), mock.patch.object(supervisor, "grace_wait"), mock.patch.object(
            SUPERVISE.os, "waitpid", side_effect=waitpid
        ), mock.patch.object(
            SUPERVISE.time, "monotonic", side_effect=clock.monotonic
        ), mock.patch.object(
            SUPERVISE.time, "sleep", side_effect=clock.sleep
        ), contextlib.redirect_stderr(stderr):
            status = supervisor.run()

        return (
            supervisor,
            status,
            state_path.read_text(encoding="utf-8"),
            stderr.getvalue(),
            read_fd,
            wait_calls,
        )

    def test_reap_timeout_turns_child_success_into_cleanup_failure(self) -> None:
        supervisor, status, state, stderr, read_fd, wait_calls = (
            self.run_with_reap_timeout()
        )

        self.assertEqual(status, 125)
        self.assertIn("cleanup failed leader=43210 detail=reap-timeout\n", state)
        self.assertIn("exit status=125\n", state)
        self.assertIn(
            "[CLEANUP ERROR] leader 43210 was not reaped within 0.05s\n", stderr
        )
        self.assertTrue(wait_calls)
        self.assertTrue(all(call == (43210, os.WNOHANG) for call in wait_calls))
        self.assertIsNone(supervisor.leader_pid)
        self.assertIsNone(supervisor.status_fd)
        with self.assertRaises(OSError):
            os.fstat(read_fd)

    def test_reap_timeout_preserves_requested_cancellation_status(self) -> None:
        supervisor, status, state, stderr, read_fd, wait_calls = (
            self.run_with_reap_timeout(signal.SIGINT)
        )

        self.assertEqual(status, 130)
        self.assertIn("cleanup failed leader=43210 detail=reap-timeout\n", state)
        self.assertIn("exit status=130\n", state)
        self.assertIn(
            "[CLEANUP ERROR] leader 43210 was not reaped within 0.05s\n", stderr
        )
        self.assertTrue(wait_calls)
        self.assertTrue(all(call == (43210, os.WNOHANG) for call in wait_calls))
        self.assertIsNone(supervisor.leader_pid)
        self.assertIsNone(supervisor.status_fd)
        with self.assertRaises(OSError):
            os.fstat(read_fd)


if __name__ == "__main__":
    unittest.main()
