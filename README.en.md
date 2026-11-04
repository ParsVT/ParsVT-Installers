# ParsVT CRM Automated Installers

**English** | [فارسی](README.md)

Official automated deployment scripts for **ParsVT CRM** (Persian-localized Vtiger CRM) on Linux and Windows servers.

The scripts install and configure the whole stack: web server, PHP, MariaDB, ionCube, the CRM, scheduled jobs and backups. They ask as few questions as possible, which cuts manual configuration and human error.

| Platform | Script | Guide (Persian) |
|---|---|---|
| Linux | [`linux/parsvt.sh`](linux/parsvt.sh) | [`linux/README.md`](linux/README.md) |
| Windows Server | [`windows/parsvt.ps1`](windows/parsvt.ps1) | [`windows/README.md`](windows/README.md) |

---

## 🚀 Quick Start

You need a valid ParsVT license key and a server **without a control panel** (cPanel, DirectAdmin, Plesk, etc.). On a server with a control panel, both installers stop without changing anything.

### 🐧 Linux

Run as **root**:

```bash
curl -fsSLO https://raw.githubusercontent.com/ParsVT/ParsVT-Installers/main/linux/parsvt.sh && bash parsvt.sh
```

Not logged in as root? Use `sudo bash parsvt.sh` for the second part.

> **Do not use `bash <(curl ...)`.** If the download fails, bash runs an empty script and exits with code 0, which looks exactly like success. The command above runs the script only when the download is complete. It also leaves `parsvt.sh` on disk, which you need later for Repair, ionCube updates, PHP upgrades and SSL.

### 🪟 Windows Server

Open **PowerShell as Administrator** and paste:

```powershell
$ErrorActionPreference = "Stop"; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = "C:\ParsVT-Setup"; New-Item -ItemType Directory -Path $dir -Force | Out-Null
$url = "https://raw.githubusercontent.com/ParsVT/ParsVT-Installers/main/windows"
foreach ($f in "parsvt.ps1", "preflight.ps1", "Install ParsVT.cmd") { Invoke-WebRequest -Uri "$url/$([uri]::EscapeDataString($f))" -OutFile (Join-Path $dir $f) -UseBasicParsing }
Start-Process -FilePath (Join-Path $dir "Install ParsVT.cmd") -Verb RunAs
```

What each part does:

- `Stop`: if any download fails, nothing is started.
- `Tls12`: Windows PowerShell 5.1 on Server 2016 does not use TLS 1.2 by default, and GitHub requires it.
- `C:\ParsVT-Setup`: the files stay there for later Repair runs. `%TEMP%` can be cleaned at any time.

The launcher checks the server first (`preflight.ps1`), then asks **which Vtiger version** to install (Enter = Vtiger 8) and **the license key**.

**Manual alternative:** download the three files from the [`windows`](windows) folder into one local folder, then right-click `Install ParsVT.cmd` → **Run as administrator**. If you downloaded them as a ZIP, extract the whole ZIP first.

---

## ✨ Features

- **Native on each platform:** Bash on Linux; plain PowerShell 5.1 on Windows, with no XAMPP or Cygwin.
- **PHP version management:** PHP 8.3 for Vtiger 8 (recommended) or PHP 7.4 for Vtiger 7 (deprecated). On Linux, PHP can also be upgraded on an existing Vtiger 7 server, as part of the Vtiger 8 migration.
- **Security first:**
  - Strong random passwords for the database and the CRM `admin` user.
  - Credential and database option files are readable by root/Administrators only: `/root/crm.txt` and `/root/mysql.txt` on Linux; `C:\parsvt-credentials.txt` and `backup.cnf` on Windows.
  - The ionCube loader is checked against the installed PHP before it is enabled (Windows: NTS, x64 and PHP build).
  - phpMyAdmin (Windows) is reachable from localhost and private networks only by default, and stores no password.
- **Safe re-runs:** an existing CRM is never overwritten without a typed confirmation. The old web root is moved aside and the old database is dumped first. On Windows, Quick mode on an installed server runs Repair instead.
- **Automated backups:** daily database and file backups, with a restore script.
  - Linux keeps the number of backup sets you choose during installation.
  - Windows keeps backups for 7 days.
