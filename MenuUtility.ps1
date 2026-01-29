# MenuUtility.ps1
# Menu-driven PowerShell utility + Winget menu + Paged catalog browser (UI polished)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------
# Theme / UI helpers
# ---------------------------

$script:AppName    = 'Menu Utility'
$script:AppVersion = '1.0.0'
$script:Crumb      = 'Main'

# Toggle colors off if you want maximum compatibility:
$script:UseColor = $true

function Write-C {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    if ($script:UseColor) {
        if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline }
        else { Write-Host $Text -ForegroundColor $Color }
    } else {
        if ($NoNewline) { Write-Host $Text -NoNewline }
        else { Write-Host $Text }
    }
}

function Pause-ForUser {
    Write-Host ''
    [void](Read-Host 'Press Enter to continue')
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    $resp = Read-Host "$Message (Y/N)"
    return ($resp -match '^(y|yes)$')
}

function Set-Crumb {
    param([Parameter(Mandatory)][string]$Text)
    $script:Crumb = $Text
}

function Write-Header {
    param([Parameter(Mandatory)][string]$Title)

    Clear-Host
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = ('=' * 56)

    Write-C $line ([ConsoleColor]::DarkGray)
    Write-C (" {0}  v{1}" -f $script:AppName, $script:AppVersion) ([ConsoleColor]::Cyan)
    Write-C (" {0}" -f $now) ([ConsoleColor]::DarkGray)
    Write-C (" Location: {0}" -f $script:Crumb) ([ConsoleColor]::Yellow)
    Write-C $line ([ConsoleColor]::DarkGray)
    Write-Host ''
    Write-C $Title ([ConsoleColor]::White)
    Write-Host ''
}

function Write-Menu {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][hashtable]$Items,
        [string[]]$FooterHints = @()
    )

    Write-Header $Title
    foreach ($k in ($Items.Keys | Sort-Object {[int]($_ -replace '\D','9999')}, $_)) {
        $label = $Items[$k]
        Write-C (" [{0}] {1}" -f $k, $label) ([ConsoleColor]::Gray)
    }
    Write-Host ''
    foreach ($h in $FooterHints) { Write-C $h ([ConsoleColor]::DarkGray) }
    Write-Host ''
}

function Read-Select {
    param([string]$Prompt = 'Select')
    return (Read-Host $Prompt).Trim()
}

# ---------------------------
# System / tools features
# ---------------------------

function Get-SystemSummary {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        OS           = $os.Caption
        OSVersion    = $os.Version
        BuildNumber  = $os.BuildNumber
        Uptime       = (Get-Date) - $os.LastBootUpTime
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        CPU          = $cpu.Name
        RAM_GB       = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 2)
        BIOS         = $bios.SMBIOSBIOSVersion
    }
}

function Show-SystemInfo {
    Set-Crumb 'Main > System Info'
    Write-Header 'System Info'
    Get-SystemSummary | Format-List
    Pause-ForUser
}

function Show-DiskUsage {
    Set-Crumb 'Main > Disk Usage'
    Write-Header 'Disk Usage'
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{n='Size(GB)';e={[math]::Round($_.Size/1GB,2)}},
            @{n='Free(GB)';e={[math]::Round($_.FreeSpace/1GB,2)}},
            @{n='Free(%)';e={ if ($_.Size) {[math]::Round(($_.FreeSpace/$_.Size)*100,2)} else {0} }} |
        Format-Table -AutoSize
    Pause-ForUser
}

function Show-NetworkInfo {
    Set-Crumb 'Main > Network Info'
    Write-Header 'Network Info'
    Write-C 'IP Configuration:' ([ConsoleColor]::Gray)
    Get-NetIPConfiguration | Format-Table -AutoSize

    Write-Host ''
    Write-C 'DNS servers (adapter settings):' ([ConsoleColor]::Gray)
    Get-DnsClientServerAddress -AddressFamily IPv4 |
        Select-Object InterfaceAlias, ServerAddresses |
        Format-Table -AutoSize
    Pause-ForUser
}

