@echo off
setlocal
title Plutonium Quick Launcher Setup

echo Made by SyncHole

set "ROOT=%LOCALAPPDATA%\PlutoniumQuickLaunch"
set "PSFILE=%ROOT%\Launcher.ps1"
set "BATFILE=%~f0"

if not exist "%ROOT%" mkdir "%ROOT%"

echo Generating Launcher.ps1...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$text=[IO.File]::ReadAllText($env:BATFILE); $marker='###PLUTO_PS_PAYLOAD_7F31###'; $i=$text.LastIndexOf($marker); if($i -lt 0){throw 'Payload marker missing'}; $payload=$text.Substring($i+$marker.Length).TrimStart([char[]](13,10)); [IO.File]::WriteAllText($env:PSFILE,$payload,[Text.Encoding]::UTF8)"

if errorlevel 1 (
    echo Failed to generate Launcher.ps1.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%" -Setup

if errorlevel 1 (
    echo Setup failed.
    pause
    exit /b 1
)

echo.
echo Setup complete.
pause
exit /b

###PLUTO_PS_PAYLOAD_7F31###
param(
    [switch]$Setup,
    [switch]$RegisterTaskOnly,
    [ValidateSet("t6zm","t6mp","t5sp","t5mp","t4sp","t4mp","iw5mp")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$Pluto = Join-Path $env:LOCALAPPDATA "Plutonium"
$Bin = Join-Path $Pluto "bin"
$InstallDir = Join-Path $env:LOCALAPPDATA "PlutoniumQuickLaunch"
$SettingsFile = Join-Path $InstallDir "settings.json"
$IconDir = Join-Path $InstallDir "icons"
$Config = Join-Path $Pluto "config.json"
$Info = Join-Path $Pluto "info.json"
$Bootstrapper = Join-Path $Bin "plutonium-bootstrapper-win32.exe"
$Updater = Join-Path $InstallDir "plutonium.exe"
$UpdateScript = Join-Path $InstallDir "SilentUpdate.ps1"
$Desktop = [Environment]::GetFolderPath("Desktop")

$Games = @(
    [pscustomobject]@{N=1;Name="BO2 Zombies";Mode="t6zm";Ids=@("212910","202970")}
    [pscustomobject]@{N=2;Name="BO2 Multiplayer";Mode="t6mp";Ids=@("202970","202990")}
    [pscustomobject]@{N=3;Name="BO1 Zombies";Mode="t5sp";Ids=@("42700")}
    [pscustomobject]@{N=4;Name="BO1 Multiplayer";Mode="t5mp";Ids=@("42710")}
    [pscustomobject]@{N=5;Name="WaW Zombies";Mode="t4sp";Ids=@("10090")}
    [pscustomobject]@{N=6;Name="WaW Multiplayer";Mode="t4mp";Ids=@("10090")}
    [pscustomobject]@{N=7;Name="MW3 Multiplayer";Mode="iw5mp";Ids=@()}
)

function Show-LauncherError {
    param([string]$Message)

    Write-Host ""
    Write-Host "========== LAUNCHER ERROR ==========" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Yellow
    Write-Host "====================================" -ForegroundColor Red
    Read-Host "Press Enter to close"
}

function Get-Libraries {
    $roots = @()

    $key = Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
    if ($key.SteamPath) { $roots += $key.SteamPath }

    foreach ($reg in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )) {
        $key = Get-ItemProperty $reg -ErrorAction SilentlyContinue
        if ($key.InstallPath) { $roots += $key.InstallPath }
    }

    $libraries = @()

    foreach ($root in ($roots | Select-Object -Unique)) {
        $root = $root.Replace('/', '\')
        $libraries += $root
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"

        if (Test-Path $vdf) {
            $content = Get-Content $vdf -Raw

            foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }

    return @(
        $libraries |
        Where-Object { Test-Path (Join-Path $_ "steamapps") } |
        Select-Object -Unique
    )
}

function Find-Game {
    param([string[]]$AppIds)

    foreach ($library in @(Get-Libraries)) {
        foreach ($id in $AppIds) {
            $manifest = Join-Path $library "steamapps\appmanifest_$id.acf"
            if (-not (Test-Path $manifest)) { continue }

            $content = Get-Content $manifest -Raw
            $match = [regex]::Match($content, '"installdir"\s+"([^"]+)"')
            if (-not $match.Success) { continue }

            $path = Join-Path $library ("steamapps\common\" + $match.Groups[1].Value)
            if (Test-Path $path -PathType Container) {
                return [pscustomobject]@{
                    AppId = $id
                    Path = (Resolve-Path $path).Path
                }
            }
        }
    }

    return $null
}

function Install-GameIcons {
    New-Item -ItemType Directory -Force -Path $IconDir | Out-Null

    $iconNames = @(
        "iw5mp.ico","iw5sp.ico","t4mp.ico","t4sp.ico",
        "t5mp.ico","t5sp.ico","t6mp.ico","t6zm.ico"
    )

    foreach ($iconName in $iconNames) {
        $iconPath = Join-Path $IconDir $iconName
        $temp = "$iconPath.download"
        $url = "https://raw.githubusercontent.com/syncholex/PlutoniumLauncherSkip/main/icons/$iconName"

        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $temp
            if ((Get-Item $temp).Length -lt 100) {
                throw "Downloaded icon is invalid."
            }
            Move-Item $temp $iconPath -Force
        }
        catch {
            Remove-Item $temp -Force -ErrorAction SilentlyContinue
            Write-Warning "Could not download $iconName."
        }
    }
}

function New-GameShortcut {
    param(
        [string]$Name,
        [string]$GameMode,
        [string]$GamePath
    )

    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcutName = "Plutonium - $Name"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $Desktop "$shortcutName.lnk"))

    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoExit -NoProfile -ExecutionPolicy Bypass -File "' +
        $PSCommandPath + '" -Mode ' + $GameMode
    $shortcut.WorkingDirectory = $Pluto
    $shortcut.Description = "Launch $Name through Plutonium"

    $iconName = switch ($GameMode) {
        "t6zm"  { "t6zm.ico" }
        "t6mp"  { "t6mp.ico" }
        "t5sp"  { "t5sp.ico" }
        "t5mp"  { "t5mp.ico" }
        "t4sp"  { "t4sp.ico" }
        "t4mp"  { "t4mp.ico" }
        "iw5mp" { "iw5mp.ico" }
    }

    $iconPath = Join-Path $IconDir $iconName
    if (Test-Path $iconPath) {
        $shortcut.IconLocation = "$iconPath,0"
    }

    $shortcut.Save()
    Write-Host "Created shortcut: $shortcutName" -ForegroundColor Green
}

function Install-Updater {
    $temp = "$Updater.download"

    Write-Host "Downloading Plutonium updater..."

    Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "https://cdn.plutonium.pw/updater/plutonium.exe" `
        -OutFile $temp

    if (-not (Test-Path $temp) -or (Get-Item $temp).Length -lt 100000) {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        throw "Updater download failed validation."
    }

    Move-Item $temp $Updater -Force
    Write-Host "Updater saved outside Plutonium's update-managed directory."
}

function Register-HiddenUpdater {
    $wrapper = @'
$ErrorActionPreference = "Stop"
$updater = Join-Path $env:LOCALAPPDATA "PlutoniumQuickLaunch\plutonium.exe"
$log = Join-Path $env:LOCALAPPDATA "PlutoniumQuickLaunch\updater.log"

try {
    if (-not (Test-Path $updater)) {
        throw "Updater executable not found."
    }

    # Hidden task session: no interactive desktop is available.
    $process = Start-Process -FilePath $updater `
        -WorkingDirectory (Split-Path $updater) -PassThru

    Wait-Process -Id $process.Id -Timeout 600 -ErrorAction SilentlyContinue
    $process.Refresh()

    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Add-Content $log "$(Get-Date -Format s) Updater stopped after 10-minute timeout."
    }
}
catch {
    Add-Content $log "$(Get-Date -Format s) $($_.Exception.Message)"
}
'@

    [IO.File]::WriteAllText(
        $UpdateScript,
        $wrapper,
        [Text.Encoding]::UTF8
    )

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    $action = New-ScheduledTaskAction `
        -Execute $powershell `
        -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UpdateScript`"" `
        -WorkingDirectory $InstallDir

    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User $identity)
        (New-ScheduledTaskTrigger -Daily -At 3:00AM)
    )

    $principal = New-ScheduledTaskPrincipal `
        -UserId $identity `
        -LogonType S4U `
        -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName "Plutonium Quick Launcher Hidden Updater" `
        -Action $action `
        -Trigger $triggers `
        -Principal $principal `
        -Settings $settings `
        -Description "Runs the Plutonium updater at login and daily at 3 AM." `
        -Force | Out-Null
}

function Request-TaskRegistrationElevation {
    Write-Host ""
    Write-Host "Windows denied registration of the hidden updater task." -ForegroundColor Yellow
    Write-Host "Administrator permission may be required to configure this scheduled task."
    Write-Host "This is only for setting up automatic Plutonium updates; game shortcuts do not need admin rights."
    Write-Host "Requesting permission in 5 seconds..."
    Start-Sleep -Seconds 5

    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -RegisterTaskOnly'

    Start-Process -FilePath $powershell `
        -ArgumentList $arguments `
        -Verb RunAs `
        -ErrorAction Stop
}

