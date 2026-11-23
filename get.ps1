# yerux-skills bootstrap (Windows): installs agent-bridge (featured) and any of the other skills.
#   powershell -c "irm https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.ps1 | iex"
# Env: $env:AGENT_BRIDGE_REF = tag|branch|commit (default main) · $env:AGENT_BRIDGE_REPO = owner/repo
#      $env:AGENT_BRIDGE_HOME = install dir · $env:AGENT_BRIDGE_ZIP = local archive (offline/testing)
# Installer options: set $env:AGENT_BRIDGE_ARGS = '-Yes' (or '-Uninstall', '-List', '-DryRun') before running.
$ErrorActionPreference = 'Stop'
$repo = if ($env:AGENT_BRIDGE_REPO) { $env:AGENT_BRIDGE_REPO } else { 'yervix10/yerux-skills' }
$ref = if ($env:AGENT_BRIDGE_REF) { $env:AGENT_BRIDGE_REF } else { 'main' }
$app = if ($env:AGENT_BRIDGE_HOME) { $env:AGENT_BRIDGE_HOME } else { Join-Path $env:USERPROFILE '.agent-bridge' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("agent-bridge-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  $zip = Join-Path $tmp 'src.zip'
  if ($env:AGENT_BRIDGE_ZIP) { Copy-Item $env:AGENT_BRIDGE_ZIP $zip }
  else { Write-Host "  Downloading $repo@$ref ..." -ForegroundColor Cyan; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$repo/zip/$ref" -OutFile $zip }
  Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x') -Force
  $src = Get-ChildItem (Join-Path $tmp 'x') -Directory | Where-Object { (Test-Path (Join-Path $_.FullName 'install.ps1')) -and (Test-Path (Join-Path $_.FullName 'skills\agent-bridge\package.ps1')) } | ForEach-Object { $_.FullName } | Select-Object -First 1
  if (-not $src) { throw 'installer files not found in the archive' }
  $dest = Join-Path $app 'app'
  # An antivirus or a running process can hold files of an older copy: retry, and if it still fails update in place instead of aborting half-way.
  if (Test-Path $dest) {
    $removed = $false
    for ($i = 1; $i -le 4 -and -not $removed; $i++) {
      try { Remove-Item $dest -Recurse -Force -ErrorAction Stop; $removed = $true } catch { $lockMsg = $_.Exception.Message; if ($i -lt 4) { Start-Sleep -Seconds 2 } } }
    if (-not $removed) { Write-Host "  ! some files in $dest are in use ($lockMsg)" -ForegroundColor Yellow; Write-Host '    Updating the rest in place; close any program using them and run this again to finish.' -ForegroundColor Yellow }
  }
  New-Item -ItemType Directory -Path $app -Force | Out-Null
  if (Test-Path $dest) {
    # file by file, so one locked file cannot stop the rest from being updated
    $busy = @()
    Get-ChildItem $src -Recurse -File -Force | ForEach-Object {
      $rel = $_.FullName.Substring($src.Length).TrimStart('\'); $to = Join-Path $dest $rel
      try { New-Item -ItemType Directory -Path (Split-Path $to) -Force -ErrorAction Stop | Out-Null; Copy-Item $_.FullName $to -Force -ErrorAction Stop } catch { $busy += $rel } }
    if ($busy.Count) { Write-Host "  ! $($busy.Count) file(s) in use were not updated (the old copy stays): $(($busy | Select-Object -First 5) -join ', ')" -ForegroundColor Yellow }
  } else { Copy-Item $src $dest -Recurse -Force }
  Write-Host "  Files ready in $dest (ref: $ref)" -ForegroundColor Green
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
$extra = @(); if ($env:AGENT_BRIDGE_ARGS) { $extra = @($env:AGENT_BRIDGE_ARGS -split '\s+' | Where-Object { $_ }) }   # @() keeps a single argument an array (a lone string cannot be splatted)
# Run the installer in its own PowerShell with a process-scoped Bypass: Windows client editions ship with scripts disabled (Restricted),
# and `irm | iex` itself is allowed but `& install.ps1` is not. This needs no administrator rights.
$psExe = (Get-Process -Id $PID).Path; if (-not $psExe) { $psExe = 'powershell.exe' }
& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install.ps1') @extra
if ($LASTEXITCODE -ne 0) {
  $pol = Get-ExecutionPolicy -List | Where-Object { $_.Scope -in 'MachinePolicy', 'UserPolicy' -and $_.ExecutionPolicy -ne 'Undefined' }
  if ($pol) { Write-Host "  ! PowerShell scripts are restricted by a policy of your organisation ($($pol[0].Scope) = $($pol[0].ExecutionPolicy)); ask your administrator or run the installer from a machine you control." -ForegroundColor Yellow }
}
