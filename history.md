# History

This file archives the detailed documentation that used to live in `README.md`.

## Additional Lessons Learned

1. **Keep local installer payloads out of git history and normal tracking.**
    - Use `.gitignore` for `apps` content and avoid committing binary installers.

2. **Docker builds must tolerate missing optional inputs.**
    - `./apps` is optional: build should succeed if the folder is missing/empty.
    - Injection should run only when `.exe`/`.msi` files actually exist.

3. **Optional features should be explicit in logs.**
    - Clear messages for "missing `./apps`" and "no installers found" reduce debugging time.

4. **Document examples for both single and multiple `-Browsers` values.**
    - Include `-Browsers chrome` and comma-separated variants in both Linux and Windows container examples.

5. **Sync + rebuild is critical after script or Dockerfile changes.**
    - For Windows container testing, re-sync workspace content and rebuild images with `--no-cache` when troubleshooting.

6. **Keep orchestrators thin and move stage-specific logic into child scripts.**
   - Linux now mirrors PowerShell modular flow (browser staging, app staging, RunOnce generation, unattended apply/rebuild), which makes debugging and parity checks much easier.

7. **When merging staged content, copy directory contents into destination roots, not the top-level directory node.**
   - Copying `sources` into an existing `sources` folder creates unintended nesting (`sources/sources/...`).

8. **Avoid hard dependency on a single JSON parser in shell tooling.**
   - Linux scripts now support `jq` first with `python3` fallback, reducing environment-specific failures.

9. **Parameter defaults should not depend on runtime-provided script path variables when they can be empty in container entrypoints.**
   - Resolve default paths after startup in script body rather than inside parameter default expressions.

10. **Keep README focused on usage and move deep script internals to dedicated docs.**

- Script reference content now lives in `scripts-reference.md` to keep top-level documentation easier to scan.

## Original Documentation

Injects an `autounattend.xml` into a Windows 11 ISO to produce a minimal, unattended installation image. The `autounattend.xml` is sourced from [UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall) and downloaded automatically at build time.

> **Warning:** Before the build starts, this tool deletes the output ISO (if it already exists) and any existing `autounattend.xml` in the working directory. It also deletes the downloaded `autounattend.xml` after the build completes.

## Prerequisites

You must manually download a Windows 11 ISO from Microsoft before running this tool.

- **Native (Linux/WSL):** `bash`, `curl`, `p7zip-full`, `xorriso`
- **Native (Windows PowerShell):** `oscdimg` (from Windows ADK Deployment Tools). `7z` is optional; if missing, the script uses native ISO mount/copy.
- **Docker (Linux):** Docker only — uses Linux container image.
- **Docker (PowerShell — Windows containers):** Requires Docker Desktop in Windows container mode, Windows 10/11 host with Hyper-V enabled, and no additional local tools — `oscdimg` is baked into the image.

### Installing Windows ADK (Deployment Tools) for oscdimg

1. Download the ADK installer from Microsoft:
   <https://go.microsoft.com/fwlink/?linkid=2243390>
2. Run `adksetup.exe`.
3. On the **Select the features you want to install** screen, tick only **Deployment Tools** (you do not need the other features).
4. Click **Install** and wait for it to complete.
5. Add `oscdimg` to your PATH so PowerShell can find it:

   ```powershell
   # Default install path (adjust if you chose a custom location)
   $adkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
   [System.Environment]::SetEnvironmentVariable('PATH', "$env:PATH;$adkBin", 'User')
   ```

   > Restart PowerShell after running this so the new PATH takes effect.
6. Verify:

   ```powershell
   oscdimg /?
   ```

   You should see the oscdimg usage/help output.

## Usage

### Native

```bash
bash build-winiso.sh <input_iso> <output_iso>
```

```powershell
pwsh ./build-winiso.ps1 <input_iso> <output_iso>
```

Optional browser injection:

```bash
bash build-winiso.sh <input_iso> <output_iso> -Browsers <chrome|opera|firefox|brave|all>
```

```powershell
pwsh ./build-winiso.ps1 <input_iso> <output_iso> -Browsers <chrome|opera|firefox|brave|all>
```

You can pass multiple browsers:

```bash
bash build-winiso.sh /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso -Browsers chrome,firefox
```

