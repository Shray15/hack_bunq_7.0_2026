#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${BUNQ_DATA_DIR:-/data/bunq}"
export BUNQ_DATA_DIR="$DATA_DIR"

if [ ! -f "$DATA_DIR/bunq_sandbox.conf" ] || [ ! -f "$DATA_DIR/account_id" ]; then
    echo "[entrypoint] bunq config incomplete in $DATA_DIR, bootstrapping..."
    python /app/scripts/bootstrap_bunq.py
fi

exec uvicorn grocery_api:app --host 0.0.0.0 --port 8001
