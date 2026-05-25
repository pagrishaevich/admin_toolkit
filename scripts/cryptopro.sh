#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

: "${CRYPTO_PRO_ENABLED:=0}"
: "${CRYPTO_PRO_DIST_DIR:=/mnt/distr/linux/bootstrap/cryptopro}"
: "${CRYPTO_PRO_ARCHIVE_PATTERN:=linux-amd64*.tgz}"
: "${CRYPTO_PRO_INSTALL_RUTOKEN_PKCS11:=0}"
: "${CRYPTO_PRO_INSTALL_RUTOKEN_DRIVER:=0}"
: "${CRYPTO_PRO_INSTALL_JACARTA_DRIVER:=0}"
: "${CRYPTO_PRO_LICENSE_KEY:=}"

find_single_file() {
  local search_dir="$1"
  local pattern="$2"

  find "$search_dir" -maxdepth 1 -type f -name "$pattern" | sort | tail -n 1
}

append_if_exists() {
  local -n target_ref="$1"
  local value="${2:-}"

  if [ -n "$value" ]; then
    target_ref+=("$value")
  fi
}

install_cryptopro() {
  local archive_path=""
  local extract_dir=""
  local extracted_root=""
  local cpconfig_path=""
  local rutoken_pkcs11_rpm=""
  local jacarta_rpm=""
  local core_rpms=()

  if [ "$CRYPTO_PRO_ENABLED" != "1" ]; then
    log "[CRYPTO_PRO] skipped"
    return 0
  fi

  require_root
  require_command dnf
  require_command tar

  if [ ! -d "$CRYPTO_PRO_DIST_DIR" ]; then
    log "[ERROR] CRYPTO_PRO_DIST_DIR does not exist: $CRYPTO_PRO_DIST_DIR"
    exit 1
  fi

  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-base-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-rdr-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-kc1-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-capilite-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-curl-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-ca-certs-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-rdr-gui-gtk-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-cptools-gtk-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'lsb-cprocsp-pkcs11-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-rdr-pcsc-64-*.rpm')"
  append_if_exists core_rpms "$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-stunnel-64-*.rpm')"

  archive_path="$(find_single_file "$CRYPTO_PRO_DIST_DIR" "$CRYPTO_PRO_ARCHIVE_PATTERN")"
  if [ -n "$archive_path" ]; then
    log "[CRYPTO_PRO] found archive: $archive_path"
  fi

  if [ "${#core_rpms[@]}" -eq 0 ] && [ -n "$archive_path" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[DRY-RUN] unpack CryptoPro archive: $archive_path"
    else
      extract_dir="$(mktemp -d /tmp/cryptopro.XXXXXX)"
      tar -xf "$archive_path" -C "$extract_dir"
      extracted_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
      if [ -z "$extracted_root" ]; then
        log "[ERROR] extracted CryptoPro directory not found"
        rm -rf "$extract_dir"
        exit 1
      fi
      log "[CRYPTO_PRO] unpacked archive to: $extracted_root"
    fi
  fi

  if [ "${#core_rpms[@]}" -eq 0 ] && [ -n "$extracted_root" ]; then
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-base-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-rdr-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-kc1-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-capilite-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'cprocsp-curl-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-ca-certs-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'cprocsp-rdr-gui-gtk-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'cprocsp-cptools-gtk-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'lsb-cprocsp-pkcs11-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'cprocsp-rdr-pcsc-64-*.rpm')"
    append_if_exists core_rpms "$(find_single_file "$extracted_root" 'cprocsp-stunnel-64-*.rpm')"
  fi

  if [ "${#core_rpms[@]}" -eq 0 ]; then
    if [ "$DRY_RUN" = "1" ]; then
      if [ -n "$archive_path" ]; then
        log "[WARN] CryptoPro RPM packages will be resolved from the archive during real installation"
      else
        log "[ERROR] CryptoPro archive or RPM packages not found in $CRYPTO_PRO_DIST_DIR"
        exit 1
      fi
    else
      log "[ERROR] CryptoPro RPM packages not found in $CRYPTO_PRO_DIST_DIR or extracted archive"
      rm -rf "$extract_dir"
      exit 1
    fi
  else
    log "[CRYPTO_PRO] selected RPM packages:"
    printf '%s\n' "${core_rpms[@]}" | while IFS= read -r rpm_file; do
      log "[CRYPTO_PRO]   $rpm_file"
    done
  fi

  if [ "$CRYPTO_PRO_INSTALL_RUTOKEN_PKCS11" = "1" ]; then
    rutoken_pkcs11_rpm="$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'librtpkcs11ecp-*.rpm')"
    if [ -z "$rutoken_pkcs11_rpm" ] && [ -n "$extracted_root" ]; then
      rutoken_pkcs11_rpm="$(find_single_file "$extracted_root" 'librtpkcs11ecp-*.rpm')"
    fi
    [ -n "$rutoken_pkcs11_rpm" ] || {
      log "[ERROR] Rutoken PKCS#11 RPM not found in $CRYPTO_PRO_DIST_DIR"
      rm -rf "$extract_dir"
      exit 1
    }
    log "[CRYPTO_PRO] found Rutoken PKCS#11 RPM: $rutoken_pkcs11_rpm"
  fi

  if [ "$CRYPTO_PRO_INSTALL_JACARTA_DRIVER" = "1" ]; then
    jacarta_rpm="$(find_single_file "$CRYPTO_PRO_DIST_DIR" 'cprocsp-rdr-jacarta*.rpm')"
    if [ -z "$jacarta_rpm" ] && [ -n "$extracted_root" ]; then
      jacarta_rpm="$(find_single_file "$extracted_root" 'cprocsp-rdr-jacarta*.rpm')"
    fi
    [ -n "$jacarta_rpm" ] || {
      log "[ERROR] JaCarta RPM not found in $CRYPTO_PRO_DIST_DIR"
      rm -rf "$extract_dir"
      exit 1
    }
    log "[CRYPTO_PRO] found JaCarta RPM: $jacarta_rpm"
  fi

  log "[CRYPTO_PRO] installing dependencies"
  run_cmd dnf install -y pcsc-tools

  if [ "$CRYPTO_PRO_INSTALL_RUTOKEN_DRIVER" = "1" ]; then
    run_cmd dnf install -y ifd-rutokens
  fi

  log "[CRYPTO_PRO] installing CryptoPro CSP RPM packages"
  if [ "${#core_rpms[@]}" -gt 0 ]; then
    run_cmd dnf install -y "${core_rpms[@]}"
  fi

  if [ "$CRYPTO_PRO_INSTALL_RUTOKEN_PKCS11" = "1" ]; then
    log "[CRYPTO_PRO] installing Rutoken PKCS#11 library"
    run_cmd dnf install -y "$rutoken_pkcs11_rpm"
  fi

  if [ "$CRYPTO_PRO_INSTALL_JACARTA_DRIVER" = "1" ]; then
    log "[CRYPTO_PRO] installing JaCarta driver"
    run_cmd dnf install -y "$jacarta_rpm"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] enable pcsc daemon if available"
  else
    systemctl enable --now pcscd.socket >/dev/null 2>&1 || systemctl enable --now pcscd.service >/dev/null 2>&1 || true
  fi

  if [ -n "$CRYPTO_PRO_LICENSE_KEY" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[DRY-RUN] activate CryptoPro license"
    else
      cpconfig_path="$(cpconfig_cmd || true)"
      [ -n "$cpconfig_path" ] || {
        log "[ERROR] cpconfig not found after CryptoPro installation"
        rm -rf "$extract_dir"
        exit 1
      }
      log "[CRYPTO_PRO] activating license"
      "$cpconfig_path" -license -set "$CRYPTO_PRO_LICENSE_KEY"
    fi
  fi

  if [ -n "$extract_dir" ] && [ -d "$extract_dir" ]; then
    rm -rf "$extract_dir"
  fi

  log "[CRYPTO_PRO] done"
}

install_cryptopro "$@"
