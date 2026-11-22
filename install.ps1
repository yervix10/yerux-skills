# yerux-skills installer (Windows): finds every Claude Code / Codex account and installs the featured package
# (agent-bridge) plus any of the other skills. Package-specific logic lives in agent-bridge\package.ps1.
# Interactive menu in a console; -Yes accepts everything detected.
# Usage: .\install.ps1 [-Yes] [-Skills a,b|all|none] [-DryRun] [-NoBypass] [-Safe] [-NoPath] [-NoTrust] [-Check] [-ClaudeDir DIR[,DIR]] [-CodexDir DIR[,DIR]] [-Name "DIR=NAME"]
#        .\install.ps1 -List | -Uninstall [-DryRun]
# If scripts are blocked:  powershell -ExecutionPolicy Bypass -File .\install.ps1
param([switch]$DryRun, [switch]$Uninstall, [switch]$List, [switch]$Check, [switch]$Yes, [switch]$NoBypass, [switch]$Safe, [switch]$NoPath, [switch]$NoTrust, [string]$Skills = '', [string[]]$ClaudeDir = @(), [string[]]$CodexDir = @(), [string[]]$KiroDir = @(), [string[]]$AgyDir = @(), [string[]]$CursorDir = @(), [string[]]$QwenDir = @(), [string[]]$Name = @())
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) { throw 'This is the Windows installer. On Linux/macOS/WSL run ./install.sh' }
$utf8 = New-Object System.Text.UTF8Encoding $false
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path; $Src = Join-Path $Root 'agent-bridge'; $RepoRoot = $Root
$UserHome = $env:USERPROFILE
$BR = Join-Path $UserHome '.claude-bridge'; $Bin = Join-Path $BR 'bin'; $Manifest = Join-Path $UserHome '.yerux-skills\installed.txt'
# package: defined after the basic helpers below
function Say($m) { Write-Host $m }
function Ensure-Dir($p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Read-Text($p) { if (Test-Path $p) { [IO.File]::ReadAllText($p, $utf8) } else { '' } }
function Write-Text($p, $t) { [IO.File]::WriteAllText($p, $t, $utf8) }
. (Join-Path $Src 'package.ps1')


# ---------- UI (colors, banner, progress) ----------
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
$UiUtf = ($PSVersionTable.PSVersion.Major -ge 6) -or [bool]$env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode')
$UiColor = -not $env:NO_COLOR
if ($UiUtf) { $S = @{ ok = [string][char]0x2714; fail = [string][char]0x2716; arrow = [string][char]0x276F; on = [string][char]0x25C9; off = [string][char]0x25CB; dot = [string][char]0x2022; tl = [string][char]0x256D; tr = [string][char]0x256E; bl = [string][char]0x2570; br = [string][char]0x256F; h = [string][char]0x2500; v = [string][char]0x2502; dry = [string][char]0x25CC; full = [string][char]0x2588; empty = [string][char]0x2591 } }
else { $S = @{ ok = '+'; fail = 'x'; arrow = '>'; on = '(*)'; off = '( )'; dot = '*'; tl = '+'; tr = '+'; bl = '+'; br = '+'; h = '-'; v = '|'; dry = '~'; full = '#'; empty = '.' } }
function Ui-W($text, $color = 'Gray', [switch]$NoNewline) { if ($UiColor) { Write-Host $text -ForegroundColor $color -NoNewline:$NoNewline } else { Write-Host $text -NoNewline:$NoNewline } }
function Ui-Box($title, $lines) {
  $w = 54; Say ''; Ui-W ("  " + $S.tl + $S.h + " $title " + ($S.h * ($w - $title.Length - 3)) + $S.tr) 'Green'
  foreach ($l in $lines) { Ui-W ("  " + $S.v + "  ") 'Green' -NoNewline; Say $l }
  Ui-W ("  " + $S.bl + ($S.h * $w) + $S.br) 'Green'; Say '' }
$script:Fast = $false
function Ui-Sleep { if (-not $script:Fast) { Start-Sleep -Milliseconds 50 } }
function Ui-Banner {
  $w = 50; $t1 = '  yerux - skills  installer   v1.4.0'; $t2 = '  * featured: agent-bridge'
  Say ''; Ui-W ("  " + $S.tl + ($S.h * $w) + $S.tr) 'Cyan'; Ui-Sleep
  Ui-W ("  " + $S.v + $t1.PadRight($w) + $S.v) 'Cyan'; Ui-Sleep
  Ui-W ("  " + $S.v + $t2.PadRight($w) + $S.v) 'DarkCyan'; Ui-Sleep
  Ui-W ("  " + $S.bl + ($S.h * $w) + $S.br) 'Blue'; Say '' }
function Ui-H($t) { Say ''; Ui-W "  $t" 'Magenta' }
function Ui-Info($t) { Ui-W "  $($S.dot) " 'Cyan' -NoNewline; Say $t }
function Ui-Ok($t) { Ui-W "  $($S.ok) " 'Green' -NoNewline; Say $t }
function Ui-Fail($t) { Ui-W "  $($S.fail) " 'Red' -NoNewline; Say $t }
function Ui-Row($n, $on, $kind, $name, $dir) {
  $mark = if ($on) { $S.on } else { $S.off }; $col = if ($on) { 'Green' } else { 'DarkGray' }
  Write-Host ("   {0,2}  " -f $n) -NoNewline; Ui-W "$mark  " $col -NoNewline; Ui-W ("{0,-6} " -f $kind) 'Blue' -NoNewline
  Write-Host ("{0,-10} " -f $name) -NoNewline; Ui-W ($dir -replace [regex]::Escape($UserHome), '~') 'DarkGray' }
$script:Steps = 0; $script:StepNo = 0; $script:Fails = 0
function Ui-Bar { $filled = if ($script:Steps -gt 0) { [int](20 * $script:StepNo / $script:Steps) } else { 20 }
  return ("[" + ($S.full * $filled) + ($S.empty * (20 - $filled)) + "] $($script:StepNo)/$($script:Steps)") }
function Step($label, [scriptblock]$sb) {
  $script:StepNo++
  if ($DryRun) { Ui-W "  $($S.dry) $label" 'Yellow'; return }
  try { & $sb | Out-Null; Ui-Ok "$label"; Ui-W ("    " + (Ui-Bar)) 'DarkGray' }
  catch { $script:Fails++; Ui-Fail "$label"; Ui-W "      $($_.Exception.Message)" 'DarkGray' } }

# ---------- discovery ----------
function Norm($p) {
  if (-not $p) { return $null }
  $p = $p.Trim().Trim('"').Trim("'")
  $p = $p -replace '^~', $UserHome
  $p = $p -replace '(?i)\$env:USERPROFILE', $UserHome -replace '(?i)\$\{?HOME\}?', $UserHome -replace '(?i)%USERPROFILE%', $UserHome
  $p = $p -replace '/', '\'
  if ($p -match '\$') { return $null }
  return $p.TrimEnd('\') }
$Claude = New-Object System.Collections.Generic.List[string]
$Codex = New-Object System.Collections.Generic.List[string]
$Kiro = New-Object System.Collections.Generic.List[string]
$Agy = New-Object System.Collections.Generic.List[string]
$Cursor = New-Object System.Collections.Generic.List[string]
$Qwen = New-Object System.Collections.Generic.List[string]
function Add-Dir($kind, $p) {
  $d = Norm $p; if (-not $d -or -not (Test-Path $d -PathType Container)) { return }
  if ((Split-Path $d -Leaf) -eq '.claude-bridge') { return }
  $list = $Codex; if ($kind -eq 'claude') { $list = $Claude } elseif ($kind -eq 'kiro') { $list = $Kiro } elseif ($kind -eq 'antigravity') { $list = $Agy } elseif ($kind -eq 'cursor') { $list = $Cursor } elseif ($kind -eq 'qwen') { $list = $Qwen }
  if (-not ($list | Where-Object { $_ -ieq $d })) { $list.Add($d) } }
foreach ($d in $ClaudeDir) { Add-Dir 'claude' $d }
foreach ($d in $CodexDir) { Add-Dir 'codex' $d }
foreach ($d in $KiroDir) { Add-Dir 'kiro' $d }
foreach ($d in $AgyDir) { Add-Dir 'antigravity' $d }
foreach ($d in $CursorDir) { Add-Dir 'cursor' $d }
foreach ($d in $QwenDir) { Add-Dir 'qwen' $d }
foreach ($d in (Get-ChildItem $UserHome -Directory -Force -Filter '.claude*' -ErrorAction SilentlyContinue)) {
  foreach ($m in 'settings.json', '.credentials.json', 'projects', 'commands', 'skills') { if (Test-Path (Join-Path $d.FullName $m)) { Add-Dir 'claude' $d.FullName; break } } }
foreach ($d in (Get-ChildItem $UserHome -Directory -Force -Filter '.codex*' -ErrorAction SilentlyContinue)) {
  foreach ($m in 'auth.json', 'config.toml', 'hooks.json', 'sessions') { if (Test-Path (Join-Path $d.FullName $m)) { Add-Dir 'codex' $d.FullName; break } } }
if ((Get-Command kiro-cli -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome '.kiro\sessions'))) { Add-Dir 'kiro' (Join-Path $UserHome '.kiro') }
# Cursor CLI (binary cursor-agent, never the bare `agent`) and Qwen Code (qwen): one account per HOME (.cursor, .qwen)
if ((Get-Command cursor-agent -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome '.cursor\chats'))) { Add-Dir 'cursor' (Join-Path $UserHome '.cursor') }
if ((Get-Command qwen -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome '.qwen'))) { Add-Dir 'qwen' (Join-Path $UserHome '.qwen') }
# Google Antigravity (agy): one account per HOME (.gemini\antigravity-cli); its sign-in lives in the system, not in that folder
if ((Get-Command agy -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $UserHome '.gemini\antigravity-cli'))) { $ad = Join-Path $UserHome '.gemini\antigravity-cli'; if (-not $DryRun) { Ensure-Dir $ad }; Add-Dir 'antigravity' $ad }
foreach ($scope in 'Process', 'User', 'Machine') {
  $v = [Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR', $scope); if ($v) { Add-Dir 'claude' $v }
  $v = [Environment]::GetEnvironmentVariable('CODEX_HOME', $scope); if ($v) { Add-Dir 'codex' $v } }
# PowerShell profiles / Git Bash startup files that mention CLAUDE_CONFIG_DIR or CODEX_HOME
$rcs = @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost, (Join-Path $UserHome '.bashrc'), (Join-Path $UserHome '.bash_profile'), (Join-Path $UserHome '.bash_aliases')) | Where-Object { $_ }
foreach ($rc in $rcs) { if (-not (Test-Path $rc)) { continue }
  foreach ($line in (Get-Content $rc -ErrorAction SilentlyContinue)) { if ($line -match '^\s*#') { continue }
    foreach ($m in [regex]::Matches($line, 'CLAUDE_CONFIG_DIR[=\s]+[''"]?([^''";\s)]+)')) { Add-Dir 'claude' $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($line, 'CODEX_HOME[=\s]+[''"]?([^''";\s)]+)')) { Add-Dir 'codex' $m.Groups[1].Value } } }

