#!/usr/bin/env python3
"""Build, parse and check the Android bootloader_message (BCB) in `misc`.

Layout (AOSP bootloader_message.h, 2048 bytes):
  command[32]  status[32]  recovery[768]  stage[32]  reserved[1184]

The default image is `boot-recovery` with every other byte zero. U-Boot on
this unit boots the recovery partition when it sees that, and recovery opens
its menu with no arguments. Verified on one unit on 2026-10-25.

  bcb.py build > bcb.img           menu-only image to stdout
  bcb.py parse < bcb.img           decode, print SAFE or UNSAFE (exit 1)
  bcb.py check-misc FILE           a full misc dump: SAFE BCB, rest all zero
  bcb.py check-zero FILE           a full misc dump: every byte zero
  bcb.py selftest                  parser controls: SAFE accepted, wipe refused

A wipe image (recovery args `--wipe_data`) is refused unless the caller passes
both --wipe-data and --allow-wipe. It exists only as a negative control: parse
and check-misc always call it UNSAFE, so the host scripts will never write it.

Exit codes: 0 ok/SAFE, 1 UNSAFE or check failed, 2 usage or refused request.
"""
import sys

SIZE = 2048
MISC_SIZE = 1024 * 1024  # blkdevparts on this unit: 1M(misc)
CMD = b"boot-recovery"
WIPE_ARGS = b"recovery\n--wipe_data\n"


def build(wipe: bool = False) -> bytes:
    img = bytearray(SIZE)
    img[0:len(CMD)] = CMD
    if wipe:
        img[64:64 + len(WIPE_ARGS)] = WIPE_ARGS
    return bytes(img)


def fields(img: bytes) -> dict:
    def cstr(a, b):
        return img[a:b].split(b"\0", 1)[0]
    return {
        "command": cstr(0, 32),
        "status": cstr(32, 64),
        "recovery": cstr(64, 832),
        "stage": cstr(832, 864),
        "reserved_nonzero": sum(1 for x in img[864:] if x),
    }


def verdict(img: bytes) -> list:
    """Return a list of reasons the image is unsafe. Empty means SAFE."""
    if len(img) != SIZE:
        return [f"expected {SIZE} bytes, got {len(img)}"]
    d = fields(img)
    bad = []
    if d["command"] != CMD:
        bad.append("command is not boot-recovery")
    if d["recovery"] != b"":
        bad.append("recovery field is not empty (would pass arguments to recovery)")
    if b"wipe" in img.lower():
        bad.append("image mentions wipe")
    if d["status"] or d["stage"]:
        bad.append("status or stage is set")
    if d["reserved_nonzero"]:
        bad.append("reserved area is not zero")
    # Catch anything the field checks miss, such as bytes after a NUL.
    if not bad and img != build():
        bad.append("image differs from the menu-only BCB")
    return bad


def report(img: bytes) -> int:
    if len(img) == SIZE:
        for k, v in fields(img).items():
            print(f"{k}: {v!r}")
    bad = verdict(img)
    if bad:
        print("UNSAFE: " + "; ".join(bad))
        return 1
    print("SAFE: boot-recovery, menu only, no arguments")
    return 0


def read_file(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def check_misc(path: str) -> int:
    data = read_file(path)
    if len(data) != MISC_SIZE:
        print(f"FAIL: {path} is {len(data)} bytes, expected {MISC_SIZE}")
        return 1
    rc = report(data[:SIZE])
    tail_nonzero = sum(1 for x in data[SIZE:] if x)
    if tail_nonzero:
        print(f"FAIL: {tail_nonzero} nonzero bytes after the BCB")
        return 1
    if rc == 0:
        print(f"OK: rest of misc ({MISC_SIZE - SIZE} bytes) is zero")
    return rc


def check_zero(path: str) -> int:
    data = read_file(path)
    if len(data) != MISC_SIZE:
        print(f"FAIL: {path} is {len(data)} bytes, expected {MISC_SIZE}")
        return 1
    nonzero = sum(1 for x in data if x)
    if nonzero:
        print(f"FAIL: misc has {nonzero} nonzero bytes, expected all zero")
        return 1
    print(f"OK: misc is all zero ({MISC_SIZE} bytes)")
    return 0


def selftest() -> int:
    """Positive and negative control for the parser itself."""
    fails = []
    if verdict(build()):
        fails.append("menu-only image was not SAFE")
    if not verdict(build(wipe=True)):
        fails.append("wipe image was not UNSAFE")
    if not verdict(bytes(SIZE)):
        fails.append("all-zero image was not UNSAFE")
    tampered = bytearray(build())
    tampered[20] = 0x41  # a byte after the command's NUL
    if not verdict(bytes(tampered)):
        fails.append("image with a stray byte was not UNSAFE")
    if not verdict(build()[:-1]):
        fails.append("short image was not UNSAFE")
    for f in fails:
        print("selftest FAIL: " + f)
    if not fails:
        print("selftest OK: SAFE accepted; wipe, zero, stray byte, short refused")
    return 1 if fails else 0


def main(argv: list) -> int:
    mode = argv[1] if len(argv) > 1 else ""
    opts = set(argv[2:])
    if mode == "build":
        unknown = opts - {"--wipe-data", "--allow-wipe"}
        if unknown:
            print(f"build: unknown option {sorted(unknown)[0]}", file=sys.stderr)
            return 2
        wipe = "--wipe-data" in opts
        if wipe and "--allow-wipe" not in opts:
            print("build: refusing a wipe BCB; add --allow-wipe if you mean it", file=sys.stderr)
            return 2
        if "--allow-wipe" in opts and not wipe:
            print("build: --allow-wipe without --wipe-data does nothing", file=sys.stderr)
            return 2
        if sys.stdout.isatty():
            print("build: stdout is a terminal; redirect to a file", file=sys.stderr)
            return 2
        sys.stdout.buffer.write(build(wipe=wipe))
        return 0
    if mode == "parse" and not opts:
        return report(sys.stdin.buffer.read())
    if mode == "check-misc" and len(argv) == 3:
        return check_misc(argv[2])
    if mode == "check-zero" and len(argv) == 3:
        return check_zero(argv[2])
    if mode == "selftest" and not opts:
        return selftest()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
