#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PINGPLACE_SMOKE_APP_PATH:-$ROOT_DIR/PingPlace.app}"
LOG_PATH="${PINGPLACE_LOG_PATH:-$HOME/Library/Logs/PingPlace/debug.log}"
SENDER="${PINGPLACE_SMOKE_SENDER:-com.apple.Terminal}"
TITLE="${PINGPLACE_SMOKE_TITLE:-PingPlace Smoke}"
MESSAGE="${PINGPLACE_SMOKE_MESSAGE:-demo notification}"
NOTIFICATION_TIMEOUT="${PINGPLACE_SMOKE_NOTIFICATION_TIMEOUT:-1}"
STARTUP_TIMEOUT="${PINGPLACE_SMOKE_STARTUP_TIMEOUT:-10}"
RESULT_TIMEOUT="${PINGPLACE_SMOKE_RESULT_TIMEOUT:-10}"
SETTINGS_FILE="${PINGPLACE_SMOKE_SETTINGS_FILE:-${TMPDIR:-/tmp}/PingPlace.smoke-test.json}"
POSITION="${PINGPLACE_SMOKE_POSITION:-deadCenter}"
PRIMARY_DISPLAY_TARGET="${PINGPLACE_SMOKE_DISPLAY_TARGET:-mainDisplay}"

assume_yes=0
skip_build=0
restart_regular_app=0
regular_app_bundle_to_restart=""