# ---------- names (names.conf: DIR=NAME) ----------
$conf = Join-Path $BR 'names.conf'; $Map = [ordered]@{}
if (Test-Path $conf) { foreach ($l in (Get-Content $conf -Encoding UTF8)) { $p = $l.Split('=', 2); if ($p.Count -eq 2 -and $p[0]) { $Map[$p[0]] = $p[1].Trim() } } }
$Over = @{}; foreach ($n in $Name) { $p = $n.Split('=', 2); if ($p.Count -eq 2) { $Over[(Norm $p[0])] = $p[1] } }
function Next-Name($prefix) { $max = 0; foreach ($v in $Map.Values) { if ($v -match "^$prefix-(\d+)$") { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }; return "$prefix-$($max + 1)" }
function Existing-Name($d) {
  $s = Join-Path $d 'settings.json'
  if (Test-Path $s) { try { $j = (Read-Text $s) | ConvertFrom-Json; if ($j.env.BRIDGE_NAME) { return [string]$j.env.BRIDGE_NAME } } catch {} }
  $h = Join-Path $d 'hooks.json'
  if (Test-Path $h) { if ((Read-Text $h) -match '-Name\s+([A-Za-z0-9_-]+)') { return $Matches[1] } }
  return $null }
function Assign($d, $prefix) {
  $n = $Over[$d]; if (-not $n) { $n = $Map[$d] }; if (-not $n) { $n = Existing-Name $d }; if (-not $n) { $n = Next-Name $prefix }
  if ($n -notmatch '^[A-Za-z0-9_-]+$') { throw "invalid name for ${d}: '$n'" }
  $Map[$d] = $n }
foreach ($d in $Claude) { Assign $d 'claude' }
foreach ($d in $Codex) { Assign $d 'codex' }
foreach ($d in $Kiro) { Assign $d 'kiro' }
foreach ($d in $Agy) { Assign $d 'agy' }
foreach ($d in $Cursor) { Assign $d 'cursor' }
foreach ($d in $Qwen) { Assign $d 'qwen' }

if ($List) {
  Say 'system: windows'
  foreach ($d in $Claude) { Say "claude  $($Map[$d])  $d" }
  foreach ($d in $Codex) { Say "codex   $($Map[$d])  $d" }
  foreach ($d in $Kiro) { Say "kiro    $($Map[$d])  $d" }
  foreach ($d in $Agy) { Say "agy     $($Map[$d])  $d" }
  foreach ($d in $Cursor) { Say "cursor  $($Map[$d])  $d" }
  foreach ($d in $Qwen) { Say "qwen    $($Map[$d])  $d" }
  return }

# ---------- JSON / text helpers ----------
function Load-Json($p) { if (Test-Path $p) { $t = Read-Text $p; if ($t.Trim()) { return ($t | ConvertFrom-Json) } }; return (New-Object psobject) }
function Save-Json($p, $o) { Write-Text $p (($o | ConvertTo-Json -Depth 30) + "`n") }
function Set-Prop($o, $name, $val) { if ($o.PSObject.Properties[$name]) { $o.$name = $val } else { $o | Add-Member -NotePropertyName $name -NotePropertyValue $val } }
function Act($desc, [scriptblock]$sb) { if ($DryRun) { Say "  [dry-run] $desc" } else { & $sb } }

# ---------- uninstall ----------
function Remove-Skills($d) {
  if (-not (Test-Path $Manifest)) { return }
  $keep = @(); foreach ($l in (Get-Content $Manifest -Encoding UTF8)) { $p = $l.Split("`t"); if ($p.Count -eq 2 -and $p[0] -eq $d) { Remove-Item (Join-Path $d "skills\$($p[1])") -Recurse -Force -ErrorAction SilentlyContinue; Say "  removed skill $($p[1])" } elseif ($l) { $keep += $l } }
  Write-Text $Manifest ((($keep -join "`n")) + $(if ($keep.Count) { "`n" } else { '' })) }
if ($Uninstall) {
  foreach ($d in $Claude) { Say "uninstalling Claude: $d"; if ($DryRun) { continue }; Ab-Uninstall-Claude $d; Remove-Skills $d }
  foreach ($d in $Codex) { Say "uninstalling Codex: $d"; if ($DryRun) { continue }; Ab-Uninstall-Codex $d; Remove-Skills $d }
  foreach ($d in $Kiro) { Say "uninstalling Kiro: $d"; if ($DryRun) { continue }; Ab-Uninstall-Kiro $d; Remove-Skills $d }
  foreach ($d in $Agy) { Say "uninstalling Antigravity: $d"; if ($DryRun) { continue }; Ab-Uninstall-Agy $d; Remove-Skills (Agy-Cfg $d) }
  foreach ($d in $Cursor) { Say "uninstalling Cursor: $d"; if ($DryRun) { continue }; Ab-Uninstall-Cursor $d; Remove-Skills $d }
  foreach ($d in $Qwen) { Say "uninstalling Qwen: $d"; if ($DryRun) { continue }; Ab-Uninstall-Qwen $d; Remove-Skills $d }
  Say "done. agent-bridge and the extra skills this installer added were removed. The mailbox $BR (messages, names.conf) is kept."; return }


# ---------- check: scripts, hooks, names, skills and Codex hook approval of every account ----------
if ($Check) {
  $script:bad = 0
  function Chk-Ok($t) { Ui-Ok $t }; function Chk-Bad($t) { Ui-Fail $t; $script:bad++ }
  function Has-BridgeHook($file) { if (-not (Test-Path $file)) { return $false }; $j = Load-Json $file
    if (-not $j.PSObject.Properties['hooks']) { return $false }
    foreach ($p in @($j.hooks.PSObject.Properties)) { foreach ($e in @($p.Value)) { if (Is-Bridge $e) { return $true } } }
    return $false }
  Ui-H 'Check'
  foreach ($f in 'bridge.ps1', 'agent.cmd', 'admin.cmd') { if (Test-Path (Join-Path $Bin $f)) { Chk-Ok "script $f" } else { Chk-Bad "script $f missing in $Bin" } }
  $skillText = For-Windows (Read-Text (Join-Path $Src 'SKILL.md'))
  $py = Get-Command python3, python, py -ErrorAction SilentlyContinue | Select-Object -First 1
  foreach ($d in $Claude) { $n = $Map[$d]; $sj = Join-Path $d 'settings.json'
    if (Has-BridgeHook $sj) { Chk-Ok "Claude  $n  hook" } else { Chk-Bad "Claude  $n  hook missing" }
    $jj = Load-Json $sj; if ($jj.PSObject.Properties['env'] -and $jj.env.BRIDGE_NAME -eq $n) { Chk-Ok "Claude  $n  name" } else { Chk-Bad "Claude  $n  BRIDGE_NAME not set" }
    if ((Read-Text (Join-Path $d 'skills\agent-bridge\SKILL.md')) -eq $skillText) { Chk-Ok "Claude  $n  skill up to date" } else { Chk-Bad "Claude  $n  skill missing or outdated" } }
  foreach ($d in $Codex) { $n = $Map[$d]
    if (Has-BridgeHook (Join-Path $d 'hooks.json')) { Chk-Ok "Codex   $n  hook" } else { Chk-Bad "Codex   $n  hook missing" }
    if ($py -and (Get-Command codex -ErrorAction SilentlyContinue)) {
      $a = @((Join-Path $Src 'scripts\codex-trust-hooks'), $d, '--check'); if ($py.Name -like 'py*') { $a = @('-3') + $a }
      $out = & $py.Source @a 2>&1; if ($LASTEXITCODE -eq 0) { Chk-Ok "Codex   $n  hooks approved" } else { Chk-Bad "Codex   $n  $(@($out | Where-Object { $_ -match 'untrusted' }).Count) hook(s) not approved: reinstall or run /hooks" } }
    if ((Read-Text (Join-Path $d 'skills\agent-bridge\SKILL.md')) -eq $skillText) { Chk-Ok "Codex   $n  skill up to date" } else { Chk-Bad "Codex   $n  skill missing or outdated" } }
  foreach ($d in $Kiro) { $n = $Map[$d]; $ag = Join-Path $d 'steering\AGENTS.md'
    if ((Read-Text $ag) -match 'BRIDGE-BEGIN') { Chk-Ok "Kiro    $n  steering" } else { Chk-Bad "Kiro    $n  steering missing" }
    if ((Read-Text (Join-Path $d 'steering\agent-bridge.md')) -eq (Read-Text (Join-Path $Src 'SKILL.md'))) { Chk-Ok "Kiro    $n  skill up to date" } else { Chk-Bad "Kiro    $n  skill missing or outdated" } }
  foreach ($d in $Agy) { $n = $Map[$d]; $cfg = Agy-Cfg $d
    if ((Read-Text (Join-Path $cfg 'AGENTS.md')) -match 'BRIDGE-BEGIN') { Chk-Ok "Agy     $n  global rules" } else { Chk-Bad "Agy     $n  global rules missing" }
    if ((Read-Text (Join-Path $cfg 'skills\agent-bridge\SKILL.md')) -eq (Read-Text (Join-Path $Src 'SKILL.md'))) { Chk-Ok "Agy     $n  skill up to date" } else { Chk-Bad "Agy     $n  skill missing or outdated" } }
  foreach ($d in $Cursor) { $n = $Map[$d]
    if ((Read-Text (Join-Path $d 'skills\agent-bridge\SKILL.md')) -eq (Read-Text (Join-Path $Src 'SKILL.md'))) { Chk-Ok "Cursor  $n  skill up to date" } else { Chk-Bad "Cursor  $n  skill missing or outdated" }
    if (Cursor-Agent-Clash) { Chk-Bad "Cursor  $n  'agent' on PATH is Cursor's, not the bridge's: workers call cursor-agent; reinstall the bridge command" } }
  foreach ($d in $Qwen) { $n = $Map[$d]
    if ((Read-Text (Join-Path $d 'QWEN.md')) -match 'BRIDGE-BEGIN') { Chk-Ok "Qwen    $n  QWEN.md" } else { Chk-Bad "Qwen    $n  QWEN.md block missing" }
    if ((Read-Text (Join-Path $d 'skills\agent-bridge\SKILL.md')) -eq (Read-Text (Join-Path $Src 'SKILL.md'))) { Chk-Ok "Qwen    $n  skill up to date" } else { Chk-Bad "Qwen    $n  skill missing or outdated" } }
  Say ''; if ($script:bad -eq 0) { Ui-Info 'everything looks fine'; return } else { Ui-W "  ! $($script:bad) problem(s): run .\install.ps1 to repair" 'Yellow'; exit 1 } }

if (-not $List -and -not $Uninstall) { Ui-Banner }
# ---------- skills of this repo (every folder with a SKILL.md besides agent-bridge) ----------
$SkList = @()
foreach ($d in (Get-ChildItem $RepoRoot -Directory | Sort-Object Name)) {
  if ($d.Name -eq 'agent-bridge' -or $d.Name.StartsWith('.')) { continue }
  $sk = Join-Path $d.FullName 'SKILL.md'; if (-not (Test-Path $sk)) { continue }
  $desc = ''; $lines = Get-Content $sk -Encoding UTF8 -TotalCount 40
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^description:\s*(.*)$') { $desc = $Matches[1]; if ($desc -match '^[>|]?$' -and ($i + 1) -lt $lines.Count) { $desc = $lines[$i + 1].Trim() }; break } }
  if ($desc.Length -gt 64) { $desc = $desc.Substring(0, 64) }
  $SkList += [pscustomobject]@{ Name = $d.Name; Desc = $desc; Path = $d.FullName } }
$PkgAb = $true; $SelSkills = @()
if ($Skills -eq 'all') { $SelSkills = @($SkList | ForEach-Object { $_.Name }) } elseif ($Skills -and $Skills -ne 'none') { $SelSkills = @($Skills -split '[,\s]+' | Where-Object { $_ }) }

# ---------- interactive menu (arrows + space) ----------
$optSkill = $true; $optHooks = $true; $optBypass = -not $NoBypass; $optSafe = [bool]$Safe; $optPath = -not $NoPath; $optTrust = -not $NoTrust
function YN($q, $def) { $d = if ($def) { 'Y/n' } else { 'y/N' }; $r = Read-Host "  $($S.arrow) $q [$d]"; if ($r -match '^[Yy]') { return $true }; if ($r -match '^[Nn]') { return $false }; return $def }
# Items: objects with Label, Sub, On, Feat. $onKey is an optional scriptblock called with the pressed char (may modify $items; returns extra lines it printed).
$script:MsBack = $false
function Ms-Run($items, [scriptblock]$onKey = $null, [switch]$CanBack, [switch]$AllRow) {
  $script:MsBack = $false; $cur = 0; $top = 0; $drawn = 0; $first = $true
  while ($true) {
    $vis = [Math]::Max(5, [Console]::WindowHeight - 15); if ($vis -gt $items.Count) { $vis = $items.Count }
    if ($cur -lt $top) { $top = $cur }; if ($cur -ge $top + $vis) { $top = $cur - $vis + 1 }; if ($top -lt 0) { $top = 0 }
    if (-not $first) { [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $drawn)) }
    $first = $false; $cols = [Console]::WindowWidth; $drawn = 0
    $lw = [Math]::Min(30, ($items | ForEach-Object { $_.Label.Length + $(if ($_.Feat) { 2 } else { 0 }) } | Measure-Object -Maximum).Maximum)
    for ($i = $top; $i -lt [Math]::Min($items.Count, $top + $vis); $i++) {
      $it = $items[$i]; $ptr = if ($i -eq $cur) { $S.arrow } else { ' ' }; $mark = if ($it.On) { $S.on } else { $S.off }
      $lab = if ($it.Feat) { "* $($it.Label)" } else { $it.Label }
      if ($lab.Length -gt $lw) { $lab = $lab.Substring(0, $lw - 1) + '~' }; $lab = $lab.PadRight($lw)
      $max = $cols - $lw - 12; $sub = if ($max -lt 8) { '' } elseif ($it.Sub.Length -gt $max) { $it.Sub.Substring(0, $max) } else { $it.Sub }
      Write-Host "  " -NoNewline; Ui-W $ptr 'Cyan' -NoNewline; Write-Host " " -NoNewline
      Ui-W $mark $(if ($it.On) { 'Green' } else { 'DarkGray' }) -NoNewline; Write-Host "  " -NoNewline
      Ui-W $lab $(if ($it.Feat) { 'Magenta' } else { 'White' }) -NoNewline; Ui-W ("  $sub").PadRight($cols - 8 - $lab.Length) 'DarkGray'
      $drawn++ }
    if ($AllRow -or $items.Count -gt $vis) {
      $sel = @($items | Where-Object { $_.On }).Count; if ($AllRow -and $items[0].On) { $sel-- }
      Ui-W (' '.PadRight($cols - 2)) 'Gray'; Ui-W ("  $sel selected   $($cur + 1)/$($items.Count)").PadRight($cols - 2) 'DarkGray'; $drawn += 2 }
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'Enter' { return }
      'UpArrow' { if ($cur -gt 0) { $cur-- } }
      'DownArrow' { if ($cur -lt $items.Count - 1) { $cur++ } }
      'Spacebar' { if ($items.Count -gt 0) {
          $items[$cur].On = -not $items[$cur].On
          if ($AllRow) {
            if ($cur -eq 0) { for ($i = 1; $i -lt $items.Count; $i++) { $items[$i].On = $items[0].On } }
            else { $items[0].On = -not ($items | Select-Object -Skip 1 | Where-Object { -not $_.On }) } } } }
      default {
        $ch = [string]$k.KeyChar
        if ($ch -eq 'k') { if ($cur -gt 0) { $cur-- } } elseif ($ch -eq 'j') { if ($cur -lt $items.Count - 1) { $cur++ } }
        elseif ($ch -eq 'a' -and -not $onKey) { foreach ($it in $items) { $it.On = $true } }
        elseif ($ch -eq 'n' -and -not $onKey) { foreach ($it in $items) { $it.On = $false } }
        elseif (($ch -eq 'b' -or $ch -eq 'B') -and $CanBack) { $script:MsBack = $true; return }
        elseif ($onKey) { $extra = & $onKey $ch $items $cur; if ($extra) { $drawn += [int]$extra } } } } } }
