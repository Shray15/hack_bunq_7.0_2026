#!/usr/bin/env bash
set -euo pipefail

cd /app

echo "[entrypoint] running alembic upgrade head"
alembic upgrade head

echo "[entrypoint] launching uvicorn"
exec uvicorn app.main:app --host 0.0.0.0 --port 4567 "$@"
