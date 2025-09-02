# 0x TOOL INSTALLER

`tool_installer.sh` ek **advanced portable installer script** hai jo Kali Linux (ya kisi bhi Debian-based system) par custom tools install karne ke liye banayi gayi hai.  

---

## ✨ Features
- **Interactive flow**: user se input leta hai (URL ya local file).
- **File type detection**:
  - `.deb` → installs via `dpkg`
  - `.tar.gz` / `.tgz` → extracts to `/opt/<toolname>` or custom path
  - `.zip` → extracts to chosen path
  - single binary/script → copies to `/usr/local/bin` or chosen path
- **Auto-executable setup**: permissions + symlinks created
- **Optional checks**: SHA256 checksum verification
- **Optional persistence**: create `systemd` service (auto-start on boot)
- **Safe logging**: all actions logged to `/var/log/tool_installer.log`
- **Failure marker**: `/var/log/tool_installer_fail.marker` created if install fails

---

## 🚀 Usage

### 1. Clone or copy the script

wget -O tool_installer.sh https://example.com/tool_installer.sh
chmod +x tool_installer.sh

📝 Notes

You must run the script as root (sudo) because it installs into system paths like /usr/local/bin and /opt.

The script is transparent – it will always ask for your input before making changes. Nothing is installed silently.

You can install tools into a custom directory if you don’t want to touch system folders.

Logs are stored at: /var/log/tool_installer.log (all messages prefixed with 0x:).

If installation fails, a failure marker file is created: /var/log/tool_installer_fail.marker containing 0x: FAIL.

The installer supports .deb, .tar.gz, .tgz, .zip, and standalone binaries/scripts.

An optional systemd service can be created to auto-start the installed tool at boot.

