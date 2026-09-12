#!/usr/bin/env python3
"""Build deterministic APK containers for the toolkit's binary manifest gate."""

import argparse
import struct
import zipfile


NO_INDEX = 0xFFFFFFFF
ANDROID_URI = "http://schemas.android.com/apk/res/android"


def chunk(kind, header_size, payload):
    return struct.pack("<HHI", kind, header_size, 8 + len(payload)) + payload


def length8(value):
    if value > 0x7FFF:
        raise ValueError("UTF-8 pool strings must fit a 15-bit length")
    if value > 0x7F:
        return bytes((0x80 | (value >> 8), value & 0xFF))
    return bytes((value,))


def length16(value):
    if value > 0x7FFF:
        return struct.pack("<HH", 0x8000 | (value >> 16), value & 0xFFFF)
    return struct.pack("<H", value)


def string_pool(strings, utf8):
    offsets = []
    data = bytearray()
    for text in strings:
        offsets.append(len(data))
        utf16 = text.encode("utf-16-le")
        units = len(utf16) // 2
        if utf8:
            encoded = text.encode("utf-8")
            data.extend(length8(units) + length8(len(encoded)) + encoded + b"\0")
        else:
            data.extend(length16(units) + utf16 + b"\0\0")
    data.extend(b"\0" * (-len(data) % 4))
    header = struct.pack("<IIIII", len(strings), 0, 0x100 if utf8 else 0,
                         28 + 4 * len(strings), 0)
    indexes = struct.pack("<%dI" % len(offsets), *offsets)
    return chunk(0x0001, 28, header + indexes + data)


def manifest(package, variant):
    # Put android:name first so the resource map needs just one entry.
    strings = ["name", "android", ANDROID_URI, "manifest", "package", package,
               "application", "activity", ".MainActivity", "intent-filter",
               "action", "android.intent.action.MAIN"]
    if variant == "home":
        strings.extend(["category", "android.intent.category.HOME"])
    strings = list(dict.fromkeys(strings))
    indexes = {text: index for index, text in enumerate(strings)}

    def node(kind, extension):
        return chunk(kind, 16, struct.pack("<II", 1, NO_INDEX) + extension)

    def attribute(namespace, name, value):
        namespace_index = NO_INDEX if namespace is None else indexes[namespace]
        value_index = indexes[value]
        return struct.pack("<IIIHBBI", namespace_index, indexes[name], value_index,
                           8, 0, 0x03, value_index)

    def start(name, attributes=()):
        extension = struct.pack("<IIHHHHHH", NO_INDEX, indexes[name],
                                20, 20, len(attributes), 0, 0, 0)
        return node(0x0102, extension + b"".join(attributes))

    def end(name):
        return node(0x0103, struct.pack("<II", NO_INDEX, indexes[name]))

    namespace = struct.pack("<II", indexes["android"], indexes[ANDROID_URI])
    chunks = [
        string_pool(strings, variant == "utf8"),
        # Android uses this ID for namespaced name attributes; the toolkit skips it.
        chunk(0x0180, 8, struct.pack("<I", 0x01010003)),
        node(0x0100, namespace),
        start("manifest", [attribute(None, "package", package)]),
        start("application"),
        start("activity", [attribute(ANDROID_URI, "name", ".MainActivity")]),
        start("intent-filter"),
        # The toolkit rejects any pool without MAIN, even for non-home fixtures.
        start("action", [attribute(ANDROID_URI, "name", "android.intent.action.MAIN")]),
        end("action"),
    ]
    if variant == "home":
        chunks.extend([
            start("category", [attribute(ANDROID_URI, "name", "android.intent.category.HOME")]),
            end("category"),
        ])
    chunks.extend([end("intent-filter"), end("activity"), end("application"),
                   end("manifest"), node(0x0101, namespace)])
    return chunk(0x0003, 8, b"".join(chunks))


def write_apk(output, package, variant):
    entries = [("AndroidManifest.xml", manifest(package, variant))]
    if variant == "native":
        # An ABI-gate marker, not a loadable ELF library.
        entries.append(("lib/x86_64/libdummy.so", b"fixture native library\n"))
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as apk:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED
            apk.writestr(info, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", help="APK path to create or overwrite")
    parser.add_argument("--package", default="com.example.fixture",
                        help="manifest package name (default: %(default)s)")
    parser.add_argument("--variant", choices=("utf16", "utf8", "home", "native"),
                        default="utf16", help="fixture variant (default: %(default)s)")
    args = parser.parse_args()
    try:
        write_apk(args.output, args.package, args.variant)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
