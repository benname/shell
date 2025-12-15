#!/usr/bin/env bash

set -euo pipefail

TS_FORMAT="%Y-%m-%d %H:%M:%S"

log_ts() {
  date +"${TS_FORMAT}"
}

log_info() {
  printf "[%s] [INFO ] %s\n" "$(log_ts)" "$*" >&1
}

log_warn() {
  printf "[%s] [WARN ] %s\n" "$(log_ts)" "$*" >&1
}

log_error() {
  printf "[%s] [ERROR] %s\n" "$(log_ts)" "$*" >&2
}

fatal() {
  log_error "$*"
  exit 1
}