function Open-CommonToolsMenu {
    while ($true) {
        Set-Crumb 'Main > Tools'
        Write-Menu -Title 'Open Common Tools' -Items @{
            '1' = 'Task Manager'
            '2' = 'Services'
            '3' = 'Device Manager'
            '4' = 'Event Viewer'
            '5' = 'Control Panel'
            '0' = 'Back'
        } -FooterHints @('Tip: These open in separate windows.')

        $choice = Read-Select
        switch ($choice) {
            '1' { Start-Process 'taskmgr.exe' }
            '2' { Start-Process 'services.msc' }
            '3' { Start-Process 'devmgmt.msc' }
            '4' { Start-Process 'eventvwr.msc' }
            '5' { Start-Process 'control.exe' }
            '0' { return }
            default { Write-C 'Invalid choice.' ([ConsoleColor]::Red); Pause-ForUser }
        }
    }
}

function Cleanup-TempFiles {
    Set-Crumb 'Main > Cleanup'
    Write-Header 'Cleanup Temp Files'
    Write-C 'Targets:' ([ConsoleColor]::Gray)
    Write-C (" - User temp: {0}" -f $env:TEMP) ([ConsoleColor]::DarkGray)
    Write-C (" - Windows temp: {0}\Temp" -f $env:WINDIR) ([ConsoleColor]::DarkGray)
    Write-Host ''

    if (-not (Confirm-Action -Message 'This will delete TEMP files it can access. Continue?')) {
        Write-C 'Cancelled.' ([ConsoleColor]::Yellow)
        Pause-ForUser
        return
    }

    $targets = @($env:TEMP, (Join-Path $env:WINDIR 'Temp'))
    foreach ($t in $targets) {
        if (-not (Test-Path $t)) { continue }
        Write-C ("Cleaning: {0}" -f $t) ([ConsoleColor]::Gray)
        try {
            Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } catch {
            Write-C ("Warning: Some items could not be removed in {0}" -f $t) ([ConsoleColor]::Yellow)
        }
    }

    Write-Host ''
    Write-C 'Cleanup complete (best effort).' ([ConsoleColor]::Green)
    Pause-ForUser
}

# ---------------------------
# Winget features
# ---------------------------

$script:WingetCatalog = @()
$script:WingetCatalogQuery = $null

function Test-Winget {
    return [bool](Get-Command 'winget.exe' -ErrorAction SilentlyContinue)
}

function Get-WingetVersion {
    if (-not (Test-Winget)) { return $null }
    try { return (& winget --version 2>$null) -join ' ' } catch { return $null }
}

function Invoke-Winget {
    param([Parameter(Mandatory)][string[]]$Args)
    if (-not (Test-Winget)) { throw 'winget was not found on this system.' }
    & winget @Args
    return $LASTEXITCODE
}

function Show-WingetStatusLine {
    if (Test-Winget) {
        $ver = Get-WingetVersion
        if ($ver) { Write-C ("winget: FOUND ({0})" -f $ver) ([ConsoleColor]::Green) }
        else { Write-C 'winget: FOUND' ([ConsoleColor]::Green) }
    } else {
        Write-C 'winget: NOT FOUND' ([ConsoleColor]::Red)
        Write-C 'Install/repair "App Installer" (Microsoft Store / org portal).' ([ConsoleColor]::DarkGray)
    }
    Write-Host ''
}

function Winget-Search {
    Set-Crumb 'Main > Winget > Search'
    Write-Header 'Winget Search'
    Show-WingetStatusLine
    if (-not (Test-Winget)) { Pause-ForUser; return }

    $q = Read-Host 'Enter search query (name/publisher/tag)'
    if ([string]::IsNullOrWhiteSpace($q)) { return }

    Write-Host ''
    Invoke-Winget -Args @('search', '--query', $q)
    Pause-ForUser
}

function Winget-ListInstalled {
    Set-Crumb 'Main > Winget > List'
    Write-Header 'Winget List (Installed)'
    Show-WingetStatusLine
    if (-not (Test-Winget)) { Pause-ForUser; return }

    Invoke-Winget -Args @('list')
    Pause-ForUser
}

