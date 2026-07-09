#!/bin/bash
# Regenerates DriveVerse.xcodeproj from project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
