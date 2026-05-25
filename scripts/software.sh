#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/kaspersky.sh"
source "$(dirname "$0")/cryptopro.sh"
source "$(dirname "$0")/vipnet.sh"
source "$(dirname "$0")/assistant.sh"
source "$(dirname "$0")/yandex_browser.sh"
source "$(dirname "$0")/r7office.sh"
run_local_hook software
log "[SOFT] done"
