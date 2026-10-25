#!/bin/bash
# Does the "command inherits only fds 0 1 2" check hold under repetition?
#
# The earlier review saw occasional extra fds from a probe that listed them
# through a shell pipeline, and called it a harness artifact. This separates
# the readings so only one explanation survives:
#
#   A  shell pipeline, no daemon involved   (the control: deviations seen
#                                            here belong to the pipeline)
#   B  the same pipeline through sud
#   C  a compiled lister through sud        (the form the test suite uses)
#
# If A and B show hits while C does not, the extra fd belongs to the pipeline,
# not to sud.
#
# The deviations are load-dependent. On an idle host all three loops report
# zero, and then the run proves nothing; to reproduce, run it alongside other
# container or build work. A and B must run the identical pipeline: the first
# version of this script quoted them differently and the control reported
# 200/200 while the daemon path reported 1/200.
#
# Runs on the host: sud and the clients are compiled for the host inside a
# disposable, network-less container, as tests/sud-tests.sh does. No device.
#
# Usage: bash tools/device/sud-fd-loop.sh [ITERATIONS]   (default 500)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ITERATIONS="${1:-500}"
IMAGE="nl5h00x-sud-test:alpine3.20"

RUNTIME="${CONTAINER_RUNTIME:-}"
if [[ -z "$RUNTIME" ]]; then
    for r in docker podman; do
        if command -v "$r" >/dev/null 2>&1 && "$r" info >/dev/null 2>&1; then RUNTIME=$r; break; fi
    done
fi
if [[ -z "$RUNTIME" ]]; then
    echo "SKIPPED: no working docker or podman" >&2
    exit 2
fi
"$RUNTIME" image inspect "$IMAGE" >/dev/null 2>&1 \
    || { echo "missing image $IMAGE - run tests/sud-tests.sh once first" >&2; exit 2; }

exec "$RUNTIME" run --rm --network none \
    -v "$REPO_ROOT/root:/src/root:ro" \
    -v "$REPO_ROOT/tests/sud:/src/tests:ro" \
    -v "$HERE/fd-loop-inner.sh:/src/fd-loop-inner.sh:ro" \
    "$IMAGE" sh /src/fd-loop-inner.sh "$ITERATIONS"
