#!/usr/bin/env bash

send_alert() {
  local type="$1"
  local url="$2"
  local msg="$3"
  echo "[STUB ALERT - $type] $url: $msg"
  return 0
}