function Winget-InstallById {
    param([string]$Id)

    Set-Crumb 'Main > Winget > Install'
    Write-Header 'Winget Install (by ID)'
    Show-WingetStatusLine
    if (-not (Test-Winget)) { Pause-ForUser; return }

    if ([string]::IsNullOrWhiteSpace($Id)) {
        Write-C 'Tip: Use Search/Browse to find the exact ID.' ([ConsoleColor]::DarkGray)
        $Id = Read-Host 'Enter exact package ID (e.g., Git.Git, Microsoft.VisualStudioCode)'
        if ([string]::IsNullOrWhiteSpace($Id)) { return }
    }

    Write-Host ''
    Write-C ("About to install: {0}" -f $Id) ([ConsoleColor]::White)
    Write-C 'Uses: --exact --source winget --accept-*' ([ConsoleColor]::DarkGray)
    Write-Host ''

    if (-not (Confirm-Action -Message 'Proceed with install?')) {
        Write-C 'Cancelled.' ([ConsoleColor]::Yellow)
        Pause-ForUser
        return
    }

    $exit = Invoke-Winget -Args @(
        'install',
        '--id', $Id,
        '--exact',
        '--source', 'winget',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    Write-Host ''
    Write-C ("winget exit code: {0}" -f $exit) ([ConsoleColor]::DarkGray)
    Pause-ForUser
}

function Winget-UpgradeById {
    Set-Crumb 'Main > Winget > Upgrade (ID)'
    Write-Header 'Winget Upgrade (by ID)'
    Show-WingetStatusLine
    if (-not (Test-Winget)) { Pause-ForUser; return }

    $id = Read-Host 'Enter exact package ID to upgrade'
    if ([string]::IsNullOrWhiteSpace($id)) { return }

    Write-Host ''
    Write-C ("About to upgrade: {0}" -f $id) ([ConsoleColor]::White)
    Write-Host ''

    if (-not (Confirm-Action -Message 'Proceed with upgrade?')) {
        Write-C 'Cancelled.' ([ConsoleColor]::Yellow)
        Pause-ForUser
        return
    }

    $exit = Invoke-Winget -Args @(
        'upgrade',
        '--id', $id,
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    Write-Host ''
    Write-C ("winget exit code: {0}" -f $exit) ([ConsoleColor]::DarkGray)
    Pause-ForUser
}

function Winget-UpgradeAll {
    Set-Crumb 'Main > Winget > Upgrade All'
    Write-Header 'Winget Upgrade All'
    Show-WingetStatusLine
    if (-not (Test-Winget)) { Pause-ForUser; return }

    Write-C 'This will attempt to upgrade all applicable packages.' ([ConsoleColor]::Gray)
    Write-C 'Uses: --all --include-unknown --accept-*' ([ConsoleColor]::DarkGray)
    Write-Host ''

    if (-not (Confirm-Action -Message 'Proceed with upgrade-all?')) {
        Write-C 'Cancelled.' ([ConsoleColor]::Yellow)
        Pause-ForUser
        return
    }

    $exit = Invoke-Winget -Args @(
        'upgrade',
        '--all',
        '--include-unknown',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    Write-Host ''
    Write-C ("winget exit code: {0}" -f $exit) ([ConsoleColor]::DarkGray)
    Pause-ForUser
}

function ConvertFrom-WingetSearchOutput {
    param([Parameter(Mandatory)][string[]]$Lines)

    $sepIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*-{3,}\s*$' -or $Lines[$i] -match '^\s*-{3,}\s+-{3,}') {
            $sepIndex = $i
            break
        }
    }
    if ($sepIndex -lt 0 -or ($sepIndex + 1) -ge $Lines.Count) { return @() }

    $header = $Lines[$sepIndex - 1]
    $namePos   = $header.IndexOf('Name')
    $idPos     = $header.IndexOf('Id'); if ($idPos -lt 0) { $idPos = $header.IndexOf('ID') }
    $verPos    = $header.IndexOf('Version')
    $sourcePos = $header.IndexOf('Source')

    if ($namePos -lt 0 -or $idPos -lt 0) { return @() }
    if ($verPos -lt 0) { $verPos = $Lines[$sepIndex].Length }
    if ($sourcePos -lt 0) { $sourcePos = $Lines[$sepIndex].Length }

    $items = New-Object System.Collections.Generic.List[object]
    for ($j = $sepIndex + 1; $j -lt $Lines.Count; $j++) {
        $line = $Lines[$j]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -lt ($idPos + 2)) { continue }

        $name = $line.Substring($namePos, [math]::Max(0, $idPos - $namePos)).Trim()
        $id   = $line.Substring($idPos,   [math]::Max(0, $verPos - $idPos)).Trim()
        $ver  = if ($verPos -lt $sourcePos -and $line.Length -ge $sourcePos) {
            $line.Substring($verPos, [math]::Max(0, $sourcePos - $verPos)).Trim()
        } else { '' }
        $src  = if ($sourcePos -ge 0 -and $line.Length -gt $sourcePos) {
            $line.Substring($sourcePos).Trim()
        } else { '' }

        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $items.Add([pscustomobject]@{ Name=$name; Id=$id; Version=$ver; Source=$src })
    }
    return $items.ToArray()
}