When `-Browsers` is used, the script downloads the latest installers and injects them into `BrowserInstallers/` in the ISO. It also writes:

- `BrowserInstallers/download-links.txt` with the source URLs used for each selected browser.
- `sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/install-browsers-once.cmd` with silent install commands for the selected browsers.

**Example:**

```bash
bash build-winiso.sh /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso
```

```powershell
pwsh ./build-winiso.ps1 C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso
```

### Docker

```bash
# Build the image
docker build -t win11-unattend-iso .

# Run the container
docker run --rm -v /mnt/c/MV-ISO:/mnt/c/MV-ISO win11-unattend-iso /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso
```

### Docker (PowerShell — Windows containers)

> **Requires:** Docker Desktop switched to Windows containers. Windows 10/11 host with Hyper-V enabled.

```powershell
# Verify Docker is in Windows container mode
docker info --format "{{.OSType}}"   # must print: windows

# Build/rebuild the image (use --no-cache after script changes)
docker build --no-cache -f Dockerfile.pwsh -t win11-unattend-iso-pwsh C:\MV-ISO

# Run the container
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso

# Run with browser injection
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso -Browsers brave

# Multiple browsers
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso -Browsers chrome,firefox
```

The `-v` flag mounts the host directory into the container at the same path so the container can read the input ISO and write the output ISO back to the host.

## Compare Two ISOs

Use the comparison script to check which files were added/removed/changed between two ISOs.

### Native (Linux/WSL)

```bash
bash compare-isos.sh /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso
```

Optional third argument sets report file path:

```bash
bash compare-isos.sh /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso /mnt/c/MV-ISO/iso-diff.txt
```

### Docker (Linux)

```bash
# Build comparison image
docker build -f Dockerfile.compare -t win11-iso-compare .

# Run compare inside container
docker run --rm -v /mnt/c/MV-ISO:/mnt/c/MV-ISO win11-iso-compare /mnt/c/MV-ISO/win11.iso /mnt/c/MV-ISO/win11-min.iso /mnt/c/MV-ISO/iso-diff.txt
```

## Troubleshooting

### Different ISO sizes between Linux and PowerShell outputs

Different ISO sizes do not always mean the payload files are different. Linux uses `xorriso` and Windows uses `oscdimg`, so ISO metadata can vary between builds.

Use `compare-isos.sh` to verify the actual file payload.

Expected Linux-only boot metadata entries:

```bash
[BOOT]/1-Boot-NoEmul.img
[BOOT]/2-Boot-NoEmul.img
boot/boot.cat
```

These differences are expected and do not mean files are missing from the Windows ISO.

### Why `-h` is required for `oscdimg` in `build-winiso.ps1`

Without `-h`, `oscdimg` can omit hidden files from the rebuilt ISO. One observed example was `sources/ws.dat` missing from a PowerShell-built ISO.

The fix is to include `-h` in the `oscdimg` command so hidden files are preserved.

### Why `compare-isos.sh` enforces locale

The compare script relies on sorted file lists before using `comm`. Locale differences can change sort order and trigger false errors such as `input is not in sorted order`.

`compare-isos.sh` sets `LC_ALL=C` and sorts paths explicitly to keep results deterministic.

### Browser installer text files are normalized across Linux and Windows builds

Both builders write the injected browser helper files in the same format to avoid hash or size differences caused only by encoding or line endings:

- `BrowserInstallers/download-links.txt`: ASCII with CRLF line endings
- `sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/install-browsers-once.cmd`: ASCII with CRLF line endings

### Docker (PowerShell): `-Browsers` parameter not found

If you see:

```text
build-winiso.ps1: A parameter cannot be found that matches parameter name 'Browsers'.
```

The container image usually predates the `-Browsers` support. Rebuild the image and run again:

```powershell
docker rmi win11-unattend-iso-pwsh
docker build --no-cache -f Dockerfile.pwsh -t win11-unattend-iso-pwsh C:\MV-ISO
docker run --rm -v C:\MV-ISO:C:\MV-ISO win11-unattend-iso-pwsh C:\MV-ISO\win11.iso C:\MV-ISO\win11-min.iso -Browsers brave
```

To confirm the current script supports the parameter:

```powershell
pwsh -NoLogo -NoProfile -Command "Get-Help ./build-winiso.ps1 -Full | Select-String Browsers"
```

