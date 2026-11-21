# yerux-skills installer (Windows): finds every Claude Code / Codex account and installs the featured package
# (agent-bridge) plus any of the other skills. Package-specific logic lives in agent-bridge\package.ps1.
# Interactive menu in a console; -Yes accepts everything detected.
# Usage: .\install.ps1 [-Yes] [-Skills a,b|all|none] [-DryRun] [-NoBypass] [-NoPath] [-ClaudeDir DIR[,DIR]] [-CodexDir DIR[,DIR]] [-Name "DIR=NAME"]
#        .\install.ps1 -List | -Uninstall [-DryRun]
# If scripts are blocked:  powershell -ExecutionPolicy Bypass -File .\install.ps1
param([switch]$DryRun, [switch]$Uninstall, [switch]$List, [switch]$Yes, [switch]$NoBypass, [switch]$NoPath, [string]$Skills = '', [string[]]$ClaudeDir = @(), [string[]]$CodexDir = @(), [string[]]$Name = @())
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
if ($UiUtf) { $S = @{ ok = [string][char]0x2714; fail = [string][char]0x2716; arrow = [string][char]0x276F; on = [string][char]0x25C9; off = [string][char]0x25CB; dot = [string][char]0x2022; tl = [string][char]0x256D; tr = [string][char]0x256E; bl = [string][char]0x2570; br = [string][char]0x256F; h = [string][char]0x2500; v = [string][char]0x2502; full = [string][char]0x2588; empty = [string][char]0x2591 } }
else { $S = @{ ok = '+'; fail = 'x'; arrow = '>'; on = '(*)'; off = '( )'; dot = '*'; tl = '+'; tr = '+'; bl = '+'; br = '+'; h = '-'; v = '|'; full = '#'; empty = '.' } }
function Ui-W($text, $color = 'Gray', [switch]$NoNewline) { if ($UiColor) { Write-Host $text -ForegroundColor $color -NoNewline:$NoNewline } else { Write-Host $text -NoNewline:$NoNewline } }
function Ui-Banner {
  $w = 50; $t1 = '  yerux - skills  installer   v1.0.0'; $t2 = '  * featured: agent-bridge'
  Say ''; Ui-W ("  " + $S.tl + ($S.h * $w) + $S.tr) 'Cyan'; Start-Sleep -Milliseconds 50
  Ui-W ("  " + $S.v + $t1.PadRight($w) + $S.v) 'Cyan'; Start-Sleep -Milliseconds 50
  Ui-W ("  " + $S.v + $t2.PadRight($w) + $S.v) 'DarkCyan'; Start-Sleep -Milliseconds 50
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
  if ($DryRun) { Say "  [dry-run] $label"; & $sb; return }
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
function Add-Dir($kind, $p) {
  $d = Norm $p; if (-not $d -or -not (Test-Path $d -PathType Container)) { return }
  if ((Split-Path $d -Leaf) -eq '.claude-bridge') { return }
  $list = $Codex; if ($kind -eq 'claude') { $list = $Claude }
  if (-not ($list | Where-Object { $_ -ieq $d })) { $list.Add($d) } }
foreach ($d in $ClaudeDir) { Add-Dir 'claude' $d }
foreach ($d in $CodexDir) { Add-Dir 'codex' $d }
foreach ($d in (Get-ChildItem $UserHome -Directory -Force -Filter '.claude*' -ErrorAction SilentlyContinue)) {
  foreach ($m in 'settings.json', '.credentials.json', 'projects', 'commands', 'skills') { if (Test-Path (Join-Path $d.FullName $m)) { Add-Dir 'claude' $d.FullName; break } } }
foreach ($d in (Get-ChildItem $UserHome -Directory -Force -Filter '.codex*' -ErrorAction SilentlyContinue)) {
  foreach ($m in 'auth.json', 'config.toml', 'hooks.json', 'sessions') { if (Test-Path (Join-Path $d.FullName $m)) { Add-Dir 'codex' $d.FullName; break } } }
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
foreach ($d in $Claude) { Assign $d 'agent' }
foreach ($d in $Codex) { Assign $d 'codex' }

if ($List) {
  Say 'system: windows'
  foreach ($d in $Claude) { Say "claude  $($Map[$d])  $d" }
  foreach ($d in $Codex) { Say "codex   $($Map[$d])  $d" }
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
  Say "done. agent-bridge and the extra skills this installer added were removed. The mailbox $BR (messages, names.conf) is kept."; return }


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
$optSkill = $true; $optHooks = $true; $optBypass = -not $NoBypass; $optPath = -not $NoPath
function YN($q, $def) { $d = if ($def) { 'Y/n' } else { 'y/N' }; $r = Read-Host "  $($S.arrow) $q [$d]"; if ($r -match '^[Yy]') { return $true }; if ($r -match '^[Nn]') { return $false }; return $def }
# Items: objects with Label, Sub, On, Feat. $onKey is an optional scriptblock called with the pressed char (may modify $items; returns extra lines it printed).
function Ms-Run($items, [scriptblock]$onKey = $null) {
  $cur = 0; $top = 0; $drawn = 0; $first = $true
  while ($true) {
    $vis = [Math]::Max(5, [Console]::WindowHeight - 9); if ($vis -gt $items.Count) { $vis = $items.Count }
    if ($cur -lt $top) { $top = $cur }; if ($cur -ge $top + $vis) { $top = $cur - $vis + 1 }; if ($top -lt 0) { $top = 0 }
    if (-not $first) { [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $drawn)) }
    $first = $false; $cols = [Console]::WindowWidth; $drawn = 0
    for ($i = $top; $i -lt [Math]::Min($items.Count, $top + $vis); $i++) {
      $it = $items[$i]; $ptr = if ($i -eq $cur) { $S.arrow } else { ' ' }; $mark = if ($it.On) { $S.on } else { $S.off }
      $lab = if ($it.Feat) { "* $($it.Label)  featured" } else { $it.Label }
      $max = $cols - $lab.Length - 12; $sub = if ($max -lt 8) { '' } elseif ($it.Sub.Length -gt $max) { $it.Sub.Substring(0, $max) } else { $it.Sub }
      Write-Host "  " -NoNewline; Ui-W $ptr 'Cyan' -NoNewline; Write-Host " " -NoNewline
      Ui-W $mark $(if ($it.On) { 'Green' } else { 'DarkGray' }) -NoNewline; Write-Host "  " -NoNewline
      Ui-W $lab $(if ($it.Feat) { 'Magenta' } else { 'White' }) -NoNewline; Ui-W ("  $sub").PadRight($cols - 8 - $lab.Length) 'DarkGray'
      $drawn++ }
    if ($items.Count -gt $vis) { Ui-W ("  $($cur + 1)/$($items.Count)").PadRight($cols - 2) 'DarkGray'; $drawn++ }
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'Enter' { return }
      'UpArrow' { if ($cur -gt 0) { $cur-- } }
      'DownArrow' { if ($cur -lt $items.Count - 1) { $cur++ } }
      'Spacebar' { if ($items.Count -gt 0) { $items[$cur].On = -not $items[$cur].On } }
      default {
        $ch = [string]$k.KeyChar
        if ($ch -eq 'k') { if ($cur -gt 0) { $cur-- } } elseif ($ch -eq 'j') { if ($cur -lt $items.Count - 1) { $cur++ } }
        elseif ($ch -eq 'a' -and -not $onKey) { foreach ($it in $items) { $it.On = $true } }
        elseif ($ch -eq 'n' -and -not $onKey) { foreach ($it in $items) { $it.On = $false } }
        elseif ($onKey) { $extra = & $onKey $ch $items $cur; if ($extra) { $drawn += [int]$extra } } } } } }