function Ui-Hint($t) { Ui-W "  $t" 'DarkGray' }

function Ui-Stepper($cur) {
  $names = 'Packages', 'Accounts', 'agent-bridge', 'Confirm'; Write-Host '  ' -NoNewline
  for ($i = 1; $i -le 4; $i++) {
    if ($i -lt $cur) { Ui-W "$($S.ok) $($names[$i - 1])" 'Green' -NoNewline } elseif ($i -eq $cur) { Ui-W "$($S.on) $($names[$i - 1])" 'Magenta' -NoNewline } else { Ui-W "$($S.off) $($names[$i - 1])" 'DarkGray' -NoNewline }
    if ($i -lt 4) { Ui-W " $($S.h)$($S.h) " 'DarkGray' -NoNewline } }
  Say '' }
function Ui-Keys($keys) { Write-Host '  ' -NoNewline; foreach ($k in $keys) { $w, $r = $k -split ' ', 2; Ui-W $w 'Cyan' -NoNewline; Ui-W " $r   " 'DarkGray' -NoNewline }; Say '' }
function Menu-Screen($n, $keys) { $script:Fast = $true; Clear-Host; Ui-Banner; Ui-Stepper $n; Say ''; Ui-Keys $keys; Say '' }
function Info-Wait { while ($true) { $k = [Console]::ReadKey($true); if ($k.Key -eq 'Enter') { return $false }; if ($k.KeyChar -eq 'b' -or $k.KeyChar -eq 'B') { return $true } } }
if (-not $Yes -and -not $DryRun -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
  # accounts as detected (information only); packages are the only selectable step
  $acc = @(); foreach ($d in $Claude) { $acc += [pscustomobject]@{ Kind = 'claude'; Dir = $d } }; foreach ($d in $Codex) { $acc += [pscustomobject]@{ Kind = 'codex'; Dir = $d } }; foreach ($d in $Kiro) { $acc += [pscustomobject]@{ Kind = 'kiro'; Dir = $d } }; foreach ($d in $Agy) { $acc += [pscustomobject]@{ Kind = 'antigravity'; Dir = $d } }; foreach ($d in $Cursor) { $acc += [pscustomobject]@{ Kind = 'cursor'; Dir = $d } }; foreach ($d in $Qwen) { $acc += [pscustomobject]@{ Kind = 'qwen'; Dir = $d } }
  $pk = New-Object System.Collections.ArrayList
  [void]$pk.Add([pscustomobject]@{ Label = 'all'; Sub = 'select every package'; On = $false; Feat = $false })
  [void]$pk.Add([pscustomobject]@{ Label = 'agent-bridge'; Sub = 'Claude Code + Codex + Kiro + Antigravity + Cursor + Qwen sessions that talk to each other'; On = $true; Feat = $true })
  foreach ($x in $SkList) { [void]$pk.Add([pscustomobject]@{ Label = $x.Name; Sub = $x.Desc; On = $false; Feat = $false }) }
  $step = 1
  while ($true) {
    if ($step -eq 1) {
      $pk[0].On = -not ($pk | Select-Object -Skip 1 | Where-Object { -not $_.On })
      Menu-Screen 1 @('up/down move', 'space select', 'a all', 'n none', 'enter continue')
      Ms-Run $pk -AllRow
      $PkgAb = $pk[1].On; $SelSkills = @(); for ($i = 2; $i -lt $pk.Count; $i++) { if ($pk[$i].On) { $SelSkills += $pk[$i].Label } }
      $step = 2 }
    elseif ($step -eq 2) {
      Menu-Screen 2 @('b back', 'enter continue'); Ui-W '  Detected accounts; all of them will be configured' 'DarkGray'; Say ''
      foreach ($a in $acc) { Write-Host '    ' -NoNewline; Ui-W "$($S.ok)  " 'Green' -NoNewline; Write-Host ("{0,-9} " -f $Map[$a.Dir]) -NoNewline; Ui-W ("{0,-7} " -f $a.Kind) 'Blue' -NoNewline; Ui-W ($a.Dir -replace [regex]::Escape($UserHome), '~') 'Cyan' }
      Say ''; if (Info-Wait) { $step = 1 } elseif ($PkgAb) { $step = 3 } else { $step = 4 } }
    elseif ($step -eq 3) {
      Menu-Screen 3 @('b back', 'enter continue'); Ui-W '  What agent-bridge will set up' 'DarkGray'; Say ''
      foreach ($l in @(@('Skill + /admin /agent commands', 'how sessions learn the commands'), @('Message hook', 'delivers messages between sessions'), @('Auto-approve Codex hooks', 'no /hooks review needed in Codex'), @('Headless workers in bypass mode', 'no permission prompts for orders'), @('Put agent/admin on PATH', 'user PATH'))) {
        Write-Host '    ' -NoNewline; Ui-W "$($S.ok)  " 'Green' -NoNewline; Write-Host ("{0,-34} " -f $l[0]) -NoNewline; Ui-W $l[1] 'DarkGray' }
      Say ''; if (Info-Wait) { $step = 2 } else { $step = 4 } }
    else {
      Menu-Screen 4 @('enter install', 'n back')
      $pkn = @(); if ($PkgAb) { $pkn += 'agent-bridge' }; $pkn += $SelSkills; $pkt = if ($pkn.Count) { $pkn -join ', ' } else { 'none' }
      if ($pkt.Length -gt 58) { $pkt = $pkt.Substring(0, 55) + "...  ($($pkn.Count) packages)" }
      $sum = @("Accounts     $($Claude.Count + $Codex.Count + $Kiro.Count + $Agy.Count + $Cursor.Count + $Qwen.Count)  ($($Claude.Count) claude / $($Codex.Count) codex / $($Kiro.Count) kiro / $($Agy.Count) agy / $($Cursor.Count) cursor / $($Qwen.Count) qwen)", "Packages     $pkt")
      if ($PkgAb) { $sum += "agent-bridge skill+commands, hook" + $(if ($optTrust) { ', auto-approve Codex hooks' }) + $(if ($optSafe) { ', safe-mode workers' } elseif ($optBypass) { ', bypass workers' }) + $(if ($optPath) { ', PATH' }) }
      Ui-Box 'Summary' $sum
      if (YN 'Install now?' $true) { break }
      if ($PkgAb) { $step = 3 } else { $step = 2 } } }
  $script:Fast = $false; Clear-Host; Ui-Banner }

