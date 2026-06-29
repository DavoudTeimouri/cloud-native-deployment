# Windows Server Operations Workstation Setup

## Overview

This guide covers the setup of a Windows Server workstation for managing
a cloud-native Kubernetes deployment. The workstation provides an operations
console with all necessary tooling.

---

## 1. WSL2 Installation

### 1.1 Prerequisites

- Windows Server 2019/2022 or Windows 10/11
- Hardware virtualization enabled in BIOS (VT-x/AMD-V)

### 1.2 Install WSL2

Open PowerShell as Administrator:

```powershell
# Install WSL feature
wsl --install

# Set WSL2 as default
wsl --set-default-version 2

# Install Ubuntu 22.04 distribution
wsl --install -d Ubuntu-22.04

# Restart if prompted
```

### 1.3 Verify Installation

```powershell
wsl --list --verbose
# Should show Ubuntu-22.04 running on VERSION: 2
```

### 1.4 WSL2 Configuration

Create `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

---

## 2. Docker Desktop with WSL2 Backend

### 2.1 Installation

1. Download Docker Desktop installer from internal file share
   (air-gapped: installer pre-staged)
2. Run `Docker Desktop Installer.exe`
3. Enable "Use WSL 2 instead of Hyper-V" during installation
4. Restart when prompted

### 2.2 Configuration

In Docker Desktop Settings:
- **General**: Enable "Start Docker Desktop when you sign in"
- **Resources > WSL Integration**: Enable integration with Ubuntu-22.04
- **Docker Engine**: Configure registry mirrors for air-gap:

```json
{
  "registry-mirrors": [
    "https://nexus.internal.lan:5000",
    "https://harbor.internal.lan"
  ],
  "insecure-registers": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### 2.3 Verify

```powershell
docker run hello-world
docker info | findstr "Operating System"
# Should show "Operating System: Docker Desktop" with WSL2 backend
```

---

## 3. SSH Client (OpenSSH)

### 3.1 Installation

```powershell
# Check if installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### 3.2 Configuration

Create/edit `%USERPROFILE%\.ssh\config`:

```ssh-config
# Kubernetes cluster nodes
Host k8s-master-*
    User deploy
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no

Host k8s-worker-*
    User deploy
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no

# Jump host / bastion
Host bastion
    User admin
    IdentityFile ~/.ssh/id_ed25519
    HostName bastion.internal.lan
```

### 3.3 Generate Key Pair

```powershell
ssh-keygen -t ed25519 -C "ops-team@company.com" -f "$env:USERPROFILE\.ssh\id_ed25519" -N ""
```

---

## 4. kubectl Installation

### 4.1 Download from Internal Nexus

```powershell
# Download kubectl from internal mirror (air-gapped)
$url = "https://nexus.internal.lan/repository/kubernetes-release/v1.28.4/bin/linux/amd64/kubectl"
$out = "$env:USERPROFILE\bin\kubectl.exe"

# Create bin directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\bin"

# Download
Invoke-WebRequest -Uri $url -OutFile $out

# Add to PATH if not already
$path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($path -notlike "*$env:USERPROFILE\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$path;$env:USERPROFILE\bin", "User")
}
```

### 4.2 Verify

```powershell
kubectl version --client
```

### 4.3 Copy kubeconfig

```powershell
# Copy kubeconfig from bastion/jump host
scp bastion:~/.kube/config $env:USERPROFILE\.kube\config
```

---

## 5. Helm Installation

### 5.1 Download

```powershell
$url = "https://nexus.internal.lan/repository/helm/v3.13.2/helm-v3.13.2-windows-amd64.zip"
$tmp = "$env:TEMP\helm.zip"

Invoke-WebRequest -Uri $url -OutFile $tmp
Expand-Archive -Path $tmp -DestinationPath "$env:TEMP\helm" -Force
Copy-Item "$env:TEMP\helm\windows-amd64\helm.exe" "$env:USERPROFILE\bin\helm.exe"
```

### 5.2 Verify

```powershell
helm version
```

### 5.3 Add Internal Chart Repository

```powershell
helm repo add internal https://nexus.internal.lan/repository/helm-charts
helm repo update
```

---

## 6. Rancher CLI

### 6.1 Installation

```powershell
$url = "https://nexus.internal.lan/repository/rancher/cli/v2.8.0/rancher-windows-amd64-v2.8.0.zip"
$tmp = "$env:TEMP\rancher.zip"

