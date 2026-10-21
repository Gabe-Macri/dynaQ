#!/bin/sh
set -e

# dynaQ Container Entrypoint Script
# Supports:
#   1. Standalone DSP & telemetry CLI: dynaq-cli [options]
#   2. Static documentation web server: dynaq docs

if [ "$1" = "docs" ] || [ "$1" = "serve" ] || [ "$1" = "server" ]; then
    PORT="${PORT:-8080}"
    echo "┌──────────────────────────────────────────────┐"
    echo "│  DYNAQ STATIC DOCUMENTATION SERVER           │"
    echo "│  URL: http://0.0.0.0:${PORT}                   │"
    echo "└──────────────────────────────────────────────┘"
    echo "// Serving technical documentation from /app/docs"
    echo "// Press Ctrl+C to terminate server."
    if command -v httpd >/dev/null 2>&1; then
        exec httpd -f -p "${PORT}" -h /app/docs
    elif command -v python3 >/dev/null 2>&1; then
        exec python3 -m http.server "${PORT}" --directory /app/docs
    else
        echo "Error: No suitable HTTP server found (busybox httpd or python3 required)"
        exit 1
    fi
fi

if [ "$1" = "sh" ] || [ "$1" = "bash" ]; then
    exec "$@"
fi

if [ "$#" -eq 0 ]; then
    exec dynaq-cli --help
fi

exec dynaq-cli "$@"

