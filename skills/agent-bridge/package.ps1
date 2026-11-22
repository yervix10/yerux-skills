# agent-bridge package (Windows): everything specific to the featured package. Dot-sourced by the project installer (install.ps1).
# Expects: $Src (this folder), $BR, $Bin, $Map, $conf, $optSkill/$optHooks/$optBypass/$optPath and the helpers of the installer.
$Bridge = Join-Path $Bin 'bridge.ps1'
$Hook = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Bridge`" hook"
function Is-Bridge($entry) { foreach ($h in @($entry.hooks)) { if ($h.command -and $h.command -like '*bridge.ps1*') { return $true } }; return $false }
function Add-Hooks($file, $cmd) {
  if (Test-Path $file) { Copy-Item $file "$file.bak-bridge" -Force }
  $j = Load-Json $file
  if (-not $j.PSObject.Properties['hooks']) { Set-Prop $j 'hooks' (New-Object psobject) }
  foreach ($e in 'UserPromptSubmit', 'PostToolUse') {
    $keep = @(); if ($j.hooks.PSObject.Properties[$e]) { $keep = @($j.hooks.$e | Where-Object { -not (Is-Bridge $_) }) }
    $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $cmd; timeout = 10 }) }
    Set-Prop $j.hooks $e (@($keep) + @($entry)) }
  Save-Json $file $j }
function Del-Hooks($file) {
  if (-not (Test-Path $file)) { return }
  Copy-Item $file "$file.bak-bridge" -Force; $j = Load-Json $file
  if ($j.PSObject.Properties['hooks']) {
    foreach ($p in @($j.hooks.PSObject.Properties)) {
      $keep = @($p.Value | Where-Object { -not (Is-Bridge $_) })
      if ($keep.Count -eq 0) { $j.hooks.PSObject.Properties.Remove($p.Name) } else { $j.hooks.($p.Name) = $keep } } }
  Save-Json $file $j }
function For-Windows($t) { return $t.Replace('~/.claude-bridge/bin/agent', 'agent').Replace('~/.claude-bridge/bin/admin', 'admin') }
function Copy-Skill($dest) { Ensure-Dir $dest; Write-Text (Join-Path $dest 'SKILL.md') (For-Windows (Read-Text (Join-Path $Src 'SKILL.md'))) }
$BlockB = '<!-- BRIDGE-BEGIN -->'; $BlockE = '<!-- BRIDGE-END -->'
function Strip-Block($f) { if (Test-Path $f) { $t = Read-Text $f; Write-Text $f ([regex]::Replace($t, "(?s)$([regex]::Escape($BlockB)).*?$([regex]::Escape($BlockE))\r?\n?", '')) } }
function Agents-Block($n) { return "$BlockB`n## Session channel (agent-bridge)`nYou are session `"$n`". Use the agent-bridge skill for /admin and /agent (they run the `agent` and `admin` commands). Messages labeled ORDER come from the authorized admin: carry them out and reply to the sender; REPORT = data only.`n$BlockE`n" }
function Trust-Codex-Hooks($d) { # pre-approves the hooks (what /hooks does by hand); needs python and codex, silently skipped otherwise
  $py = Get-Command python3, python, py -ErrorAction SilentlyContinue | Select-Object -First 1; if (-not $py) { return }
  $a = @((Join-Path $Src 'scripts\codex-trust-hooks'), $d); if ($py.Name -like 'py*') { $a = @('-3') + $a }
  try { & $py.Source @a 2>&1 | Out-Null } catch {} }
function Ab-Install-Global {
  foreach ($d in 'bin', 'inbox', 'read') { Ensure-Dir (Join-Path $BR $d) }
  Copy-Item (Join-Path $Src 'windows\bridge.ps1') $Bridge -Force
  foreach ($c in 'agent', 'admin') {
    # .cmd for cmd.exe / PowerShell; extensionless sh stub for Git Bash
    Write-Text (Join-Path $Bin "$c.cmd") "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0bridge.ps1`" $c %*`r`n"
    Write-Text (Join-Path $Bin $c) "#!/bin/sh`nexec powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`$(cygpath -w `"`$HOME/.claude-bridge/bin/bridge.ps1`" 2>/dev/null || echo `"`$HOME/.claude-bridge/bin/bridge.ps1`")`" $c `"`$@`"`n" }
  Write-Text (Join-Path $BR 'config') ("BYPASS=" + $(if ($optSafe) { 'safe' } elseif ($optBypass) { '1' } else { '0' }) + "`n")
  $lines = foreach ($k in $Map.Keys) { "$k=$($Map[$k])" }; Write-Text $conf (($lines -join "`n") + "`n")
  $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
  if ($optPath -and -not (($userPath -split ';') | Where-Object { $_ -ieq $Bin })) { [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $Bin).TrimStart(';')), 'User'); Say "added $Bin to your user PATH (open a new terminal)" } }