Invoke-WebRequest -Uri $url -OutFile $tmp
Expand-Archive -Path $tmp -DestinationPath "$env:TEMP\rancher" -Force
Copy-Item "$env:TEMP\rancher\rancher.exe" "$env:USERPROFILE\bin\rancher.exe"
```

### 6.2 Configuration

```powershell
# Set Rancher server URL and token
$env:RANCHER_URL = "https://rancher.internal.lan"
$env:RANCHER_ACCESS_KEY = "token-xxxxx"
$env:RANCHER_SECRET_KEY = "xxxxxxxx"
```

---

## 7. Git Installation and Configuration

### 7.1 Installation

```powershell
# Download from internal Nexus (air-gapped)
$url = "https://nexus.internal.lan/repository/git/Git-2.42.0-64-bit.exe"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\git-installer.exe"
Start-Process -FilePath "$env:TEMP\git-installer.exe" -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh" -Wait
```

### 7.2 Configuration

```powershell
git config --global user.name "Operations Team"
git config --global user.email "ops-team@company.com"
git config --global init.defaultBranch main
git config --global core.autocrlf true
git config --global pull.rebase false
```

### 7.3 Git for Windows Credential Manager

```powershell
git config --global credential.helper manager
```

---

## 8. RDP Access Configuration

### 8.1 Enable RDP (if not already enabled)

```powershell
# Enable Remote Desktop
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

# Enable firewall rule
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Allow only from management subnet
New-NetFirewallRule -DisplayName "RDP Management Subnet" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -RemoteAddress 10.0.0.0/24
```

### 8.2 Security Hardening

```powershell
# Require Network Level Authentication
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

# Set encryption level to High
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value 3

# Limit RDP to specific group
# Use Local Users and Groups to add operators to "Remote Desktop Users" group
```

---

## 9. Windows Terminal Setup

### 9.1 Installation

```powershell
# Install from Windows Package Manager (if available)
winget install Microsoft.WindowsTerminal

# Or install from internal file share (air-gapped)
# Download MSIX bundle from internal Nexus
```

### 9.2 Configuration

Create/edit `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`:

```json
{
    "profiles": {
        "list": [
            {
                "name": "Ubuntu (WSL)",
                "commandline": "wsl.exe -d Ubuntu-22.04",
                "icon": "ms-appdata:///local/icons/ubuntu.png",
                "startingDirectory": "//wsl$/Ubuntu-22.04/home/deploy",
                "font": {
                    "face": "Cascadia Code",
                    "size": 11
                }
            },
            {
                "name": "PowerShell",
                "commandline": "powershell.exe",
                "icon": "ms-appdata:///local/icons/powershell.ico"
            },
            {
                "name": "Command Prompt",
                "commandline": "cmd.exe",
                "icon": "ms-appdata:///local/icons/cmd.ico"
            }
        ]
    },
    "schemes": [
        {
            "name": "Campbell",
            "background": "#0C0C0C",
            "foreground": "#CCCCCC"
        }
    ],
    "defaultProfile": "{your-wsl-profile-guid}",
    "theme": "dark",
    "tabBar": {
        "visible": true
    }
}
```

### 9.3 Recommended Font

Install **Cascadia Code** or **JetBrains Mono** for terminal use:

```powershell
winget install Microsoft.CascadiaCode
```

---

## 10. Verification Checklist

After completing setup:

- [ ] WSL2 running Ubuntu-22.04
- [ ] Docker Desktop running with WSL2 backend
- [ ] SSH client configured with keys
- [ ] kubectl installed and connected to cluster
- [ ] Helm installed with internal repo configured
- [ ] Rancher CLI installed
- [ ] Git installed and configured
- [ ] RDP accessible from management subnet
- [ ] Windows Terminal configured with profiles

---

## 11. Additional Tools (Optional)

| Tool | Purpose | Installation |
|------|---------|-------------|
| k9s | Kubernetes TUI | `choco install k9s` or download binary |
| kubectx | Context switching | `choco install kubectx` |
| stern | Multi-pod logging | Download from GitHub releases |
| jq | JSON processing | `winget install jqlang.jq |
| VS Code | Editor | `winget install Microsoft.VisualStudioCode` |
| Postman | API testing | `winget install Postman.Postman` |