### Docker (PowerShell): `no match for platform in manifest`

If you see:

```text
failed to resolve source metadata for mcr.microsoft.com/windows/servercore:ltsc2022: no match for platform in manifest
```

`Dockerfile.pwsh` uses a Windows base image, so Docker must be in Windows container mode.

Fix:

1. Right-click Docker Desktop tray icon → **Switch to Windows containers**
2. Verify:

```powershell
docker info --format "{{.OSType}}"   # must print: windows
```

1. Rebuild:

```powershell
docker build --no-cache -f C:\MV-ISO\Dockerfile.pwsh -t win11-unattend-iso-pwsh C:\MV-ISO
```

### Docker (PowerShell): `oscdimg` not found inside container

If ADK installation failed or `oscdimg` is not on `PATH` after image build:

1. Verify the ADK install step completed:

```powershell
docker run --rm --entrypoint powershell.exe win11-unattend-iso-pwsh -Command "oscdimg /?"
```

1. If not found, rebuild with `--no-cache` to force fresh ADK download:

```powershell
docker build --no-cache -f C:\MV-ISO\Dockerfile.pwsh -t win11-unattend-iso-pwsh C:\MV-ISO
```

### What We Learned

1. **Container OS must match Docker engine mode.**
   - If `docker info --format "{{.OSType}}"` is `linux`, use Linux base images.
   - If it is `windows`, use Windows base images.

2. **PowerShell script is Windows-only; use the shell script for Linux.**
   - `build-winiso.ps1` requires Windows and `oscdimg` (ADK). For Linux/WSL, use `build-winiso.sh` with `xorriso` and `p7zip-full`.

3. **Builder label is an immediate diagnostic signal.**
   - Seeing `docker:desktop-linux` in build output explains why `mcr.microsoft.com/windows/*` images fail.

4. **Path and mount style follow container OS.**
   - Linux containers should use Linux paths inside the container (for example `/mnt/c/...`).
   - Windows containers should use Windows paths inside the container (for example `C:\...`).

5. **MCR image tags must exist.**
   - Invalid/nonexistent tags fail before any Dockerfile build steps run.

6. **Use `--no-cache` while troubleshooting.**
   - This avoids stale layers masking Dockerfile/script changes.

7. **Avoid host symlink ambiguity for build context files.**
   - When building from Windows PowerShell, prefer real files in `C:\MV-ISO` for `Dockerfile.pwsh` and scripts.

8. **Dedicated Dockerfiles per OS are simpler and more reliable than cross-platform branching in a single Dockerfile.**
   - A single Dockerfile that tries to support both Linux and Windows engines adds fragile conditional logic and is harder to debug.
   - Separate `Dockerfile` (Linux) and `Dockerfile.pwsh` (Windows) keeps each path clean, independently testable, and clearly named.

## Unattended Configuration

The `autounattend.xml` is provided by [UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall) - a streamlined Windows 11 unattended installation configuration for a minimal setup with the latest updates.

---

## Inspecting ISO Contents Without Extracting

Use `7z` to check whether a file exists inside an ISO or read its contents directly, without extracting the whole image.

### Check if a file exists in an ISO

**Bash (WSL/Linux):**

```bash
7z l <iso_path> <file_path_inside_iso>
# Example: list all files under BrowserInstallers/
7z l /mnt/c/MV-ISO/win11-min-brave-bash.iso BrowserInstallers/
```

**PowerShell (Host Windows):**

```powershell
& "C:\Program Files\7-Zip\7z.exe" l "C:\MV-ISO\win11-min-brave-bash.iso" "BrowserInstallers/"
```

**PowerShell (WSL native pwsh):**

```powershell
7z l /mnt/c/MV-ISO/win11-min-brave-bash.iso BrowserInstallers/
```

### View the contents of a file inside an ISO (no extraction)

The `-so` flag tells `7z` to write the extracted file to stdout instead of disk.

**Bash (WSL/Linux):**

```bash
# View a .cmd script embedded in the ISO
7z e -so /mnt/c/MV-ISO/win11-min-brave-bash.iso "sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/install-browsers-once.cmd"

# View the download-links.txt embedded in the ISO
7z e -so /mnt/c/MV-ISO/win11-min-brave-bash.iso BrowserInstallers/download-links.txt
```