function Ui-Hint($t) { Ui-W "  $t" 'DarkGray' }

if (-not $Yes -and -not $DryRun -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
  # --- accounts ---
  $acc = New-Object System.Collections.ArrayList
  foreach ($d in $Claude) { [void]$acc.Add([pscustomobject]@{ Kind = 'claude'; Dir = $d; Label = $Map[$d]; Sub = ''; On = $true; Feat = $false }) }
  foreach ($d in $Codex) { [void]$acc.Add([pscustomobject]@{ Kind = 'codex'; Dir = $d; Label = $Map[$d]; Sub = ''; On = $true; Feat = $false }) }
  function Acc-Refresh { foreach ($a in $acc) { $a.Label = $Map[$a.Dir]; $a.Sub = "$($a.Kind)   " + ($a.Dir -replace [regex]::Escape($UserHome), '~') } }
  Acc-Refresh
  Ui-H 'Accounts'; Ui-Hint 'up/down move | space select | r rename | + add folder | enter continue'; Say ''
  $accKey = {
    param($ch, $items, $cur)
    if ($ch -eq 'r') {
      $new = Read-Host "`n  $($S.arrow) new name for $($items[$cur].Label)"
      if ($new -match '^[A-Za-z0-9_-]+$' -and -not ($Map.Keys | Where-Object { $_ -ne $items[$cur].Dir -and $Map[$_] -eq $new })) { $Map[$items[$cur].Dir] = $new; Acc-Refresh }
      return 2 }
    if ($ch -eq '+') {
      $k = Read-Host "`n  $($S.arrow) type (claude/codex)"; $p = Norm (Read-Host "  $($S.arrow) folder")
      if ($k -in 'claude', 'codex' -and $p -and (Test-Path $p -PathType Container)) {
        Assign $p $(if ($k -eq 'claude') { 'agent' } else { 'codex' })
        [void]$acc.Add([pscustomobject]@{ Kind = $k; Dir = $p; Label = ''; Sub = ''; On = $true; Feat = $false }); Acc-Refresh }
      return 3 }
    return 0 }
  Ms-Run $acc $accKey
  $Claude.Clear(); $Codex.Clear()
  foreach ($a in $acc) { if ($a.On) { if ($a.Kind -eq 'claude') { $Claude.Add($a.Dir) } else { $Codex.Add($a.Dir) } } }
  # --- packages ---
  $pk = New-Object System.Collections.ArrayList
  [void]$pk.Add([pscustomobject]@{ Label = 'agent-bridge'; Sub = 'Claude Code + Codex sessions that talk to each other'; On = $true; Feat = $true })
  foreach ($x in $SkList) { [void]$pk.Add([pscustomobject]@{ Label = $x.Name; Sub = $x.Desc; On = $false; Feat = $false }) }
  Ui-H 'Packages'; Ui-Hint 'up/down move | space select | a all | n none | enter continue'; Say ''
  Ms-Run $pk
  $PkgAb = $pk[0].On; $SelSkills = @(); for ($i = 1; $i -lt $pk.Count; $i++) { if ($pk[$i].On) { $SelSkills += $pk[$i].Label } }
  if ($PkgAb) { Ab-Options-Menu }
  Say ''; Ui-Info "Accounts: $($Claude.Count + $Codex.Count)   |   agent-bridge: $(if ($PkgAb) { 'yes' } else { 'no' })   |   extra skills: $($SelSkills.Count)"
  if (-not (YN 'Proceed?' $true)) { Say 'cancelled'; return } }