function Get-WingetCatalog {
    param([Parameter(Mandatory)][string]$Query)

    if ($script:WingetCatalogQuery -eq $Query -and $script:WingetCatalog.Count -gt 0) {
        return $script:WingetCatalog
    }

    Set-Crumb 'Main > Winget > Browse (Fetching)'
    Write-Header 'Winget Catalog (fetching...)'
    Show-WingetStatusLine
    Write-C ("Query: {0}" -f $Query) ([ConsoleColor]::Gray)
    Write-C 'Tip: Use a specific filter for faster results.' ([ConsoleColor]::DarkGray)
    Write-Host ''

    $raw = & winget @('search','--source','winget','--query',$Query) 2>&1
    $lines = if ($raw -is [string]) { $raw -split "`r?`n" } else { [string[]]$raw }

    $items = ConvertFrom-WingetSearchOutput -Lines $lines
    $script:WingetCatalog = $items
    $script:WingetCatalogQuery = $Query
    return $items
}

function Winget-BrowseCatalogPaged {
    if (-not (Test-Winget)) {
        Set-Crumb 'Main > Winget > Browse'
        Write-Header 'Winget Catalog'
        Show-WingetStatusLine
        Pause-ForUser
        return
    }

    $query = '.'
    $pageSize = 20
    $page = 0
    $items = Get-WingetCatalog -Query $query

    while ($true) {
        Set-Crumb 'Main > Winget > Browse'
        Write-Header 'Winget Catalog (paged)'
        Show-WingetStatusLine

        Write-C ("Query: {0}" -f $query) ([ConsoleColor]::Gray)
        Write-C ("Results: {0}" -f $items.Count) ([ConsoleColor]::DarkGray)
        Write-Host ''

        if ($items.Count -eq 0) {
            Write-C 'No results. Use F to set a filter.' ([ConsoleColor]::Yellow)
        } else {
            $totalPages = [math]::Ceiling($items.Count / $pageSize)
            if ($totalPages -lt 1) { $totalPages = 1 }
            if ($page -lt 0) { $page = 0 }
            if ($page -ge $totalPages) { $page = $totalPages - 1 }

            $start = $page * $pageSize
            $end = [math]::Min($start + $pageSize - 1, $items.Count - 1)

            Write-C ("Page {0} / {1}" -f ($page + 1), $totalPages) ([ConsoleColor]::Cyan)
            Write-Host ''

            $display = @()
            $k = 1
            for ($i = $start; $i -le $end; $i++) {
                $it = $items[$i]
                $display += [pscustomobject]@{
                    No      = $k
                    Name    = $it.Name
                    Id      = $it.Id
                    Version = $it.Version
                }
                $k++
            }

            $display | Format-Table -AutoSize
            Write-Host ''
        }

        Write-C 'Commands:' ([ConsoleColor]::Gray)
        Write-C '  N = Next page   P = Previous page   F = Filter' ([ConsoleColor]::DarkGray)
        Write-C '  1-20 = Install item number on this page' ([ConsoleColor]::DarkGray)
        Write-C '  B = Back to Winget   M = Main menu   X = Exit app' ([ConsoleColor]::DarkGray)
        Write-Host ''

        $cmd = (Read-Host 'Select').Trim()
        if ([string]::IsNullOrWhiteSpace($cmd)) { continue }

        switch -Regex ($cmd) {
            '^(n|next)$'      { $page++ }
            '^(p|prev|previous)$' { $page-- }
            '^(f|filter)$' {
                $newQ = Read-Host 'Enter filter query (example: chrome, vscode, adobe). Use "." for broad'
                if (-not [string]::IsNullOrWhiteSpace($newQ)) {
                    $query = $newQ.Trim()
                    $page = 0
                    $items = Get-WingetCatalog -Query $query
                }
            }
            '^(b|back)$' { return }
            '^(m|main)$' { throw [System.Exception]::new('__GO_MAIN_MENU__') }
            '^(x|exit|quit)$' { throw [System.Exception]::new('__EXIT_APP__') }
            '^\d+$' {
                $num = [int]$cmd
                if ($num -lt 1 -or $num -gt $pageSize) { continue }
                $idx = ($page * $pageSize) + ($num - 1)
                if ($idx -lt 0 -or $idx -ge $items.Count) { continue }
                Winget-InstallById -Id $items[$idx].Id
            }
            default { Write-C 'Invalid command.' ([ConsoleColor]::Red); Pause-ForUser }
        }
    }
}

