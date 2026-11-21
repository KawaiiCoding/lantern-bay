#!/bin/sh
# Builds the web version into build/web (open it with: tools/serve_web.sh)
set -e
cd "$(dirname "$0")/.."
mkdir -p build/web
godot --headless --import --quit >/dev/null 2>&1 || true
godot --headless --export-release "Web" build/web/index.html
touch build/web/.nojekyll
echo "Built build/web/index.html"
