#!/bin/sh

wait_for_tcp_port() {
  local host="$1"
  local port="$2"
  local timeout="${3:-30}" # Default timeout in seconds is 30
  local start_time=$SECONDS
  local elapsed_time=0

  echo "Waiting for TCP port $port on host $host (timeout: ${timeout}s)..."

  while true; do
    # Attempt to open a TCP connection to the host and port
    if nc -z "${host}" "${port}" >/dev/null 2>&1; then
      echo "TCP port $port on host $host is now reachable."
      return 0 # Success: Port is reachable
    fi

    elapsed_time=$((SECONDS - start_time))
    if [[ "$elapsed_time" -ge "$timeout" ]]; then
      echo "Timeout reached. TCP port $port on host $host is not reachable within ${timeout} seconds."
      return 1 # Failure: Timeout reached
    fi

    sleep 1 # Wait for 1 second before retrying
  done
}

wait_for_tcp_port "${REDIS_HOST}" 6379 60
if [[ "$?" -eq 0 ]]; then
  echo "redis server is ready!"
else
  echo "redis server is not ready after waiting."
  exit 1
fi

wait_for_tcp_port "${POSTGRES_HOST}" 5432 60
if [[ "$?" -eq 0 ]]; then
  echo "postgres server is ready!"
else
  echo "postgres server is not ready after waiting."
  exit 1
fi

exit 0
