#!/bin/sh
# Filters a CI step's output when it builds the private core. CI logs of this repository are public, and Swift and
# clang print the source around every warning and error as lines like "  45 |  code". The message with its file and
# line stays, so a failure can still be found. A build with the public stub passes through unchanged.
if [ "${HAS_CORE:-}" = true ]; then
    exec awk '!/^[ \t]*[0-9]*[ \t]*\|/ { print; fflush() }'
fi
exec cat
