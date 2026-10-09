#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -frontend -parse MetaRayRecorder/*.swift MetaRayRecorder/Core/*.swift MetaRayRecorder/Services/*.swift MetaRayRecorder/Views/*.swift Tests/*.swift
python3 Scripts/preflight.py
swiftc MetaRayRecorder/Core/RecordingTypes.swift Tests/CoreChecks.swift -o build/core-checks
build/core-checks
