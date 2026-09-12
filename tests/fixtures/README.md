# Binary manifest fixtures

From the worktree root, generate an APK container with Python's standard library:

```sh
python3 tests/fixtures/make-apk.py /tmp/example.apk --variant utf16 --package com.example.fixture
```

`--variant` accepts `utf16` (default), `utf8`, `home`, or `native`.
The output path is required and is overwritten if it exists. `--package` defaults
to `com.example.fixture`. The output directory must already exist.

Every manifest declares an activity with a MAIN intent-filter, which the toolkit's
decoder requires. Only `home` declares the HOME category. `home` and `native` use
UTF-16 pools. `native` adds `lib/x86_64/libdummy.so` for ABI mismatch checks.
The device seed declares `armeabi-v7a` but does not seed `ro.product.cpu.abilist`;
an ABI characterization should supply a nonempty ARM abilist in its fake state.

These are deterministic, unsigned parser fixtures, not installable applications.
They contain no bytecode, and the dummy library is not a loadable ELF file.
Fixed ZIP metadata and stored entries make repeated generation byte-identical.
The toolkit prints the package as `PKG=`, not `PACKAGE=`.
