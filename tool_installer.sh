#!/usr/bin/env bash
#
# tool_installer.sh
# Advanced, interactive installer for Kali/Debian.
# All messages prefixed with "0x:" and logged to /var/log/tool_installer.log
#
set -euo pipefail

LOGFILE="/var/log/tool_installer.log"
FAIL_MARKER="/var/log/tool_installer_fail.marker"

# Ensure logfile exists and is writable
prepare_log() {
  touch "$LOGFILE" 2>/dev/null || { echo "0x: ERROR - Cannot create log at $LOGFILE. Run as root."; exit 1; }
  chmod 644 "$LOGFILE" 2>/dev/null || true
}

# Unified logger: prints to console and appends to log file, prefixing with "0x:"
log() {
  local msg="$*"
  echo "0x: $msg"
  echo "0x: $msg" >> "$LOGFILE"
}

# Error handler - writes fail marker and logs
on_error() {
  local exit_code=$?
  log "ERROR - Installer failed (exit code $exit_code). Marker: $FAIL_MARKER"
  echo "0x: FAIL" > "$FAIL_MARKER" || true
  log "ERROR - See $LOGFILE for details."
  exit $exit_code
}
trap on_error ERR

# Require root
require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "0x: ERROR - This script must be run with sudo/root." >&2
    exit 1
  fi
}

# Print header/footer banners
print_header() {
  echo "========================================"
  echo "0x TOOL INSTALLER"
  echo "========================================"
  echo "" 
  echo "0x: Starting installer..."
  echo "" 
  echo "0x: Logging -> $LOGFILE"
  echo "" 
}

print_footer() {
  echo ""
  echo "========================================"
  echo "0x TOOL INSTALLER (END)"
  echo "========================================"
  echo ""
  log "SUCCESS - Installer finished."
  # remove fail marker if present (successful run)
  [ -f "$FAIL_MARKER" ] && rm -f "$FAIL_MARKER"
}

# Prompt helpers
prompt() {
  local msg="$1"; local default="${2:-}"
  if [ -n "$default" ]; then
    read -rp "0x: $msg [$default]: " reply
    reply="${reply:-$default}"
  else
    read -rp "0x: $msg: " reply
  fi
  echo "$reply"
}

