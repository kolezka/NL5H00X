#!/usr/bin/env python3
"""Shared client for the ESP32 UART bridge (projector-uart.local:2323).

The bridge prints a banner ending in `Password: `, takes one line, answers
`Authenticated.`, replays retained output, then prints a `--- live UART` marker.
After the marker every byte is the projector's serial console. The bridge takes
one client at a time.

The password is read from the firmware's gitignored secrets.h at run time. It is
never printed or logged, and any copy of it in received bytes is redacted.

Works with both consoles seen on this unit:
  Android   `console:/ $ `, uid shell, toybox in PATH
  recovery  `# `, uid 0, no applets in PATH: call `/vendor/bin/busybox <applet>`

CLI:
  uart.py check                       bridge answers with its password prompt; sends nothing
  uart.py run 'CMD'                   log in, run one command, print output and rc
  uart.py capture OUT [--seconds N] [--until TEXT] [--after N] [--ready-file F]
                                      log in and record console bytes to OUT

Exit codes: 0 ok, 1 command failed or marker missing, 2 bridge or secret problem.
"""
import argparse
import os
import re
import socket
import sys
import time

HOST = os.environ.get("UART_HOST", "projector-uart.local")
PORT = int(os.environ.get("UART_PORT", "2323"))
SECRETS = os.environ.get(
    "UART_SECRETS",
    "/Users/me/Development/NL5H00X-esp32c6/firmware/include/secrets.h",
)
BB = "/vendor/bin/busybox"
PROMPT = b"Password: "
LIVE = b"--- live UART"
AUDIT_LINE = re.compile(r"^\s*\[\s*\d+\.\d+\]\s+audit:.*$", re.M)


class BridgeError(Exception):
    """The bridge or the secret is not usable. Maps to exit code 2."""


def read_secret(path: str = SECRETS) -> bytes:
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        raise BridgeError(f"cannot read secrets file {path}: {e.strerror}") from None
    m = re.search(r'#define\s+UART_CONSOLE_PASSWORD\s+"([^"]*)"', text)
    if not m or not m.group(1):
        raise BridgeError(f"UART_CONSOLE_PASSWORD not found or empty in {path}")
    return m.group(1).encode()