usage() {
  cat <<'EOF'
Usage: smoke-test-alerter.sh [--yes] [--no-build]

Runs a local PingPlace smoke test by:
1. optionally building a fresh debug app
2. writing smoke-test-only settings to an isolated JSON file
3. asking before stopping any running regular PingPlace instance
4. launching the repo's PingPlace.app in smoke-test mode
5. sending a test notification with alerter
6. checking the debug log for move activity

Options:
  --yes       do not prompt before stopping a running regular PingPlace instance
  --no-build  reuse the existing PingPlace.app bundle
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

regular_instances() {
  ps -axo pid=,command= | awk '
    index($0, "/PingPlace.app/Contents/MacOS/PingPlace") > 0 &&
    index($0, "--menu-preview") == 0 &&
    index($0, "--smoke-test") == 0 {
      print
    }
  '
}

first_regular_app_bundle_path() {
  local instance
  instance="$(regular_instances | head -n 1)"
  [[ -z "$instance" ]] && return 1

  local command_path
  command_path="$(printf '%s\n' "$instance" | awk '{$1=""; sub(/^ /, ""); print}')"
  [[ -z "$command_path" ]] && return 1

  printf '%s\n' "${command_path%/Contents/MacOS/PingPlace}"
}

smoke_test_instances() {
  ps -axo pid=,command= | awk '
    index($0, "/PingPlace.app/Contents/MacOS/PingPlace") > 0 &&
    index($0, "--smoke-test") > 0 {
      print
    }
  '
}

log_lines_since() {
  local baseline_lines=$1
  if [[ -f "$LOG_PATH" ]]; then
    tail -n +"$((baseline_lines + 1))" "$LOG_PATH"
  fi
}

set_smoke_settings() {
  local display_target=$1
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  cat > "$SETTINGS_FILE" <<EOF
{
  "debugMode" : true,
  "notificationDisplayTarget" : "$display_target",
  "notificationPosition" : "$POSITION"
}
EOF
}

wait_for_log_pattern() {
  local baseline_lines=$1
  local pattern=$2
  local timeout_seconds=$3
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if log_lines_since "$baseline_lines" | grep -Fq "$pattern"; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

run_smoke_scenario() {
  local scenario_name=$1
  local display_target=$2
  local baseline_lines=0
  local scenario_logs

  if [[ -f "$LOG_PATH" ]]; then
    baseline_lines="$(wc -l < "$LOG_PATH")"
  fi

  set_smoke_settings "$display_target"
  open -n "$APP_PATH" --args --smoke-test --settings-file "$SETTINGS_FILE"

  if ! wait_for_log_pattern "$baseline_lines" "Application launched." "$STARTUP_TIMEOUT"; then
    printf 'error: timed out waiting for PingPlace to launch for scenario: %s\n' "$scenario_name" >&2
    log_lines_since "$baseline_lines" | tail -n 80 >&2
    exit 1
  fi

  alerter --sender "$SENDER" --title "$TITLE ($scenario_name)" --message "$MESSAGE" --timeout "$NOTIFICATION_TIMEOUT"

  if ! wait_for_log_pattern "$baseline_lines" "Moved notification to" "$RESULT_TIMEOUT"; then
    printf 'error: timed out waiting for PingPlace to move the smoke-test notification for scenario: %s\n' "$scenario_name" >&2
    log_lines_since "$baseline_lines" | tail -n 120 >&2
    exit 1
  fi

  scenario_logs="$(log_lines_since "$baseline_lines")"

  if [[ "$display_target" == "builtInDisplay" ]]; then
    if grep -Fq "effectiveTarget=Laptop Display" <<< "$scenario_logs"; then
      printf 'Smoke test scenario succeeded: %s\n' "$scenario_name"
    elif grep -Fq "effectiveTarget=Main Display" <<< "$scenario_logs"; then
      printf 'Smoke test scenario skipped: %s (Laptop Display unavailable; app fell back to Main Display)\n' "$scenario_name"
      return 0
    fi
  else
    printf 'Smoke test scenario succeeded: %s\n' "$scenario_name"
  fi

  printf 'Relevant log lines for %s:\n' "$scenario_name"
  grep -E 'Application launched|Using settings (suite|file):|Display target changed:|Window candidate:|Post-move verification:|Moved notification to|Scheduling notification settle follow-up|notificationWindowCreated-settle' <<< "$scenario_logs" |
    tail -n 80
}

stop_regular_instances_if_needed() {
  local instances
  instances="$(regular_instances)"

  if [[ -z "$instances" ]]; then
    return 0
  fi

  printf 'Regular PingPlace instance(s) detected:\n%s\n' "$instances"
  regular_app_bundle_to_restart="$(first_regular_app_bundle_path || true)"
  if [[ -n "$regular_app_bundle_to_restart" ]]; then
    restart_regular_app=1
  fi

  if (( assume_yes == 0 )); then
    if [[ ! -t 0 ]]; then
      printf 'error: refusing to stop PingPlace without confirmation in a non-interactive shell; rerun with --yes\n' >&2
      exit 1
    fi

    local reply
    read -r -p "Stop the running regular PingPlace instance(s) and continue? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *)
        printf 'Aborted.\n'
        exit 1
        ;;
    esac
  fi

  while IFS= read -r instance; do
    [[ -z "$instance" ]] && continue
    local pid
    pid="${instance%% *}"
    kill "$pid"
  done <<< "$instances"

  local deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    if [[ -z "$(regular_instances)" ]]; then
      return 0
    fi
    sleep 0.2
  done

  printf 'error: timed out waiting for existing regular PingPlace instance(s) to exit\n' >&2
  exit 1
}

stop_smoke_test_instances() {
  local instances
  instances="$(smoke_test_instances)"

  if [[ -z "$instances" ]]; then
    return 0
  fi

  while IFS= read -r instance; do
    [[ -z "$instance" ]] && continue
    local pid
    pid="${instance%% *}"
    kill "$pid" 2>/dev/null || true
  done <<< "$instances"

  local deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    if [[ -z "$(smoke_test_instances)" ]]; then
      return 0
    fi
    sleep 0.2
  done

  printf 'warning: timed out waiting for smoke-test PingPlace instance(s) to exit\n' >&2
}

cleanup_smoke_test() {
  stop_smoke_test_instances

  if (( restart_regular_app == 1 )) && [[ -n "$regular_app_bundle_to_restart" ]] && [[ -d "$regular_app_bundle_to_restart" ]]; then
    open "$regular_app_bundle_to_restart" >/dev/null 2>&1 || true
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      assume_yes=1
      ;;
    --no-build)
      skip_build=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

trap cleanup_smoke_test EXIT

require_command open
require_command alerter
require_command grep
require_command awk
require_command ps
require_command kill
if (( skip_build == 0 )); then
  require_command make
fi

if (( skip_build == 0 )); then
  make debug-build
fi

if [[ ! -d "$APP_PATH" ]]; then
  printf 'error: app bundle not found: %s\n' "$APP_PATH" >&2
  exit 1
fi

stop_regular_instances_if_needed
run_smoke_scenario "main-display" "$PRIMARY_DISPLAY_TARGET"

if [[ "$PRIMARY_DISPLAY_TARGET" != "builtInDisplay" ]]; then
  run_smoke_scenario "laptop-display" "builtInDisplay"
fi
