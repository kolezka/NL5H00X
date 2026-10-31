#!/bin/bash
# Behaviour tests for the root daemon (root/sud.c), compiled for the host and
# run in a throwaway Linux container: sud needs Linux (SO_PEERCRED, abstract
# sockets) and root, and it writes its real device paths. No hardware involved.
#
#   bash tests/sud-tests.sh
#   SUD_SOURCE=/path/to/old/sud.c bash tests/sud-tests.sh   # confirm it goes red
#
# Needs docker or podman (CONTAINER_RUNTIME overrides). The first run builds a
# small local image (alpine + gcc), which needs network once. With no runtime it
# exits 2, never 0: a skipped suite must not read as a passing one.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
SUD_SOURCE="${SUD_SOURCE:-$REPO_ROOT/root/sud.c}"
IMAGE="nl5h00x-sud-test:alpine3.20"

RUNTIME="${CONTAINER_RUNTIME:-}"
if [[ -z "$RUNTIME" ]]; then
    for r in docker podman; do
        if command -v "$r" >/dev/null 2>&1 && "$r" info >/dev/null 2>&1; then RUNTIME=$r; break; fi
    done
fi
if [[ -z "$RUNTIME" ]]; then
    echo "SKIPPED: no working docker or podman; sud tests did not run" >&2
    exit 2
fi
[[ -f "$SUD_SOURCE" ]] || { echo "no such sud source: $SUD_SOURCE" >&2; exit 2; }
SUD_SOURCE="$(cd "$(dirname "$SUD_SOURCE")" && pwd)/$(basename "$SUD_SOURCE")"

if ! "$RUNTIME" image inspect "$IMAGE" >/dev/null 2>&1; then
    printf 'FROM alpine:3.20\nRUN apk add --no-cache gcc musl-dev bash coreutils procps\n' \
        | "$RUNTIME" build -q -t "$IMAGE" - >/dev/null \
        || { echo "could not build $IMAGE" >&2; exit 2; }
fi

exec "$RUNTIME" run --rm --network none \
    -v "$REPO_ROOT/root:/src/root:ro" \
    -v "$TEST_DIR/sud:/src/tests:ro" \
    -v "$SUD_SOURCE:/src/sud-under-test.c:ro" \
    "$IMAGE" bash /src/tests/sud-concurrency.sh /src/sud-under-test.c /src/root /src/tests/sudprobe.c
