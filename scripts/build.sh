#!/usr/bin/env bash
set -e

echo "=== Building dynaQ (Debug & Release) ==="
cd "$(dirname "$0")/.."

echo "--> Compiling Swift targets..."
swift build -c release

echo "--> Running test suite..."
swift test

echo "--> Build succeeded!"
echo "Binary available at: .build/release/dynaQ"