**PowerShell (Host Windows):**

```powershell
& "C:\Program Files\7-Zip\7z.exe" e -so "C:\MV-ISO\win11-min-brave-bash.iso" "sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/install-browsers-once.cmd"
& "C:\Program Files\7-Zip\7z.exe" e -so "C:\MV-ISO\win11-min-brave-bash.iso" "BrowserInstallers/download-links.txt"
```

**PowerShell (WSL native pwsh):**

```powershell
7z e -so /mnt/c/MV-ISO/win11-min-brave-bash.iso "sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/install-browsers-once.cmd"
7z e -so /mnt/c/MV-ISO/win11-min-brave-bash.iso BrowserInstallers/download-links.txt
```

> **Tip:** Pipe through `Select-String` (PowerShell) or `grep` (bash) to search inside the file:
>
> ```bash
> 7z e -so /mnt/c/MV-ISO/win11-min.iso BrowserInstallers/download-links.txt | grep brave
> ```
>
> ```powershell
> 7z e -so /mnt/c/MV-ISO/win11-min.iso BrowserInstallers/download-links.txt | Select-String brave
> ```

---

## Development Environment Setup (VS Code + WSL)

## Keep WSL Repo Mirrored to Windows Folder

If you want to edit only in WSL at `/home/warha/Win11-Unattend-ISO` and test Windows containers from `C:\admin-PS`, use the included sync script.

### One-way mirror (WSL -> Windows)

```bash
cd /home/warha/Win11-Unattend-ISO

# Preview what will change
bash ./sync-to-windows.sh --dry-run

# Apply mirror sync
bash ./sync-to-windows.sh
```

Default destination is `/mnt/c/admin-PS` (Windows path `C:\admin-PS`).

You can also pass a custom destination:

```bash
bash ./sync-to-windows.sh /mnt/c/admin-PS
```

### Notes

- This is a one-way mirror from WSL to Windows.
- It uses `--delete`, so files removed in WSL are also removed from `C:\admin-PS`.
- It excludes `.git/`, editor folders, `*.iso`, `autounattend.xml`, and common temp/log files.

For Windows container tests, run Docker build from `C:\admin-PS` in host Windows PowerShell after syncing.

### Problem: PowerShell Extension failed to start on Linux/WSL

The VS Code Machine `settings.json` had Linux terminal profiles pointing to Windows `.exe` paths, which caused the PowerShell Language Server to crash on startup:

```bash
[error] Extension Terminal is undefined.
[error] PowerShell Language Server process didn't start!
```

Root cause: `terminal.integrated.defaultProfile.linux` was set to `Windows PowerShell` with path `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`, and `powershell.powerShellAdditionalExePaths` listed Windows `.exe` paths. VS Code on Linux cannot use these as a language server host.

### Fix: Native PowerShell 7 in WSL

Install PowerShell 7 natively in Ubuntu/WSL:

```bash
. /etc/os-release
sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm -f packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
pwsh --version
```

Tested with: **PowerShell 7.6.1** on Ubuntu 24.04 (Noble) in WSL2.

### VS Code Machine settings.json — Terminal Profiles

The Machine `settings.json` now defines four clearly named terminal profiles:

| Profile Name | Shell | Location |
| --- | --- | --- |
| `WSL PowerShell 7 (native)` | `pwsh` | Default — native WSL Linux |
| `WSL Bash` | `bash -l` | Native WSL Linux |
| `Host Windows PowerShell 5.1` | `powershell.exe` via `/mnt/c/` | Windows host via WSL interop |
| `Host Windows PowerShell 7` | `pwsh.exe` via `/mnt/c/` | Windows host via WSL interop |

Default terminal: `WSL PowerShell 7 (native)`.

### Symlink: Keep settings.json in the workspace

To manage VS Code Machine settings from this repo instead of editing them directly in `~/.vscode-server`:

```bash
# Create symlink so VS Code reads settings from this workspace file
ln -sfn ~/Win11-Unattend-ISO/settings.json ~/.vscode-server/data/Machine/settings.json

# Verify the link is correct
ls -l ~/.vscode-server/data/Machine/settings.json
```

> **Note:** Use `ln -sfn` (not `ln -s`) so the command is safe to re-run — it replaces any existing symlink or file.