yn_prompt() {
  local msg="$1"; local default="${2:-N}"
  read -rp "0x: $msg [y/N]: " resp
  resp="${resp:-$default}"
  case "$resp" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Download helper (supports curl or wget)
download_file() {
  local url="$1"; local out="$2"
  if command -v curl >/dev/null 2>&1; then
    log "Downloading (curl): $url -> $out"
    curl -L --fail -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading (wget): $url -> $out"
    wget -O "$out" "$url"
  else
    log "ERROR - Neither curl nor wget is installed."
    return 1
  fi
  log "Downloaded -> $out"
}

# Installation entry points
install_deb() {
  local file="$1"
  log "Installing .deb package: $file"
  dpkg -i "$file" || { log "dpkg reported issues, attempting apt-get -f install -y"; apt-get update && apt-get -f install -y; }
  log ".deb install complete."
}

extract_tarball() {
  local file="$1" dest="$2"
  mkdir -p "$dest"
  log "Extracting tar.gz to $dest"
  tar -xzf "$file" -C "$dest"
  log "Extraction done."
}

extract_zip() {
  local file="$1" dest="$2"
  if ! command -v unzip >/dev/null 2>&1; then
    log "unzip not found. Installing unzip..."
    apt-get update && apt-get install -y unzip
  fi
  mkdir -p "$dest"
  log "Unzipping $file -> $dest"
  unzip -o "$file" -d "$dest"
  log "Unzip complete."
}

install_single_file() {
  local src="$1" destdir="$2" toolname="$3"
  mkdir -p "$destdir"
  cp -f "$src" "$destdir/"
  local base="$(basename "$src")"
  local destpath="$destdir/$base"
  chmod +x "$destpath" || true
  log "Copied $src -> $destpath and set +x"
  # create symlink in /usr/local/bin if not already pointing
  if [ "$destdir" != "/usr/local/bin" ]; then
    ln -sf "$destpath" "/usr/local/bin/$toolname"
    log "Symlink created: /usr/local/bin/$toolname -> $destpath"
  fi
  echo "$destpath"
}

create_systemd_service() {
  local svcname="$1" execpath="$2" description="${3:-Managed by tool_installer}"
  local svcfile="/etc/systemd/system/$svcname.service"
  log "Creating systemd service $svcname -> ExecStart=$execpath"
  cat > "$svcfile" <<EOF
[Unit]
Description=$description
After=network.target

[Service]
Type=simple
ExecStart=$execpath
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$svcname.service"
  log "Service $svcname enabled and started."
}

# Main flow
main() {
  require_root
  prepare_log
  print_header

  # Source selection
  log "Prompting user for source (URL or local file)."
  echo ""
  echo "0x: Choose source:"
  echo "0x:   1) Download from URL"
  echo "0x:   2) Use existing local file path"
  srcchoice="$(prompt 'Enter choice [1/2]' '1')"
  local tmpfile=""
  SRC_FILE=""
  if [ "$srcchoice" = "1" ]; then
    dl_url="$(prompt 'Paste direct download URL (http(s):// or ftp)' )"
    tmpfile="$(mktemp -p /tmp tool_installer_XXXX)"
    log "Temporary download target: $tmpfile"
    download_file "$dl_url" "$tmpfile"
    SRC_FILE="$tmpfile"
  else
    localpath="$(prompt 'Enter absolute local file path')"
    if [ ! -f "$localpath" ]; then
      log "ERROR - Local file not found: $localpath"
      exit 1
    fi
    SRC_FILE="$localpath"
  fi

  # Suggested name
  default_name="$(basename "$SRC_FILE")"
  TOOL_NAME_RAW="$(prompt "Suggested tool name (used for folder/service) [$default_name]" "$default_name")"
  # sanitize tool name (alphanumeric, -, _)
  TOOL_NAME="$(echo "$TOOL_NAME_RAW" | sed 's/[^A-Za-z0-9._-]/_/g')"
  log "Tool name set to: $TOOL_NAME"

  # Optional checksum
  if yn_prompt "Do you have a SHA256 checksum to verify the download?" "N"; then
    checksum="$(prompt 'Paste SHA256 checksum (hex)')"
    echo "$checksum  $SRC_FILE" > /tmp/tool_checksum.txt
    if command -v sha256sum >/dev/null 2>&1; then
      log "Verifying checksum..."
      if sha256sum -c /tmp/tool_checksum.txt --status; then
        log "Checksum OK."
      else
        log "ERROR - Checksum mismatch."
        exit 1
      fi
    else
      log "sha256sum not available to verify. Skipping verification."
    fi
    rm -f /tmp/tool_checksum.txt
  fi

  # Choose install base
  echo ""
  echo "0x: Choose installation location:"
  echo "0x:   1) /usr/local/bin  (single binary)"
  echo "0x:   2) /opt/<toolname> (multi-file installs)"
  echo "0x:   3) Custom path (absolute)"
  choice="$(prompt 'Enter choice [1/2/3]' '1')"
  case "$choice" in
    1) INSTALL_BASE="/usr/local/bin" ;;
    2) INSTALL_BASE="/opt" ;;
    3) INSTALL_BASE="$(prompt 'Enter absolute custom path')" ;;
    *) INSTALL_BASE="/usr/local/bin" ;;
  esac
  log "Install base chosen: $INSTALL_BASE"

  # Detect MIME/type
  mime="$(file -b --mime-type "$SRC_FILE" || echo 'application/octet-stream')"
  log "Detected MIME type: $mime"
  case "$SRC_FILE" in
    *.deb) filetype="deb" ;;
    *.tar.gz|*.tgz) filetype="tar" ;;
    *.zip) filetype="zip" ;;
    *) 
      # If mime says application/x-debian-package
      if [[ "$mime" == "application/x-debian-package" ]]; then
        filetype="deb"
      elif [[ "$mime" == "application/gzip" || "$mime" == "application/x-gzip" ]]; then
        filetype="tar"
      elif [[ "$mime" == "application/zip" ]]; then
        filetype="zip"
      else
        filetype="single"
      fi
      ;;
  esac
  log "Interpreting as: $filetype"

  # Perform install based on type
  if [ "$filetype" = "deb" ]; then
    install_deb "$SRC_FILE"
    log ".deb install finished for $SRC_FILE"
    installed_exec="$(dpkg -L "$(dpkg-deb -f "$SRC_FILE" Package 2>/dev/null || true)" 2>/dev/null || true)"
    # not guaranteed to find main exec - leave to user to run by name
  elif [ "$filetype" = "tar" ]; then
    dest="$INSTALL_BASE/$TOOL_NAME"
    extract_tarball "$SRC_FILE" "$dest"
    # try to locate a likely executable (first executable file in extracted tree)
    found_exec="$(find "$dest" -type f -perm -u=x | head -n1 || true)"
    if [ -n "$found_exec" ]; then
      log "Detected executable inside archive: $found_exec"
      ln -sf "$found_exec" "/usr/local/bin/$TOOL_NAME" || true
      installed_exec="$found_exec"
      log "Symlink created: /usr/local/bin/$TOOL_NAME -> $found_exec"
    else
      log "No executable detected automatically inside archive. You may need to run/install manually from $dest"
      installed_exec=""
    fi
  elif [ "$filetype" = "zip" ]; then
    dest="$INSTALL_BASE/$TOOL_NAME"
    extract_zip "$SRC_FILE" "$dest"
    found_exec="$(find "$dest" -type f -perm -u=x | head -n1 || true)"
    if [ -n "$found_exec" ]; then
      log "Detected executable inside zip: $found_exec"
      ln -sf "$found_exec" "/usr/local/bin/$TOOL_NAME" || true
      installed_exec="$found_exec"
      log "Symlink created: /usr/local/bin/$TOOL_NAME -> $found_exec"
    else
      log "No executable detected automatically inside zip. Inspect $dest"
      installed_exec=""
    fi
  else
    # single file - copy to chosen location
    if [ "$INSTALL_BASE" = "/usr/local/bin" ]; then
      destpath="/usr/local/bin/$(basename "$SRC_FILE")"
      cp -f "$SRC_FILE" "$destpath"
      chmod +x "$destpath" || true
      installed_exec="$destpath"
      log "Copied single file -> $destpath"
    else
      destdir="$INSTALL_BASE/$TOOL_NAME"
      installed_exec="$(install_single_file "$SRC_FILE" "$destdir" "$TOOL_NAME")"
    fi
  fi

  # Optionally run the installed tool once
  if [ -n "${installed_exec:-}" ] && [ -x "$installed_exec" ]; then
    if yn_prompt "Run the installed executable now ($installed_exec)?" "N"; then
      log "Launching $installed_exec in background (nohup)..."
      nohup "$installed_exec" >/var/log/"$TOOL_NAME".out 2>&1 & disown || true
      sleep 1
      log "Process launched; stdout/stderr -> /var/log/$TOOL_NAME.out"
    fi
  fi

  # Optionally create systemd service
  if yn_prompt "Create (optional) systemd service to auto-start this tool on boot?" "N"; then
    svcname="$(prompt "Service name (no spaces)" "$TOOL_NAME")"
    # determine ExecStart path
    if [ -n "${installed_exec:-}" ] && [ -x "$installed_exec" ]; then
      execpath="$installed_exec"
    elif [ -x "/usr/local/bin/$TOOL_NAME" ]; then
      execpath="/usr/local/bin/$TOOL_NAME"
    else
      execpath="$(prompt 'Enter full path to executable for service (absolute)')"
    fi
    create_systemd_service "$svcname" "$execpath" "Service for $TOOL_NAME (created by tool_installer)"
  fi

  log "Installation steps completed for $TOOL_NAME."
  print_footer
}

main "$@"