function Open-WingetMenu {
    while ($true) {
        Set-Crumb 'Main > Winget'
        Write-Menu -Title 'Winget Installer' -Items @{
            '1' = 'Search packages'
            '2' = 'Install package (by ID)'
            '3' = 'List installed (winget)'
            '4' = 'Upgrade package (by ID)'
            '5' = 'Upgrade ALL'
            '6' = 'Browse winget catalog (paged)'
            '0' = 'Back'
        } -FooterHints @(
            'Tip: Browse is best with a filter (F) for speed.'
        )

        $choice = Read-Select
        switch ($choice) {
            '1' { Winget-Search }
            '2' { Winget-InstallById -Id $null }
            '3' { Winget-ListInstalled }
            '4' { Winget-UpgradeById }
            '5' { Winget-UpgradeAll }
            '6' {
                try { Winget-BrowseCatalogPaged }
                catch {
                    if ($_.Exception.Message -in @('__GO_MAIN_MENU__','__EXIT_APP__')) { throw }
                    Write-C ("Error: {0}" -f $_.Exception.Message) ([ConsoleColor]::Red)
                    Pause-ForUser
                }
            }
            '0' { return }
            default { Write-C 'Invalid choice.' ([ConsoleColor]::Red); Pause-ForUser }
        }
    }
}

# ---------------------------
# Main menu
# ---------------------------

function Main-Menu {
    while ($true) {
        Set-Crumb 'Main'
        Write-Menu -Title 'Main Menu' -Items @{
            '1' = 'System Info'
            '2' = 'Disk Usage'
            '3' = 'Network Info'
            '4' = 'Open Common Tools'
            '5' = 'Cleanup Temp Files (destructive)'
            '6' = 'Winget Installer Menu'
            '0' = 'Exit'
        } -FooterHints @(
            'Tip: Run as Administrator for installs/upgrades that require elevation.'
        )

        $choice = Read-Select
        switch ($choice) {
            '1' { Show-SystemInfo }
            '2' { Show-DiskUsage }
            '3' { Show-NetworkInfo }
            '4' { Open-CommonToolsMenu }
            '5' { Cleanup-TempFiles }
            '6' {
                try { Open-WingetMenu }
                catch {
                    if ($_.Exception.Message -eq '__GO_MAIN_MENU__') { continue }
                    if ($_.Exception.Message -eq '__EXIT_APP__') { return }
                    Write-C ("Error: {0}" -f $_.Exception.Message) ([ConsoleColor]::Red)
                    Pause-ForUser
                }
            }
            '0' { return }
            default { Write-C 'Invalid choice.' ([ConsoleColor]::Red); Pause-ForUser }
        }
    }
}

Main-Menu
