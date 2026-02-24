#!/bin/sh

# Determine the absolute path to the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting logical migration using Go..."
echo "Mounting $SCRIPT_DIR to /app"

docker run --rm -it \
  --network caddy \
  -v "$SCRIPT_DIR":/app \
  -w /app \
  -e SOURCE_ADDR="redis:6379" \
  -e TARGET_ADDR="valkey:6379" \
  golang:1.22-alpine \
  sh -c "go mod tidy && go run migrate.go"

echo "Migration finished."