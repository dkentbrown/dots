#!/bin/sh
# Export the Web build and publish it to https://noema.dkentbrown.dev.
#   web/deploy.sh            export, stage and deploy
#   web/deploy.sh --no-export  deploy the last export as it is
# GODOT and WRANGLER override the tool paths.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
WRANGLER=${WRANGLER:-"npx wrangler"}
if [ "$1" != "--no-export" ]; then
  mkdir -p build/web
  "$GODOT" --headless --path . --export-release "Web" build/web/index.html
fi
# Stage: the engine goes up gzipped (see web/worker.js).
rm -rf build/site
cp -R build/web build/site
gzip -9 -n -c build/site/index.wasm > build/site/index.wasm.gz
rm build/site/index.wasm
cd web && $WRANGLER deploy
