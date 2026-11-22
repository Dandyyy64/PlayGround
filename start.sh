#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/dist"
PORT="${PORT:-3000}"
METADATA_DIR="${OPENCODE_WEB_DIR:-/home/runner/work/_temp/omgithub-web}"
DEPLOYMENT_FILE="$METADATA_DIR/deployment-output.json"

run_timed() {
  /usr/bin/time -p "$@"
}

run_timed mkdir -p "$BUILD_DIR" "$METADATA_DIR"
# This is a dependency-free static project; Three.js is loaded by the browser from its CDN.
# Build a static deployment copy and repair the extra closing brace in the source module.
run_timed python3 - "$PROJECT_DIR/index.html" "$BUILD_DIR/index.html" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
# Keep source untouched; remove the stray brace that ends animate() before its render call.
broken = "\n    }\n    const target=player.position.clone();"
fixed = "\n    const target=player.position.clone();"
if source.count(broken) != 1:
    raise SystemExit("Expected to find exactly one misplaced animate() closing brace")
if source.count(":html,body{") != 1:
    raise SystemExit("Expected to find exactly one malformed root CSS selector")
built = source.replace(broken, fixed, 1).replace(":html,body{", "html,body{", 1)
pathlib.Path(sys.argv[2]).write_text(built)
PY
run_timed python3 - "$BUILD_DIR/index.html" "$BUILD_DIR/.module-check.mjs" <<'PY'
import pathlib, re, sys
html = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'<script type="module">(.*?)</script>', html, re.S)
if not match:
    raise SystemExit("Built HTML is missing its module script")
pathlib.Path(sys.argv[2]).write_text(match.group(1))
PY
run_timed node --check "$BUILD_DIR/.module-check.mjs"
run_timed rm "$BUILD_DIR/.module-check.mjs"
run_timed python3 - "$PROJECT_DIR" "$BUILD_DIR" "$DEPLOYMENT_FILE" <<'PY'
import json, pathlib, sys
project, directory, output = map(pathlib.Path, sys.argv[1:])
output.write_text(json.dumps({"project": str(project.resolve()), "directory": str(directory.resolve())}))
PY
run_timed bash -c 'cd "$1" && exec python3 -m http.server "$2" --bind 0.0.0.0 --directory "$3"' _ "$PROJECT_DIR" "$PORT" "$BUILD_DIR"
