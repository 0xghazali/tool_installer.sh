# 0x TOOL INSTALLER

`tool_installer.sh` ek **advanced portable installer script** hai jo Kali Linux (ya kisi bhi Debian-based system) par custom tools install karne ke liye banayi gayi hai.  

Har step aur log message ke aage `0x:` prefix hota hai (trace ke liye).  
Header aur footer me banner show hota hai: **0x TOOL INSTALLER**  

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
```bash
wget -O tool_installer.sh https://example.com/tool_installer.sh
chmod +x tool_installer.sh