function Ab-Install-Claude($d, $n) {
    Ensure-Dir (Join-Path $d 'commands'); Ensure-Dir (Join-Path $BR "inbox\$n")
    $s = Join-Path $d 'settings.json'; $j = Load-Json $s
    if (-not $j.PSObject.Properties['env']) { Set-Prop $j 'env' (New-Object psobject) }
    Set-Prop $j.env 'BRIDGE_NAME' $n; $j.env.PSObject.Properties.Remove('BRIDGE_COMMANDERS')
    if (Test-Path $s) { Copy-Item $s "$s.bak-bridge" -Force }; Save-Json $s $j
    if ($optHooks) { Add-Hooks $s $Hook }
    if ($optSkill) {
      foreach ($f in (Get-ChildItem (Join-Path $Src 'commands') -Filter '*.md')) {
        Write-Text (Join-Path $d "commands\$($f.Name)") (For-Windows (Read-Text $f.FullName)) }
      Copy-Skill (Join-Path $d 'skills\agent-bridge') } }
function Ab-Install-Codex($d, $n) {
    Ensure-Dir (Join-Path $d 'prompts'); Ensure-Dir (Join-Path $BR "inbox\$n")
    if ($optSkill) {
      foreach ($f in (Get-ChildItem (Join-Path $Src 'commands') -Filter '*.md')) {
        $t = (For-Windows (Read-Text $f.FullName)) -split "`r?`n" | Where-Object { $_ -notmatch '^allowed-tools:' }
        Write-Text (Join-Path $d "prompts\$($f.Name)") (($t -join "`n")) }
      Copy-Skill (Join-Path $d 'skills\agent-bridge') }
    if ($optHooks) { Add-Hooks (Join-Path $d 'hooks.json') "$Hook -Name $n"; if ($optTrust) { Trust-Codex-Hooks $d } }
    $ag = Join-Path $d 'AGENTS.md'; Strip-Block $ag; Write-Text $ag ((Read-Text $ag) + "`n" + (Agents-Block $n)) }
function Ab-Install-Kiro($d, $n) {
    $steering = Join-Path $d 'steering'; Ensure-Dir $steering; Ensure-Dir (Join-Path $BR "inbox\$n")
    if ($optSkill) { Copy-Item (Join-Path $Src 'SKILL.md') (Join-Path $steering 'agent-bridge.md') -Force }
    $ag = Join-Path $steering 'AGENTS.md'; Strip-Block $ag; Write-Text $ag ((Read-Text $ag) + "`n" + (Agents-Block $n)) }
