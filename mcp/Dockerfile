FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Git on Windows may strip the executable bit; restore it inside the image.
RUN chmod +x /app/scripts/entrypoint.sh

# Default location for the bunq sandbox conf + account_id sidecar.
# Mount a host volume here in production so config survives restarts.
ENV BUNQ_DATA_DIR=/data/bunq

EXPOSE 8001

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
