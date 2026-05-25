#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
require_command systemctl
require_command python3

configure_dnf_automatic() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] configure dnf-automatic apply_updates=${DNF_AUTO_APPLY_UPDATES} download_updates=${DNF_AUTO_DOWNLOAD_UPDATES}"
    return 0
  fi

  backup_file "$DNF_AUTOMATIC_CONFIG"
  DNF_AUTOMATIC_CONFIG="$DNF_AUTOMATIC_CONFIG" \
    DNF_AUTO_APPLY_UPDATES="$DNF_AUTO_APPLY_UPDATES" \
    DNF_AUTO_DOWNLOAD_UPDATES="$DNF_AUTO_DOWNLOAD_UPDATES" \
    python3 - <<'PY'
import configparser
import os
from pathlib import Path

cfg_path = Path(os.environ["DNF_AUTOMATIC_CONFIG"])
cfg = configparser.ConfigParser()
cfg.read(cfg_path)
if "commands" not in cfg:
    cfg["commands"] = {}
cfg["commands"]["apply_updates"] = os.environ["DNF_AUTO_APPLY_UPDATES"]
cfg["commands"]["download_updates"] = os.environ["DNF_AUTO_DOWNLOAD_UPDATES"]
with cfg_path.open("w") as fh:
    cfg.write(fh)
PY
}

configure_dnf_automatic
run_cmd systemctl enable --now dnf-automatic.timer
log "[AUTOUPDATE] done"
