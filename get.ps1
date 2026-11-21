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
  $src = Get-ChildItem (Join-Path $tmp 'x') -Directory | Where-Object { (Test-Path (Join-Path $_.FullName 'install.ps1')) -and (Test-Path (Join-Path $_.FullName 'agent-bridge\package.ps1')) } | ForEach-Object { $_.FullName } | Select-Object -First 1
  if (-not $src) { throw 'installer files not found in the archive' }
  $dest = Join-Path $app 'app'
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Path $app -Force | Out-Null
  Copy-Item $src $dest -Recurse -Force
  Write-Host "  Files ready in $dest (ref: $ref)" -ForegroundColor Green
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
$extra = @(); if ($env:AGENT_BRIDGE_ARGS) { $extra = $env:AGENT_BRIDGE_ARGS -split '\s+' | Where-Object { $_ } }
& (Join-Path $dest 'install.ps1') @extra
