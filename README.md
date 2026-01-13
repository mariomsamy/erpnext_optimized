# ERPNext Optimized Installer (Recipe Codes)

This repository provides a **production-oriented, interactive + CLI installer** for deploying **Frappe/ERPNext** with practical defaults and reliable, repeatable setup on **Ubuntu** or **Debian**.

- Company: **Recipe Codes**
- Website: https://recipe.codes
- Repository: https://github.com/mariomsamy/erpnext_optimized

---

## Features

1. **Automated Frappe / ERPNext Installation**
   - Supports ERPNext/Frappe **v13, v14, v15, v16** (best-effort).
   - Installs and configures core dependencies: **Python**, **Node.js**, **MariaDB**, **Redis**, plus production tooling.

2. **Modern Dependency Handling**
   - Uses **nvm (nvm-sh)** to install the correct Node version per selected ERPNext/Frappe version.
   - Prefers **pipx** for installing `frappe-bench` (cleaner than system-wide pip on newer distros).
   - Works around common packaging constraints on newer Ubuntu/Debian releases (logging and clear errors).

3. **Production-Ready Option**
   - Optional **production setup** (Nginx + Supervisor + fail2ban) via `bench setup production`.
   - Enables scheduler automatically.

4. **Optional SSL (Let’s Encrypt)**
   - Optionally installs Certbot and issues SSL certificates for your FQDN.

5. **Idempotent + Safer Re-runs**
   - Uses markers for critical steps (e.g., MariaDB configuration) to avoid repeating destructive operations.
   - Skips `bench init` if the bench directory already exists.

6. **Logging + Troubleshooting**
   - Writes a full installation log to:
     - `/var/log/erpnext-installer.log`
   - Exits with a clear failure location (line number) to speed up debugging.

---

## Supported Versions (Installer Policy)

| ERPNext/Frappe Version | Node.js (Installer Target) | Python (Installer Target) | Notes |
|---|---:|---:|---|
| v13 | 18 | 3.10 | Legacy / best-effort |
| v14 | 18 | 3.10+ | Recommended baseline |
| v15 | 18 | 3.10+ | Stable production choice |
| v16 | 24 | 3.14+ | Requires newer Python; Ubuntu 24.04+ strongly recommended |

> v16 has stricter requirements, especially for Python. If your OS cannot provide Python 3.14+ reliably, the installer will stop and tell you what to fix first.

---

## How to Use

### 1) Download the Script
```bash
wget https://raw.githubusercontent.com/mariomsamy/erpnext_optimized/main/erpnext_installer.sh
````

### 2) Make It Executable

```bash
chmod +x erpnext_installer.sh
```

### 3) Run (Interactive)

```bash
sudo -E bash ./erpnext_installer.sh
```

### 4) Run (Non-Interactive / CLI)

```bash
sudo -E bash ./erpnext_installer.sh \
  --version 15 \
  --site erp.example.com \
  --prod yes \
  --db-root-pass 'StrongDBPass' \
  --admin-pass 'StrongAdminPass' \
  --install-erpnext yes \
  --install-hrms no \
  --ssl no
```

### 5) Access ERPNext

* **Production**

  * `https://your-domain` (if SSL enabled)
  * `http://your-domain` or `http://<server-ip>` (if SSL not enabled)
* **Development**

  * Start with: `bench start`
  * Access: `http://<server-ip>:8000`

---

## System Requirements

* **OS**: Ubuntu or Debian (see version notes above).
* **RAM**: Minimum **4 GB** (8 GB+ recommended for production).
* **CPU**: **2 vCPU** minimum.
* **Disk**: 20 GB+ free (NVMe/SSD recommended).

---

## Change Log

### Version 3.0 (Current)

* Added support for **ERPNext/Frappe v16** (best-effort, with strict dependency checks).
* Updated Node.js installation logic using **nvm-sh**.
* Prefer **pipx** for installing `frappe-bench`.
* Added safer re-run behavior (idempotent markers + skip existing bench init).
* Improved logging and failure visibility (line-level errors + full log file path).
* Added repository + company metadata in script header.

### Version 2.0

* Added rollback/error-handling improvements and more detailed logging.
* Added optional SSL setup flow.
* Improved domain validation and interactive prompts.

### Version 1.0

* Initial release: automated ERPNext installation with dependency setup.

---

## Why Use This Installer?

* **Reliable**: predictable results, clear logs, and safer re-runs.
* **Up-to-date**: modern Node/Python handling aligned to current Frappe directions.
* **Flexible**: works in interactive mode or fully scripted CI-style usage.
* **Owned & maintained**: Recipe Codes ([https://recipe.codes](https://recipe.codes))

---

## Example Output

```bash
ERPNext Installer - Recipe Codes
Website: https://recipe.codes
Repository: https://github.com/mariomsamy/erpnext_optimized

Select ERPNext/Frappe version to install:
1) 13
2) 14
3) 15
4) 16
#? 3

Do production setup (nginx + supervisor)? [yes/no] (default: yes): yes
Enter site name (FQDN recommended if SSL): erp.example.com
Enter MariaDB root password:
Confirm:
Enter ERPNext Administrator password:
Confirm:

Updating system packages...
Installing dependencies...
Initializing bench...
Creating site...
Installing ERPNext app...
Running production setup...

Installation completed.
Access: http://erp.example.com  (or https://erp.example.com if SSL enabled)
Log file: /var/log/erpnext-installer.log
```