# ---------- install ----------
Ui-H 'Installing'
$script:Steps = $(if ($PkgAb) { 1 } else { 0 }) + $Claude.Count + $Codex.Count
function Install-Skills($d) {
  foreach ($n in $SelSkills) {
    $from = Join-Path $RepoRoot $n; if (-not (Test-Path (Join-Path $from 'SKILL.md'))) { continue }
    $to = Join-Path $d "skills\$n"; Ensure-Dir (Join-Path $d 'skills'); if (Test-Path $to) { Remove-Item $to -Recurse -Force }
    Copy-Item $from $to -Recurse -Force; Remove-Item (Join-Path $to '.git') -Recurse -Force -ErrorAction SilentlyContinue
    Ensure-Dir (Split-Path $Manifest -Parent); $entry = "$d`t$n"
    if (-not ((Test-Path $Manifest) -and ((Get-Content $Manifest -Encoding UTF8) -contains $entry))) { Add-Content -Path $Manifest -Value $entry -Encoding UTF8 } } }
if ($PkgAb) { Step "Scripts  $($Bin -replace [regex]::Escape($UserHome), '~')" { Ab-Install-Global } }
foreach ($d in $Claude) { $n = $Map[$d]
  Step "Claude  $n  $($d -replace [regex]::Escape($UserHome), '~')" {
    if ($PkgAb) { Ab-Install-Claude $d $n }
    Install-Skills $d } }
foreach ($d in $Codex) { $n = $Map[$d]
  Step "Codex   $n  $($d -replace [regex]::Escape($UserHome), '~')" {
    if ($PkgAb) { Ab-Install-Codex $d $n }
    Install-Skills $d } }
if ($Claude.Count + $Codex.Count -eq 0) { Say 'No accounts found. Use -ClaudeDir DIR / -CodexDir DIR.' }
if ($DryRun) { Say ''; Say 'dry-run finished: nothing was written.'; return }
function Ui-Box($title, $lines) {
  $w = 54; Say ''; Ui-W ("  " + $S.tl + $S.h + " $title " + ($S.h * ($w - $title.Length - 3)) + $S.tr) 'Green'
  foreach ($l in $lines) { Ui-W ("  " + $S.v + "  ") 'Green' -NoNewline; Say $l }
  Ui-W ("  " + $S.bl + ($S.h * $w) + $S.br) 'Green'; Say '' }
$msg = if ($script:Fails -gt 0) { "$($S.fail) $($script:Fails) step(s) failed" } else { "$($S.ok) $($Claude.Count + $Codex.Count) account(s) configured" }
$sum = @($msg); if ($SelSkills.Count -gt 0) { $sum += "$($S.ok) skills: $($SelSkills -join ' ')" }
$sum += @('', 'Next steps', '  1. Restart open Claude/Codex sessions')
if ($PkgAb) { $sum += Ab-Next-Steps }
Ui-Box 'Done' $sum
