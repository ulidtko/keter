#!/usr/bin/env bash

locate_keter_executable () {
    # 1. If set already explicitly, and executable -- use that.
    test -x "$KETER" && { export KETER; return; }
    # 2. Perhaps we have a stack build ready
    KETER="$(stack exec -- which keter)"
    test -x "$KETER" && { export KETER; return; }
    # 3. Perhaps we have a cabal build ready
    KETER="$(cabal exec -- which keter)"
    test -x "$KETER" && { export KETER; return; }
    # 4. Maybe it's available on PATH ?
    KETER="$(which keter)"
    test -x "$KETER" && { export KETER; return; }
    # Otherwise, fail loudly
    {
        echo "Fatal: could not find the test subject."
        echo "Compile the keter executable first, and/or point to it in KETER env-var"
        exit 1
    } >&2
}

wait_until () {
    CMD="$1"
    INTERVAL=${2:-1.0}
    TIMEO="${3:-10}"
    timeout "$TIMEO" bash -c "set -o pipefail; while ! $CMD; do sleep $INTERVAL; done"
}
