#!/usr/bin/python3
"""Run one command in an owned process group with bounded cleanup."""

import argparse
import math
import os
import select
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional


def signal_name(signum: int) -> str:
    return signal.Signals(signum).name.removeprefix("SIG")


def shell_status(returncode: int) -> int:
    if returncode < 0:
        return 128 + (-returncode)
    return returncode


class BoundedSupervisor:
    def __init__(self, command: List[str], timeout: float, grace: float, state_path: Path) -> None:
        self.command = command
        self.timeout = timeout
        self.grace = grace
        self.state_path = state_path
        self.requested_signal: Optional[int] = None
        self.leader_pid: Optional[int] = None
        self.status_fd: Optional[int] = None
        self.status_buffer = b""
        self.command_status: Optional[int] = None

    def record(self, message: str) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        with self.state_path.open("a", encoding="utf-8") as state:
            state.write(message + "\n")

    def handle_signal(self, signum: int, _frame: object) -> None:
        if self.requested_signal is not None:
            return
        self.requested_signal = signum
        self.record(f"signal received={signal_name(signum)}")
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)

    def monitor_main(self, status_fd: int) -> None:
        os.setsid()
        try:
            command = subprocess.Popen(self.command)
        except OSError:
            os.write(status_fd, b"ERROR 127\n")
            os._exit(127)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.write(status_fd, f"READY {command.pid}\n".encode("ascii"))
        status = shell_status(command.wait())
        os.write(status_fd, f"STATUS {status}\n".encode("ascii"))
        while True:
            signal.pause()

    def read_line_blocking(self, deadline: float) -> Optional[str]:
        if self.status_fd is None:
            return None
        while time.monotonic() < deadline:
            if b"\n" in self.status_buffer:
                raw, self.status_buffer = self.status_buffer.split(b"\n", 1)
                return raw.decode("ascii", errors="replace")
            readable, _, _ = select.select([self.status_fd], [], [], 0.05)
            if not readable:
                continue
            chunk = os.read(self.status_fd, 4096)
            if not chunk:
                return None
            self.status_buffer += chunk
        return None

    def spawn_group(self) -> bool:
        read_fd, write_fd = os.pipe()
        leader_pid = os.fork()
        if leader_pid == 0:
            os.close(read_fd)
            self.monitor_main(write_fd)
            os._exit(125)
        os.close(write_fd)
        self.leader_pid = leader_pid
        self.status_fd = read_fd
        line = self.read_line_blocking(time.monotonic() + 5.0)
        if line is None or not line.startswith("READY "):
            self.record(f"spawn refused leader={leader_pid} detail={line or 'no-ready'}")
            try:
                os.kill(leader_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.reap_leader()
            return False
        try:
            actual_pgid = os.getpgid(leader_pid)
        except ProcessLookupError:
            self.record(f"spawn refused leader={leader_pid} detail=leader-exited")
            self.reap_leader()
            return False
        if actual_pgid != leader_pid:
            self.record(f"spawn refused leader={leader_pid} pgid={actual_pgid}")
            os.kill(leader_pid, signal.SIGKILL)
            self.reap_leader()
            return False
        self.record(f"spawn supervisor={os.getpid()} leader={leader_pid} pgid={actual_pgid}")
        return True

    def read_status_messages(self) -> None:
        if self.status_fd is None:
            return
        while True:
            if b"\n" not in self.status_buffer:
                readable, _, _ = select.select([self.status_fd], [], [], 0)
                if not readable:
                    return
                chunk = os.read(self.status_fd, 4096)
                if not chunk:
                    return
                self.status_buffer += chunk
            if b"\n" not in self.status_buffer:
                return
            raw, self.status_buffer = self.status_buffer.split(b"\n", 1)
            line = raw.decode("ascii", errors="replace")
            if line.startswith("STATUS "):
                self.command_status = int(line.split()[1])
                self.record(f"child status={self.command_status}")
            elif line.startswith("ERROR "):
                self.command_status = int(line.split()[1])
                self.record(f"child status={self.command_status}")

    def prove_owned_group(self) -> bool:
        if self.leader_pid is None:
            return False
        try:
            actual_pgid = os.getpgid(self.leader_pid)
        except ProcessLookupError:
            self.record(f"ownership refused leader={self.leader_pid} detail=not-running")
            return False
        if actual_pgid != self.leader_pid:
            self.record(
                f"ownership refused leader={self.leader_pid} expected_pgid={self.leader_pid} actual_pgid={actual_pgid}"
            )
            return False
        self.record(f"ownership proven leader={self.leader_pid} pgid={actual_pgid}")
        return True

    def signal_group(self, signum: int) -> bool:
        if not self.prove_owned_group() or self.leader_pid is None:
            return False
        try:
            os.killpg(self.leader_pid, signum)
        except ProcessLookupError:
            return False
        self.record(f"sent signal={signal_name(signum)} pgid={self.leader_pid}")
        return True

    def grace_wait(self, signum: int) -> None:
        self.record(f"grace started signal={signal_name(signum)}")
        deadline = time.monotonic() + self.grace
        while time.monotonic() < deadline:
            self.read_status_messages()
            time.sleep(0.02)

    def reap_leader(self) -> None:
        if self.leader_pid is None:
            return
        while True:
            try:
                os.waitpid(self.leader_pid, 0)
                break
            except InterruptedError:
                continue
            except ChildProcessError:
                break
        self.record(f"reaped leader={self.leader_pid}")
        self.leader_pid = None
        if self.status_fd is not None:
            os.close(self.status_fd)
            self.status_fd = None

    def release_group(self, initial_signal: int) -> None:
        if not self.signal_group(initial_signal):
            self.reap_leader()
            return
        self.grace_wait(initial_signal)
        if initial_signal != signal.SIGTERM:
            if not self.signal_group(signal.SIGTERM):
                self.reap_leader()
                return
            self.grace_wait(signal.SIGTERM)
        if self.signal_group(signal.SIGKILL):
            self.reap_leader()

    def final_status(self, fallback: int) -> int:
        if self.requested_signal is not None:
            return 128 + self.requested_signal
        return fallback

    def run(self) -> int:
        self.state_path.write_text("", encoding="utf-8")
        signal.signal(signal.SIGINT, self.handle_signal)
        signal.signal(signal.SIGTERM, self.handle_signal)
        if not self.spawn_group():
            return 125
        started = time.monotonic()

        while True:
            self.read_status_messages()
            if self.requested_signal is not None:
                requested = self.requested_signal
                self.release_group(requested)
                status = self.final_status(128 + requested)
                self.record(f"exit status={status}")
                return status

            if self.command_status is not None:
                child_status = self.command_status
                self.release_group(signal.SIGTERM)
                status = self.final_status(child_status)
                self.record(f"exit status={status}")
                return status

            if time.monotonic() - started >= self.timeout:
                self.record(f"timeout expired={self.timeout:g}")
                print(
                    f"[TIMEOUT] {self.timeout:g}s expired; terminating owned process group {self.leader_pid}",
                    file=sys.stderr,
                )
                self.release_group(signal.SIGTERM)
                status = self.final_status(124)
                self.record(f"exit status={status}")
                return status

            time.sleep(0.02)


def finite_positive(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=finite_positive, required=True)
    parser.add_argument("--grace", type=finite_positive, default=0.5)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    return args


def main() -> int:
    args = parse_args()
    return BoundedSupervisor(args.command, args.timeout, args.grace, args.state).run()


if __name__ == "__main__":
    raise SystemExit(main())
