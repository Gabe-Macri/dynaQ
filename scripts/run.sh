#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."
echo "Starting dynaQ Audio Management Suite..."
swift run dynaQ "$@"
