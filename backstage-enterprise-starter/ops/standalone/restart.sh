#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/stop.sh"
sleep 2
"$(dirname "$0")/start.sh"
