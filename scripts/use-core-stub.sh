#!/bin/sh
# The tuned grading lives in the private core submodule. Without access to it (forks, contributors),
# this fills core/ with the basic, untuned grading from core-stub/ so the app builds and runs.
set -eu
cd "$(dirname "$0")/.."
if [ -e core/android/main ]; then
    echo "core/ is already populated; nothing to do."
    exit 0
fi
mkdir -p core
cp -R core-stub/. core/
rm -f core/README.md
echo "core/ now holds the basic grading from core-stub/."
