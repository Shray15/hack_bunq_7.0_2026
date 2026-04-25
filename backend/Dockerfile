# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.12

# ---------- builder ----------
FROM ghcr.io/astral-sh/uv:0.5-python${PYTHON_VERSION}-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Install deps first for better layer caching. Lockfile is optional in early phases.
COPY pyproject.toml uv.lock* ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-install-project --no-dev

COPY app ./app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev

# ---------- runtime ----------
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

ARG VERSION=dev
ENV VERSION=${VERSION} \
    ENVIRONMENT=production \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --home /app --shell /sbin/nologin app

WORKDIR /app
COPY --from=builder --chown=app:app /app /app

USER app
EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request, sys; sys.exit(0 if urllib.request.urlopen('http://localhost:4567/healthz').status == 200 else 1)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "4567"]