class Bridge:
    def __init__(self, host: str = HOST, port: int = PORT, secret_path: str = SECRETS):
        self.host, self.port, self.secret_path = host, port, secret_path
        self.sock = None
        self._secret = b""
        self.closed = False

    # Connection and handshake

    def connect(self, timeout: float = 10) -> bytes:
        """Open the socket and wait for the password prompt. Returns the banner."""
        try:
            self.sock = socket.create_connection((self.host, self.port), timeout=timeout)
        except OSError as e:
            raise BridgeError(f"cannot reach {self.host}:{self.port}: {e}") from None
        banner = self.recv_until([PROMPT], timeout)
        if PROMPT not in banner:
            raise BridgeError("bridge did not show its password prompt")
        return banner

    def login(self) -> bytes:
        """Full handshake. Returns the retained history the bridge replays."""
        self._secret = read_secret(self.secret_path)
        self.connect()
        self.sock.sendall(self._secret + b"\n")
        auth = self.recv_until([b"Authenticated", b"ejected", PROMPT], 10)
        if b"Authenticated" not in auth:
            raise BridgeError("bridge did not accept the password")
        # The marker can arrive in the same read as `Authenticated`, so keep that buffer.
        history = auth[auth.find(b"Authenticated"):]
        if LIVE not in history:
            history += self.recv_until([LIVE], 15)
        if LIVE not in history:
            raise BridgeError("authenticated, but the live UART marker never came")
        # Read to the end of the marker line so it is not mistaken for console output.
        if not history.rstrip().endswith(b"---"):
            history += self.recv_until([b"\n"], 2)
        return self.redact(history)

    def close(self) -> None:
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    # Low-level IO

    def redact(self, data: bytes) -> bytes:
        if self._secret and self._secret in data:
            data = data.replace(self._secret, b"<REDACTED>")
        return data

    def recv_until(self, markers, timeout: float) -> bytes:
        """Collect bytes until a marker shows, the peer closes, or time runs out."""
        self.sock.settimeout(0.5)
        buf, end = b"", time.time() + timeout
        while time.time() < end:
            try:
                chunk = self.sock.recv(8192)
            except socket.timeout:
                continue
            except OSError:
                self.closed = True
                break
            if not chunk:
                self.closed = True
                break
            buf += chunk
            if any(m in buf for m in markers):
                break
        return self.redact(buf)

    def send(self, line: str) -> None:
        self.sock.sendall(line.encode() + b"\n")

    # Console use

    def prompt(self, timeout: float = 8) -> str:
        """Ask for a fresh prompt. Returns 'recovery', 'android' or 'unknown'."""
        self.send("")
        tail = self.recv_until([b"$ ", b"# "], timeout)
        text = tail.decode("utf-8", "replace").replace("\r", "")
        if re.search(r"console:\S* \$ $", text) or text.rstrip().endswith("$"):
            return "android"
        if text.rstrip().endswith("#"):
            return "recovery"
        return "unknown"

    def run(self, cmd: str, timeout: float = 20):
        """Run one command with a sentinel. Returns (rc or None, output text)."""
        tag = f"RCV{int(time.time() * 1000)}"
        self.send(f"{cmd}; echo {tag}_rc=$?")
        # The echoed command line holds a literal `$?`, so only a digit ends the wait.
        done = re.compile(tag.encode() + rb"_rc=\d+")
        out, end = b"", time.time() + timeout
        while time.time() < end and not done.search(out) and not self.closed:
            out += self.recv_until([b"\n"], 2)
        text = out.decode("utf-8", "replace").replace("\r", "")
        m = re.search(rf"{tag}_rc=(\d+)", text)
        echo_at = text.find(f"{tag}_rc=$?")
        body = text[text.find("\n", echo_at) + 1:] if echo_at >= 0 else text
        body = re.sub(rf"\n?{tag}_rc=\d+.*", "", body, flags=re.S)
        body = AUDIT_LINE.sub("", body)
        body = "\n".join(line for line in body.split("\n") if line.strip())
        return (int(m.group(1)) if m else None), body

    def capture(self, out_path: str, seconds: float, until: bytes = b"",
                after: float = 20, ready_file: str = "") -> bool:
        """Record console bytes to out_path. Returns True if `until` was seen."""
        history = self.login()
        seen = False
        with open(out_path, "wb") as log:
            log.write(b"[retained history]\n" + history + b"\n[live]\n")
            log.flush()
            if ready_file:
                with open(ready_file, "w") as f:
                    f.write("live\n")
            start, stop_at, tail = time.time(), None, b""
            self.sock.settimeout(1.0)
            while time.time() - start < seconds:
                if stop_at and time.time() >= stop_at:
                    break
                try:
                    chunk = self.sock.recv(8192)
                except socket.timeout:
                    continue
                except OSError:
                    chunk = b""
                if not chunk:
                    log.write(b"\n[bridge closed the connection]\n")
                    break
                chunk = self.redact(chunk)
                log.write(chunk)
                log.flush()
                tail = (tail + chunk)[-4096:]
                if until and not seen and until in tail:
                    seen = True
                    stop_at = time.time() + after
        return seen


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(description="ESP32 UART bridge client")
    sub = ap.add_subparsers(dest="mode", required=True)
    sub.add_parser("check")
    r = sub.add_parser("run")
    r.add_argument("cmd")
    r.add_argument("--timeout", type=float, default=20)
    c = sub.add_parser("capture")
    c.add_argument("out")
    c.add_argument("--seconds", type=float, default=240)
    c.add_argument("--until", default="")
    c.add_argument("--after", type=float, default=20)
    c.add_argument("--ready-file", default="")
    a = ap.parse_args(argv[1:])

    b = Bridge()
    try:
        if a.mode == "check":
            read_secret()
            b.connect()
            print(f"bridge OK: {HOST}:{PORT} shows its password prompt; secret file readable")
            return 0
        if a.mode == "run":
            b.login()
            kind = b.prompt()
            rc, body = b.run(a.cmd, a.timeout)
            print(f"[console: {kind}]\n$ {a.cmd}\n{body}\n[rc={rc}]")
            return 0 if rc == 0 else 1
        if a.mode == "capture":
            seen = b.capture(a.out, a.seconds, a.until.encode(), a.after, a.ready_file)
            if a.until:
                print(f"capture: marker {'seen' if seen else 'NOT seen'}: {a.until}")
                return 0 if seen else 1
            print("capture: done")
            return 0
    except BridgeError as e:
        print(f"bridge: {e}", file=sys.stderr)
        return 2
    finally:
        b.close()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