- **Built-in diagnostics (Windows):** a failed installation writes a support bundle (zip) to the Desktop. Passwords are removed from the logs, and the credential files are never included.
- **Quick mode (Windows):** `-Quick`, used by `Install ParsVT.cmd`, asks only for the Vtiger version and the license key. Vtiger 7 needs a second confirmation.

---

## 🖥️ Supported Operating Systems

### Windows

- Windows Server 2016, 2019 and 2022 (x64)
- Stack: Apache 2.4 (Apache Lounge) + mod_fcgid, PHP NTS, MariaDB 10.11, optional phpMyAdmin and Let's Encrypt (win-acme)

### Linux

| Family | Versions |
|---|---|
| RHEL | RHEL / CentOS 7+, AlmaLinux / Rocky / Oracle Linux 8+, Fedora 39+ |
| Debian | Debian 11+, Ubuntu 20.04+, Linux Mint 21+, Pop!_OS 22.04+ |

- Stack: Apache (httpd / apache2), MariaDB, PHP (mod_php or PHP-FPM).
- Fedora, Linux Mint and Pop!_OS are best effort. EL7 is end-of-life: use AlmaLinux 9 for new servers.
- SUSE / openSUSE is **not** supported.
- Versions newer than the tested ones are accepted with a warning.
- See [`linux/README.md`](linux/README.md) for the exact tested versions.

---

## 🛠️ Advanced Usage

### Linux

`parsvt.sh` shows a menu with these options:

- Install Vtiger 8 / PHP 8.3
- Install Vtiger 7 / PHP 7.4
- Install with national internet (AlmaLinux 9 only)
- Repair
- Update ionCube
- Upgrade PHP to 8.3
- Install ClamAV
- Install SSL
- Convert CentOS 7/8 to AlmaLinux 8

The PHP upgrade can also run without the menu:

```bash
bash parsvt.sh --php-upgrade --dry-run    # show the plan, change nothing
bash parsvt.sh --php-upgrade --upgrade    # do it
```

### Windows

Run from an elevated PowerShell in `C:\ParsVT-Setup`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parsvt.ps1 [-Quick] [-Vtiger 8|7] [-SkipPreflight] [-DryRun]
```

| Flag | Effect |
|---|---|
| (none) | Menu: install Vtiger 8 or 7, Repair, update ionCube. Asks for port, paths, domain and SSL |
| `-Quick` | Asks only for the Vtiger version and the license key; uses defaults (port 80, `C:\Apache24`, no domain or SSL). Runs Repair if the CRM is already installed |
| `-Vtiger 8` / `-Vtiger 7` | With `-Quick`: installs that version without asking |
| `-SkipPreflight` | With `-Quick`: skips the pre-installation checks |
| `-DryRun` | Shows what would be done without changing anything |

Run the read-only pre-installation checks yourself (recommended before an advanced install):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
```

---

## 🆘 Troubleshooting & Support

### Windows

If the installation fails, `ParsVT-Report-<date>.zip` is created on the Desktop. Send it to ParsVT support.

Logs:

- `C:\parsvt-logs` (installer, PHP, backup and restore)
- `C:\Apache24\logs\error.log`

### Linux

The installer prints its progress to the terminal. To keep a copy for support, run it under `script`:

```bash
script -q -c "bash parsvt.sh" /root/parsvt-install.log
```

Other logs:

- Backup and restore: `/var/log/crm_backup.log`, `/var/log/crm_restore.log`, and `/var/log/crm_backup.status` (last backup result)
- Apache: `/var/log/httpd` or `/var/log/apache2`

### Detailed guides

The full installation, maintenance and troubleshooting guides are in Persian:

- [`linux/README.md`](linux/README.md)
- [`windows/README.md`](windows/README.md)

---

## 📄 License

This project is proprietary software owned by ParsVT. Unauthorized distribution or modification is prohibited.
Website: [parsvt.com](https://www.parsvt.com)