# ---------- install ----------
Ui-H 'Installing'
$script:Steps = $(if ($PkgAb) { 1 } else { 0 }) + $Claude.Count + $Codex.Count + $Kiro.Count + $Agy.Count + $Cursor.Count + $Qwen.Count
function Install-Skills($d) {
  foreach ($n in $SelSkills) {
    $from = Join-Path $RepoRoot $n; if (-not (Test-Path (Join-Path $from 'SKILL.md'))) { continue }
    $to = Join-Path $d "skills\$n"; Ensure-Dir (Join-Path $d 'skills'); if (Test-Path $to) { Remove-Item $to -Recurse -Force }
    Copy-Item $from $to -Recurse -Force; Remove-Item (Join-Path $to '.git') -Recurse -Force -ErrorAction SilentlyContinue
    Ensure-Dir (Split-Path $Manifest -Parent); $entry = "$d`t$n"
    if (-not ((Test-Path $Manifest) -and ((Get-Content $Manifest -Encoding UTF8) -contains $entry))) { Add-Content -Path $Manifest -Value $entry -Encoding UTF8 } } }
if ($PkgAb -and -not $DryRun) { Step "Scripts  $($Bin -replace [regex]::Escape($UserHome), '~')" { Ab-Install-Global } }
foreach ($d in $Claude) { $n = $Map[$d]
  Step ("Claude  {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Claude $d $n }
    Install-Skills $d } }
