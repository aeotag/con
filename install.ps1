# ============================================================================
# con - Installation Script (Windows / PowerShell)
# Installs all dependencies and sets up the 'con' CLI tool.
#
# Usage (run as Administrator):
#   .\install.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

# --- Colors via ANSI -------------------------------------------------------
function Write-Info    { Write-Host "[INFO]  $args" -ForegroundColor Blue }
function Write-Ok      { Write-Host "[OK]    $args" -ForegroundColor Green }
function Write-Warn    { Write-Host "[WARN]  $args" -ForegroundColor Yellow }
function Write-Err     { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }
function Write-Step    { Write-Host "`n>> $args" -ForegroundColor Cyan }

# --- Determine install directory -------------------------------------------
$ConDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path "$ConDir\main.lua")) {
    $ConDir = Get-Location
    if (-not (Test-Path "$ConDir\main.lua")) {
        Write-Err "Cannot find 'main.lua'. Run this script from the con project directory."
    }
}
Write-Info "Install directory: $ConDir"

# --- Check for Chocolatey or Scoop ----------------------------------------
Write-Step "Checking package manager..."

$PkgManager = $null

if (Get-Command "scoop" -ErrorAction SilentlyContinue) {
    $PkgManager = "scoop"
    Write-Ok "Found Scoop"
} elseif (Get-Command "choco" -ErrorAction SilentlyContinue) {
    $PkgManager = "choco"
    Write-Ok "Found Chocolatey"
} else {
    Write-Warn "No package manager found. Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $PkgManager = "choco"
    Write-Ok "Chocolatey installed"
}

function Install-Package {
    param([string]$ChocoName, [string]$ScoopName)

    if ($PkgManager -eq "scoop") {
        scoop install $ScoopName
    } else {
        choco install $ChocoName -y
    }
}

# ============================================================================
# 1. INSTALL LUA
# ============================================================================
Write-Step "Checking Lua..."

if (Get-Command "lua" -ErrorAction SilentlyContinue) {
    Write-Ok "Lua already installed: $(lua -v 2>&1)"
} else {
    Write-Info "Installing Lua..."
    Install-Package -ChocoName "lua" -ScoopName "lua"

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Get-Command "lua" -ErrorAction SilentlyContinue) {
        Write-Ok "Lua installed: $(lua -v 2>&1)"
    } else {
        Write-Err "Lua installation failed."
    }
}

# ============================================================================
# 2. INSTALL LUAJIT (optional)
# ============================================================================
Write-Step "Checking LuaJIT..."

if (Get-Command "luajit" -ErrorAction SilentlyContinue) {
    Write-Ok "LuaJIT already installed: $(luajit -v 2>&1)"
} else {
    Write-Info "Installing LuaJIT..."
    try {
        Install-Package -ChocoName "luajit" -ScoopName "luajit"
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Get-Command "luajit" -ErrorAction SilentlyContinue) {
            Write-Ok "LuaJIT installed: $(luajit -v 2>&1)"
        } else {
            Write-Warn "LuaJIT not available (optional)"
        }
    } catch {
        Write-Warn "LuaJIT installation failed (optional — Lua 5.4 will be used instead)"
    }
}

# ============================================================================
# 3. INSTALL LUAROCKS
# ============================================================================
Write-Step "Checking LuaRocks..."

if (Get-Command "luarocks" -ErrorAction SilentlyContinue) {
    Write-Ok "LuaRocks already installed: $(luarocks --version 2>&1 | Select-Object -First 1)"
} else {
    Write-Info "Installing LuaRocks..."
    Install-Package -ChocoName "luarocks" -ScoopName "luarocks"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Get-Command "luarocks" -ErrorAction SilentlyContinue) {
        Write-Ok "LuaRocks installed: $(luarocks --version 2>&1 | Select-Object -First 1)"
    } else {
        Write-Err "LuaRocks installation failed. Install manually: https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Windows"
    }
}

# ============================================================================
# 4. INSTALL LYAML
# ============================================================================
Write-Step "Checking lyaml..."

$lyamlCheck = lua -e "require('lyaml')" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "lyaml already installed"
} else {
    Write-Info "Installing lyaml via LuaRocks..."

    # lyaml needs libyaml — on Windows this is tricky
    Write-Warn "lyaml requires libyaml C library. If this fails, install libyaml manually."

    try {
        luarocks install lyaml
        Write-Ok "lyaml installed"
    } catch {
        Write-Warn "lyaml installation failed. You may need to:"
        Write-Warn "  1. Install Visual Studio Build Tools (C compiler)"
        Write-Warn "  2. Install libyaml from https://github.com/yaml/libyaml"
        Write-Warn "  3. Run: luarocks install lyaml"
    }
}

# ============================================================================
# 5. SET UP POWERSHELL ALIAS
# ============================================================================
Write-Step "Setting up PowerShell alias..."

$AliasLine = "function con { lua `"$ConDir\main.lua`" @args }"

$ProfilePath = $PROFILE.CurrentUserAllHosts
$ProfileDir  = Split-Path -Parent $ProfilePath

if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

if (Test-Path $ProfilePath) {
    $profileContent = Get-Content $ProfilePath -Raw
    if ($profileContent -match "function con") {
        $profileContent = $profileContent -replace "function con \{[^}]+\}", $AliasLine
        Set-Content -Path $ProfilePath -Value $profileContent
        Write-Ok "Updated con function in $ProfilePath"
    } else {
        Add-Content -Path $ProfilePath -Value "`n$AliasLine"
        Write-Ok "Added con function to $ProfilePath"
    }
} else {
    Set-Content -Path $ProfilePath -Value $AliasLine
    Write-Ok "Created $ProfilePath with con function"
}

# Also set for current session
Invoke-Expression $AliasLine

# ============================================================================
# 6. INITIALIZE CON CONFIG
# ============================================================================
Write-Step "Initializing con configuration..."

lua "$ConDir\main.lua" init

# ============================================================================
# 7. SUMMARY
# ============================================================================
Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  con installed successfully!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install dir:  $ConDir"
Write-Host "  Config dir:   $env:USERPROFILE\.config\con\"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Restart PowerShell or run: . `$PROFILE"
Write-Host "    2. Try: con help"
Write-Host "    3. Add a connection: con --name myserver user@10.0.0.1"
Write-Host ""