if ($RegisterTaskOnly) {
    try {
        Register-HiddenUpdater
        Write-Host "Hidden updater task registered successfully."
        Read-Host "Press Enter to close"
        exit 0
    }
    catch {
        Show-LauncherError ("Elevated task registration failed: " + $_.Exception.Message)
        exit 1
    }
}

if ($Setup) {
    try {
        New-Item -ItemType Directory -Force -Path $InstallDir, $Bin, $IconDir | Out-Null

        Write-Host ""
        Write-Host "=== Plutonium Quick Launcher ===" -ForegroundColor Cyan
        Write-Host "1. BO2 Zombies"
        Write-Host "2. BO2 Multiplayer"
        Write-Host "3. BO1 Zombies"
        Write-Host "4. BO1 Multiplayer"
        Write-Host "5. WaW Zombies"
        Write-Host "6. WaW Multiplayer"
        Write-Host "7. MW3 Multiplayer"
        Write-Host ""

        Install-GameIcons
        $choice = Read-Host "Select modes separated by commas (example: 1,2,5,7)"

        $selected = @(
            $choice -split '[,\s]+' |
            Where-Object { $_ -match '^[1-7]$' } |
            ForEach-Object { [int]$_ } |
            Select-Object -Unique
        )

        if (-not $selected.Count) {
            throw "No valid modes selected."
        }

        foreach ($game in ($Games | Where-Object { $selected -contains $_.N })) {
            Write-Host "`nSetting up $($game.Name)..."

            if ($game.Mode -eq "iw5mp") {
                Add-Type -AssemblyName System.Windows.Forms
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $dialog.Description = "Select the downgraded MW3 directory"

                if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                    Write-Host "Skipped MW3."
                    continue
                }

                $gamePath = $dialog.SelectedPath
                [pscustomobject]@{iw5mpPath=$gamePath} |
                    ConvertTo-Json |
                    Set-Content -LiteralPath $SettingsFile -Encoding UTF8
            }
            else {
                $found = Find-Game -AppIds $game.Ids
                if (-not $found) {
                    Write-Warning "No matching Steam manifest and game directory found for $($game.Name). This means my script may be broken: My script is broken and you should show me your install directory so I can fix the script, You have pirated files, and can fuck off, Or The game isn't installed."
                    continue
                }

                $gamePath = $found.Path
                Write-Host "Matched App ID: $($found.AppId)"
                Write-Host "Game directory: $gamePath"
            }

            New-GameShortcut -Name $game.Name -GameMode $game.Mode -GamePath $gamePath
        }

        Install-Updater

        try {
            Register-HiddenUpdater
            Write-Host "Hidden updater scheduled for login and 3:00 AM." -ForegroundColor Green
        }
        catch {
            Write-Host ""
            Write-Host "Task registration error: $($_.Exception.Message)" -ForegroundColor Red

            if ($_.Exception.Message -match 'Access is denied|denied|0x80070005') {
                Request-TaskRegistrationElevation
            }
            else {
                throw
            }
        }

        Write-Host ""
        Write-Host "Setup finished." -ForegroundColor Green
    }
    catch {
        Show-LauncherError $_.Exception.Message
        exit 1
    }

    exit 0
}