foreach ($d in $Codex) { $n = $Map[$d]
  Step ("Codex   {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Codex $d $n }
    Install-Skills $d } }
foreach ($d in $Kiro) { $n = $Map[$d]
  Step ("Kiro    {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Kiro $d $n }; Install-Skills $d } }
foreach ($d in $Agy) { $n = $Map[$d]
  Step ("Agy     {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Agy $d $n }; Install-Skills (Agy-Cfg $d) } }
foreach ($d in $Cursor) { $n = $Map[$d]
  Step ("Cursor  {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Cursor $d $n }; Install-Skills $d } }
foreach ($d in $Qwen) { $n = $Map[$d]
  Step ("Qwen    {0,-9} {1}" -f $n, ($d -replace [regex]::Escape($UserHome), '~')) {
    if ($PkgAb) { Ab-Install-Qwen $d $n }; Install-Skills $d } }
# Cursor's official installer puts its own `agent` on PATH and overwrites the bridge command: workers always use cursor-agent
if ($Cursor.Count -gt 0) { if (Cursor-Agent-Clash) { Say "! the 'agent' on your PATH is Cursor's, not the bridge's. The bridge only calls cursor-agent; reinstall the bridge command (install.ps1 without -NoPath)." }; Say 'Cursor: sign in with: cursor-agent login' }
if ($Qwen.Count -gt 0) { Say 'Qwen Code: sign in once (qwen, then /auth) or set an API key' }
if ($Claude.Count + $Codex.Count + $Kiro.Count + $Agy.Count + $Cursor.Count + $Qwen.Count -eq 0) { Say 'No accounts found. Use -ClaudeDir DIR / -CodexDir DIR / -KiroDir DIR / -AgyDir DIR / -CursorDir DIR / -QwenDir DIR.' }
if ($DryRun) { Say ''; Say 'dry-run finished: nothing was written.'; return }
$msg = if ($script:Fails -gt 0) { "$($S.fail) $($script:Fails) step(s) failed" } else { "$($S.ok) $($Claude.Count + $Codex.Count + $Kiro.Count + $Agy.Count + $Cursor.Count + $Qwen.Count) account(s) configured" }
$sum = @($msg); if ($SelSkills.Count -gt 0) { $sum += "$($S.ok) skills: $($SelSkills -join ' ')" }
$sum += @('', 'Next steps', '  1. Restart open Claude/Codex/Kiro/Antigravity/Cursor/Qwen sessions')
if ($PkgAb) { $sum += Ab-Next-Steps }
Ui-Box 'Done' $sum
