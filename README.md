# Win11-Unattend-ISO

Builds a custom Windows 11 ISO by downloading and injecting `autounattend.xml` from [UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall), enabling a clean, debloated, pre-configured Windows 11 installation directly from an official Microsoft ISO—with no manual tweaking required.

It can also inject browser installers (`-Browsers`) and local app installers from `./apps` (`.exe`/`.msi`) for first-logon installation.

> **Warning:** Before the build starts, this tool deletes the output ISO (if it already exists) and any existing `autounattend.xml` in the working directory. It also deletes the downloaded `autounattend.xml` after the build completes.

## Main Scripts

- Native Linux/WSL: `build-winiso.sh`
- Native Windows PowerShell: `build-winiso.ps1`
- Docker Linux: `Dockerfile`
- Docker Windows containers: `Dockerfile.pwsh` **Recommended for Windows users** for better native tooling support and performance.

## Documentation

- Detailed script reference: [scripts-reference.md](docs/scripts-reference.md)

## Prerequisites

You must manually download a Windows 11 ISO from Microsoft before running this tool.

- **Native (Linux/WSL):** `bash`, `curl`, (`jq` or `python3`), `p7zip-full`, `xorriso`
- **Native (Windows PowerShell):** `oscdimg` (ADK Deployment Tools), `7z` optional. See [Installing Windows ADK (Deployment Tools) for oscdimg](#installing-windows-adk-deployment-tools-for-oscdimg).
- **Docker (Linux/Windows containers):** No local build dependencies are required beyond Docker, but Docker must be installed and configured.

## Quick Start

```bash
bash build-winiso.sh <input_iso> <output_iso>
```

```powershell
pwsh ./build-winiso.ps1 <input_iso> <output_iso>
```

Optional browsers:

```bash
bash build-winiso.sh <input_iso> <output_iso> -Browsers <chrome|opera|firefox|brave|all>
```

```powershell
pwsh ./build-winiso.ps1 <input_iso> <output_iso> -Browsers <chrome|opera|firefox|brave|all>
```

## Local Apps (`./apps`)

- Place `.exe` and/or `.msi` files in `./apps` (subdirectories supported). For multi-app silent installs, [Ninite](https://ninite.com/) works well and has been tested with this workflow.
- Installers are copied to `sources/$OEM$/$1/AppInstallers` inside the ISO.
- A one-time startup script (`install-apps-once.cmd`) is created when there are installers to run.
- If `./apps` is missing or has no `.exe`/`.msi`, the build still succeeds and app injection is skipped.

When `-Browsers` is used, browser installers are injected into `sources/$OEM$/$1/BrowserInstallers`.

- `.msi` installers run silently via `msiexec /i ... /qn /norestart`.
- `.exe` installers are executed directly, so use silent-capable installers for unattended behavior.

## Containers

Use Docker when you want a reproducible environment with no local dependency setup.

Linux:

```bash
docker info --format "{{.OSType}}" # Ensure this outputs "linux" before proceeding
docker build -t win11-unattend-iso .
docker run --rm -v /mnt/c/MV-ISO:/mnt/c/MV-ISO win11-unattend-iso /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso
# Add one browser:
docker run --rm -v /mnt/c/MV-ISO:/mnt/c/MV-ISO win11-unattend-iso /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso -Browsers brave
# Add multiple browsers (comma-separated):
docker run --rm -v /mnt/c/MV-ISO:/mnt/c/MV-ISO win11-unattend-iso /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso -Browsers brave,firefox
```

Windows containers:

```powershell
docker info --format "{{.OSType}}" # Ensure this outputs "windows" before proceeding
docker build --no-cache -f Dockerfile.pwsh -t win11-unattend-iso-pwsh C:\MV-ISO
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso
# Add one browser:
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso -Browsers brave
# Add multiple browsers (comma-separated):
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso -Browsers brave,firefox
```

## Installing Windows ADK (Deployment Tools) for oscdimg

Required only for native `build-winiso.ps1` usage (not required for Docker Windows containers).

1. Download the ADK installer from Microsoft:
   <https://go.microsoft.com/fwlink/?linkid=2243390>
2. Run `adksetup.exe`.
3. On the **Select the features you want to install** screen, tick only **Deployment Tools**.
4. Click **Install** and wait for completion.
5. Add `oscdimg` to your PATH:

   ```powershell
   $adkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
   [System.Environment]::SetEnvironmentVariable('PATH', "$env:PATH;$adkBin", 'User')
   ```

6. Restart PowerShell, then verify:

   ```powershell
   oscdimg /?
   ```

For older troubleshooting notes and archived details, see [history.md](docs/history.md).