try {
    if (-not (Test-Path $Config -PathType Leaf)) {
        throw "Plutonium config.json was not found."
    }

    if (-not (Test-Path $Info -PathType Leaf)) {
        throw "Plutonium info.json was not found."
    }

    if (-not (Test-Path $Bootstrapper -PathType Leaf)) {
        throw "Plutonium bootstrapper not found. Run the official Plutonium launcher first."
    }

    $config = Get-Content $Config -Raw | ConvertFrom-Json
    $infoData = Get-Content $Info -Raw | ConvertFrom-Json
    $revision = [string]$infoData.revision

    if ([string]::IsNullOrWhiteSpace($revision)) {
        throw "Revision was not found in info.json."
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.token)) {
        throw "Plutonium UserToken was not found."
    }

    if ($Mode -eq "iw5mp") {
        if (-not (Test-Path $SettingsFile)) {
            throw "MW3 path settings were not found. Run setup again."
        }

        $mw3Settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        $gamePath = $mw3Settings.iw5mpPath
    }
    else {
        $game = $Games | Where-Object { $_.Mode -eq $Mode } | Select-Object -First 1
        if (-not $game) { throw "Unknown game mode." }

        $found = Find-Game -AppIds $game.Ids
        if (-not $found) { throw "Steam manifest or game directory not found." }

        $gamePath = $found.Path
    }

    if ([string]::IsNullOrWhiteSpace([string]$gamePath) -or
        -not (Test-Path $gamePath -PathType Container)) {
        throw "Game directory does not exist."
    }

    $encrypted = [Convert]::FromBase64String($config.token)

    # Use Windows DPAPI directly. This avoids depending on the
    # ProtectedData managed type being preloaded or exposed by a particular
    # .NET / PowerShell runtime. DPAPI still decrypts only for the current user.
    if (-not ("PlutoDpapiNative" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PlutoDpapiNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct DATA_BLOB
    {
        public int cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CryptUnprotectData(
        ref DATA_BLOB pDataIn,
        IntPtr ppszDataDescr,
        IntPtr pOptionalEntropy,
        IntPtr pvReserved,
        IntPtr pPromptStruct,
        int dwFlags,
        out DATA_BLOB pDataOut);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr hMem);

    public static byte[] Unprotect(byte[] encrypted)
    {
        if (encrypted == null) throw new ArgumentNullException("encrypted");

        DATA_BLOB input = new DATA_BLOB();
        DATA_BLOB output = new DATA_BLOB();
        input.cbData = encrypted.Length;
        input.pbData = Marshal.AllocHGlobal(encrypted.Length);

        try
        {
            Marshal.Copy(encrypted, 0, input.pbData, encrypted.Length);

            if (!CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero,
                IntPtr.Zero, IntPtr.Zero, 0, out output))
            {
                throw new System.ComponentModel.Win32Exception(
                    Marshal.GetLastWin32Error());
            }

            byte[] result = new byte[output.cbData];
            Marshal.Copy(output.pbData, result, 0, output.cbData);
            return result;
        }
        finally
        {
            if (input.pbData != IntPtr.Zero) Marshal.FreeHGlobal(input.pbData);
            if (output.pbData != IntPtr.Zero) LocalFree(output.pbData);
        }
    }
}
"@
    }

    $decrypted = [PlutoDpapiNative]::Unprotect($encrypted)
    $userToken = [Text.Encoding]::UTF8.GetString($decrypted)

    if ([string]::IsNullOrWhiteSpace($userToken)) {
        throw "Decrypted UserToken is empty."
    }

    $response = Invoke-RestMethod `
        -Uri "https://nix.plutonium.pw/api/auth/session" `
        -Method Post `
        -ContentType "application/json" `
        -Headers @{
            Authorization = "UserToken $userToken"
            "X-Plutonium-Revision" = $revision
            "User-Agent" = "Nix/3.0"
        } `
        -Body (@{game=$Mode} | ConvertTo-Json -Compress) `
        -ErrorAction Stop

    $sessionToken = [string]$response.token
    if ([string]::IsNullOrWhiteSpace($sessionToken)) {
        throw "Session API did not return a token."
    }

    $arguments = '"' + $Mode + '" "' + $gamePath + '" -token "' + $sessionToken + '" -lgbtq'

    Start-Process `
        -FilePath $Bootstrapper `
        -ArgumentList $arguments `
        -WorkingDirectory $Pluto `
        -ErrorAction Stop
}
catch {
    Show-LauncherError $_.Exception.Message
    exit 1
}

Read-Host "Press Enter to close"
