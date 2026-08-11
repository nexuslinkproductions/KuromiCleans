#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Running KuromiCleans verification harness =="
mkdir -p .build
swiftc -O Sources/SortEngine.swift Tests/main.swift -o .build/run_tests
.build/run_tests
