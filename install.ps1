# One-command install of the latest Dhoti Dash release on Windows.
#
#   irm https://raw.githubusercontent.com/ahab94/dhoti-dash/main/install.ps1 | iex
#
# Installs into %LOCALAPPDATA%\DhotiDash (no admin rights needed),
# adds a Start menu shortcut, and starts the game.
# Uninstall: delete that folder and the "Dhoti Dash" Start menu shortcut.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$repo = 'ahab94/dhoti-dash'
$name = 'Dhoti Dash'
$dest = Join-Path $env:LOCALAPPDATA 'DhotiDash'

Write-Host 'Finding the latest release...'
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$base = "https://github.com/$repo/releases/download/"
$asset = $release.assets | Where-Object { $_.name -like '*-windows.zip' -and $_.browser_download_url.StartsWith($base) } | Select-Object -First 1
$sums = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' -and $_.browser_download_url.StartsWith($base) } | Select-Object -First 1
if (-not $asset) { throw "No Windows build in the latest release. See https://github.com/$repo/releases" }
if (-not $sums) { throw "The latest release has no SHA256SUMS.txt, so the download can't be verified. See https://github.com/$repo/releases" }

$zip = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
# Verify the zip against the published checksum before unpacking or running anything.
$sumsText = (Invoke-WebRequest $sums.browser_download_url -UseBasicParsing).Content
if ($sumsText -is [byte[]]) { $sumsText = [Text.Encoding]::UTF8.GetString($sumsText) }
$want = ($sumsText -split "`n" | Where-Object { $_ -match [regex]::Escape($asset.name) + '\s*$' } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
$got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if (-not $want -or $want.ToLower() -ne $got) { Remove-Item $zip; throw "Checksum mismatch for $($asset.name): refusing to install." }
Write-Host 'Checksum OK.' 
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive $zip -DestinationPath $dest -Force
Remove-Item $zip

$exe = Join-Path $dest 'DhotiDash.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$name.lnk"
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $dest
$link.Save()

Write-Host "Installed to $dest"
Write-Host "Find '$name' in the Start menu. If SmartScreen warns, choose More info > Run anyway (the game isn't code-signed)."
Start-Process $exe