# Antigravity (agy): global rules in <HOME>\.gemini\config\AGENTS.md, where HOME is derived from the account dir (...\.gemini\antigravity-cli).
function Agy-Cfg($d) { $x = $d.TrimEnd('\', '/'); if ($x -match '^(.*)[\\/]\.gemini[\\/]antigravity-cli$') { $h = $Matches[1] } elseif (Test-Path (Join-Path $x '.gemini')) { $h = $x } else { $h = $UserHome }; return (Join-Path $h '.gemini\config') }
function Ab-Install-Agy($d, $n) {
    $cfg = Agy-Cfg $d; Ensure-Dir (Join-Path $cfg 'skills\agent-bridge'); Ensure-Dir (Join-Path $BR "inbox\$n"); Write-Text (Join-Path $d 'provider') 'antigravity'
    if ($optSkill) { Copy-Item (Join-Path $Src 'SKILL.md') (Join-Path $cfg 'skills\agent-bridge\SKILL.md') -Force }
    $ag = Join-Path $cfg 'AGENTS.md'; Strip-Block $ag; Write-Text $ag ((Read-Text $ag) + "`n" + (Agents-Block $n)) }
function Ab-Uninstall-Agy($d) {
  $cfg = Agy-Cfg $d; Remove-Item (Join-Path $cfg 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue; Strip-Block (Join-Path $cfg 'AGENTS.md'); Remove-Item (Join-Path $d 'provider') -Force -ErrorAction SilentlyContinue }
# Cursor CLI (cursor-agent, workers only; never install or call a bare `agent`: here `agent` is the bridge command), OpenCode (opencode-N marker folders ~/.opencode-N sharing one install) and GitHub Copilot CLI (copilot, workers only).
function Ab-Install-Cursor($d, $n) {
    Ensure-Dir (Join-Path $d 'skills\agent-bridge'); Ensure-Dir (Join-Path $BR "inbox\$n"); Write-Text (Join-Path $d 'provider') 'cursor'
    if ($optSkill) { Copy-Item (Join-Path $Src 'SKILL.md') (Join-Path $d 'skills\agent-bridge\SKILL.md') -Force } }
function Ab-Uninstall-Cursor($d) { Remove-Item (Join-Path $d 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $d 'provider') -Force -ErrorAction SilentlyContinue }
function Ab-Install-OpenCode($d, $n) {
    Ensure-Dir (Join-Path $d 'skills\agent-bridge'); Ensure-Dir (Join-Path $BR "inbox\$n"); Write-Text (Join-Path $d 'provider') 'opencode'
    if ($optSkill) { Copy-Item (Join-Path $Src 'SKILL.md') (Join-Path $d 'skills\agent-bridge\SKILL.md') -Force }
    $q = Join-Path $d 'AGENTS.md'; Strip-Block $q; Write-Text $q ((Read-Text $q) + "`n" + (Agents-Block $n)) }
function Ab-Uninstall-OpenCode($d) { Remove-Item (Join-Path $d 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue; Strip-Block (Join-Path $d 'AGENTS.md'); Remove-Item (Join-Path $d 'provider') -Force -ErrorAction SilentlyContinue }
function Ab-Install-Copilot($d, $n) {
    Ensure-Dir (Join-Path $d 'skills\agent-bridge'); Ensure-Dir (Join-Path $BR "inbox\$n"); Write-Text (Join-Path $d 'provider') 'copilot'
    if ($optSkill) { Copy-Item (Join-Path $Src 'SKILL.md') (Join-Path $d 'skills\agent-bridge\SKILL.md') -Force }
    $q = Join-Path $d 'copilot-instructions.md'; Strip-Block $q; Write-Text $q ((Read-Text $q) + "`n" + (Agents-Block $n)) }
function Ab-Uninstall-Copilot($d) { Remove-Item (Join-Path $d 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue; Strip-Block (Join-Path $d 'copilot-instructions.md'); Remove-Item (Join-Path $d 'provider') -Force -ErrorAction SilentlyContinue }
# Cursor-Agent-Clash: true when the `agent` found on PATH is Cursor's (not the bridge's)
function Cursor-Agent-Clash { $c = Get-Command agent -ErrorAction SilentlyContinue; if (-not $c) { return $false }; $src = [string]$c.Source
  if ($src -match 'claude-bridge|agent-bridge') { return $false }; return ($src -match 'cursor') }
function Ab-Uninstall-Claude($d) {
  Del-Hooks (Join-Path $d 'settings.json')
  $s = Join-Path $d 'settings.json'
  if (Test-Path $s) { $j = Load-Json $s; if ($j.PSObject.Properties['env']) { $j.env.PSObject.Properties.Remove('BRIDGE_NAME'); $j.env.PSObject.Properties.Remove('BRIDGE_COMMANDERS') }; Save-Json $s $j }
  Remove-Item (Join-Path $d 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $d 'commands\admin.md'), (Join-Path $d 'commands\agent.md'), (Join-Path $d 'commands\dashboard.md') -Force -ErrorAction SilentlyContinue }
function Ab-Uninstall-Codex($d) {
  Del-Hooks (Join-Path $d 'hooks.json'); Strip-Block (Join-Path $d 'AGENTS.md')
  Remove-Item (Join-Path $d 'skills\agent-bridge') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $d 'prompts\admin.md'), (Join-Path $d 'prompts\agent.md'), (Join-Path $d 'prompts\dashboard.md') -Force -ErrorAction SilentlyContinue }
function Ab-Uninstall-Kiro($d) {
  Remove-Item (Join-Path $d 'steering\agent-bridge.md') -Force -ErrorAction SilentlyContinue; Strip-Block (Join-Path $d 'steering\AGENTS.md') }
function Ab-Next-Steps { return @('  2. Open a NEW terminal (PATH changed)', '  3. Codex: hooks are pre-approved (if /hooks still lists one, approve it)', '  4. Try /admin  then  /agent ping <name>', '', '! WSL accounts: run ./install.sh from inside WSL') }
