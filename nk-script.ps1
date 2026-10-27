$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==========================================================
# 0) KONFIGURACJA
# ==========================================================
$script:Config = [ordered]@{
    preventSleepEnabled = $true
    writeErrorLog       = $false
    apps = @(
        [pscustomobject]@{ name = "firefox"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "msedge"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "vivaldi"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "paint shop pro"; minutes = 60; enabled = 1; killNow = 1 }
        [pscustomobject]@{ name = "XboxPcApp"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "StoreDesktopExtension"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "IGCC"; minutes = 60; enabled = 1; killNow = 0 }
        [pscustomobject]@{ name = "xmplay"; minutes = 60; enabled = 1; killNow = 0 }
    )
    stats = [ordered]@{
        totalKills = 0
        appKills = [ordered]@{
            firefox = 0
            msedge = 0
            vivaldi = 0
            "paint shop pro" = 0
            "XboxPcApp" = 0
            "StoreDesktopExtension" = 0
            "IGCC" = 0
            "xmplay" = 0
        }
    }
}

# ==========================================================
# 1) ŒCIE¯KI I ZMIENNE
# ==========================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "logs"
$ErrorLogPath = Join-Path $LogDir "killer_error.log"

# ==========================================================
# 2) FUNKCJE PODSTAWOWE
# ==========================================================
function Add-AppStatIfMissing {
    param([string]$AppName)

    if (-not $script:Config.stats.appKills) {
        $script:Config.stats.appKills = [ordered]@{}
    }

    $keys = @($script:Config.stats.appKills.PSObject.Properties.Name)
    if ($keys -notcontains $AppName) {
        $script:Config.stats.appKills[$AppName] = 0
    }
}

function Get-EnabledApps {
    if (-not $script:Config.apps) { return @() }

    $result = @()
    foreach ($app in $script:Config.apps) {
        if ($null -ne $app.enabled -and ([int]$app.enabled) -eq 1) {
            $result += $app
        }
    }
    return $result
}

function Get-KillNowApps {
    if (-not $script:Config.apps) { return @() }

    $result = @()
    foreach ($app in $script:Config.apps) {
        if ($null -ne $app.killNow -and ([int]$app.killNow) -eq 1) {
            $result += $app
        }
    }
    return $result
}

function Get-MaxCountdownMinutes {
    $apps = Get-EnabledApps
    if (-not $apps) { return 0 }
    return [int]($apps | Measure-Object -Property minutes -Maximum).Maximum
}

function Ensure-LogDirectory {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
}

function Write-LogToFile {
    param([string]$Text)

    if (-not $script:Config.writeErrorLog) { return }

    Ensure-LogDirectory
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | $Text" | Add-Content -Path $ErrorLogPath -Encoding UTF8
}

function Write-Log {
    param(
        [string]$Text,
        [ValidateSet("INFO","OK","WARN","ERROR","KILL","SKIP","FATAL")] [string]$Type = "INFO"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $tag = "[$Type]"
    $tagColor = [System.Drawing.Color]::White

    switch ($Type) {
        "SKIP" { $tagColor = [System.Drawing.Color]::Gray }
        "WARN" { $tagColor = [System.Drawing.Color]::Orange }
        "ERROR" { $tagColor = [System.Drawing.Color]::Red }
        "FATAL" { $tagColor = [System.Drawing.Color]::DarkRed }
        "KILL" { $tagColor = [System.Drawing.Color]::Firebrick }
        "OK" { $tagColor = [System.Drawing.Color]::LimeGreen }
        "INFO" { $tagColor = [System.Drawing.Color]::Yellow }
    }

    if ($null -ne $script:logBox) {
        $script:logBox.SelectionColor = [System.Drawing.Color]::White
        $script:logBox.AppendText("[$timestamp] ")
        $script:logBox.SelectionColor = $tagColor
        $script:logBox.AppendText("$tag ")
        $script:logBox.SelectionColor = [System.Drawing.Color]::White
        $script:logBox.AppendText("$Text`r`n")
        $script:logBox.ScrollToCaret()
    }

    Write-Host "[$timestamp] $tag $Text"

    if ($Type -eq "ERROR" -or $Type -eq "FATAL") {
        Write-LogToFile -Text "$tag $Text"
    }
}

function Kill-ProcessByName {
    param([string]$ProcessName)

    $name = $ProcessName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return 0 }

    $found = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if (-not $found) { return 0 }

    $killed = 0

    foreach ($proc in $found) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            $killed++
            Write-Log "Zabijam $name (PID: $($proc.Id))" "KILL"
        }
        catch {
            try {
                & taskkill.exe /F /IM $name /T | Out-Null
                $killed++
                Write-Log "KILL via taskkill: $name" "KILL"
            }
            catch {
                $msg = $_.Exception.Message
                Write-Log "Nie uda³o siê zamkn¹æ $name (PID: $($proc.Id)): $msg" "ERROR"
            }
        }
    }

    return $killed
}

# ==========================================================
# 3) ZAPOBIEGANIE USYPIANIU WINDOWS
# ==========================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SleepUtil {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
}
"@

function Set-PreventSleepState {
    param([bool]$Enabled)

    if ($Enabled) {
        [SleepUtil]::SetThreadExecutionState(
            [SleepUtil]::ES_CONTINUOUS -bor [SleepUtil]::ES_SYSTEM_REQUIRED -bor [SleepUtil]::ES_AWAYMODE_REQUIRED
        ) | Out-Null
        Write-Log "Zapobiegam usypianiu Windows" "OK"
    }
    else {
        [SleepUtil]::SetThreadExecutionState([SleepUtil]::ES_CONTINUOUS) | Out-Null
        Write-Log "Usypianie Windows aktywne ponownie" "INFO"
    }
}

function Update-AntiSleepHeartbeat {
    if (-not $script:Settings.preventSleepEnabled) { return }

    if (-not $script:LastAntiSleepLog) {
        $script:LastAntiSleepLog = Get-Date
    }

    $now = Get-Date
    if (($now - $script:LastAntiSleepLog).TotalHours -ge 3) {
        Write-Log "Proces anty-usypiania Windowsa pracuje..." "INFO"
        $script:LastAntiSleepLog = $now
    }
}

# ==========================================================
# 4) STAN APLIKACJI / UI
# ==========================================================
$script:Settings = $script:Config
$script:isLoadingGrid = $false
$script:SelectedAppIndex = -1
$script:LastAntiSleepLog = Get-Date
$script:lastLoggedTimerMinute = -1

function Refresh-AppGrid {
    $script:isLoadingGrid = $true
    try {
        if ($null -ne $script:appsGrid) {
            $script:appsGrid.Rows.Clear()
            foreach ($app in $script:Settings.apps) {
                $rowIndex = $script:appsGrid.Rows.Add()
                $script:appsGrid.Rows[$rowIndex].Cells["EnabledColumn"].Value = ([int]$app.enabled -eq 1)
                $script:appsGrid.Rows[$rowIndex].Cells["KillNowColumn"].Value = ([int]$app.killNow -eq 1)
                $script:appsGrid.Rows[$rowIndex].Cells["NameColumn"].Value = [string]$app.name
                $script:appsGrid.Rows[$rowIndex].Cells["MinutesColumn"].Value = [int]$app.minutes
            }
        }
    }
    finally {
        $script:isLoadingGrid = $false
    }
}

function Select-AppGridRow {
    param([int]$RowIndex)

    if ($null -eq $script:appsGrid) { return }
    if ($RowIndex -lt 0 -or $RowIndex -ge $script:appsGrid.Rows.Count) { return }

    $script:SelectedAppIndex = $RowIndex
    $script:appsGrid.ClearSelection()
    $script:appsGrid.Rows[$RowIndex].Selected = $true
    $script:appsGrid.CurrentCell = $script:appsGrid.Rows[$RowIndex].Cells["NameColumn"]
}

function RefreshProgressDisplay {
    $targetMinutes = Get-MaxCountdownMinutes
    $targetSeconds = [int]($targetMinutes * 60)

    if ($script:countdownRunning) {
        $elapsed = [Math]::Min($targetSeconds, [int]((Get-Date) - $script:countdownStart).TotalSeconds)
        $remaining = [Math]::Max(0, $targetSeconds - $elapsed)

        $progressBar.Maximum = $targetSeconds
        $progressBar.Value = $elapsed

        $minsLeft = [Math]::Floor($remaining / 60)
        $secsLeft = $remaining % 60
        $totalMins = [Math]::Floor($targetSeconds / 60)
        $totalSecs = $targetSeconds % 60

        $script:progressLabel.Text = "{0:00}:{1:00} / {2:00}:{3:00}" -f $minsLeft, $secsLeft, $totalMins, $totalSecs
    }
    else {
        $script:progressLabel.Text = "00:00 / {0:00}:{1:00}" -f ([Math]::Floor($targetSeconds / 60)), ($targetSeconds % 60)
        $progressBar.Maximum = [Math]::Max(1, $targetSeconds)
        $progressBar.Value = 0
    }
}

function Invoke-KillNow {
    $appsToKill = Get-KillNowApps

    if (-not $appsToKill) {
        Write-Log "Zaznacz aplikacje w kolumnie KILLNow" "WARN"
        return
    }

    $totalKilled = 0

    foreach ($app in $appsToKill) {
        $name = [string]$app.name

        if ([string]::IsNullOrWhiteSpace($name)) {
            Write-Log "Wybrana aplikacja ma pust¹ nazwê" "ERROR"
            $app.killNow = 0
            continue
        }

        $found = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if (-not $found) {
            Write-Log "KillNow: '$name' nie jest aktywna (proces nie istnieje)" "SKIP"
            $app.killNow = 0
            Refresh-AppGrid
            continue
        }

        $killed = Kill-ProcessByName -ProcessName $name
        if ($killed -gt 0) {
            $totalKilled += $killed
            $script:Settings.stats.totalKills += $killed
            Add-AppStatIfMissing -AppName $name
            $script:Settings.stats.appKills[$name] += $killed

            $app.killNow = 0
            Write-Log "KillNow: '$name' zosta³a zamkniêta ($killed procesów)" "OK"
        }
        else {
            Write-Log "KillNow: '$name' nie jest aktywna (po próbie zamkniêcia nie ma procesu)" "SKIP"
            $app.killNow = 0
        }

        Refresh-AppGrid
        RefreshProgressDisplay
    }

    if ($totalKilled -gt 0) {
        Write-Log "Zamkniêto ³¹cznie: $totalKilled procesów" "OK"
    }
}

function Start-Countdown {
    $enabledApps = Get-EnabledApps
    if (-not $enabledApps) {
        Write-Log "Brak aktywnych aplikacji do odliczania. Zaznacz kolumnê Timer." "ERROR"
        return
    }

    $script:countdownRunning = $true
    $script:cancelCountdown = $false
    $script:countdownWarningIssued = $false
    $script:lastLoggedTimerMinute = -1
    $script:countdownStart = Get-Date
    $script:countdownTargetSeconds = [int]((Get-MaxCountdownMinutes) * 60)
    $script:countdownTimer.Start()

    $names = @($enabledApps | ForEach-Object { $_.name } | Sort-Object -Unique)
    Write-Log "Odliczanie rozpoczête dla: $($names -join ', ') ($($script:countdownTargetSeconds / 60) min)" "INFO"
    $progressBar.ForeColor = [System.Drawing.Color]::LimeGreen
    RefreshProgressDisplay
}

# ==========================================================
# 5) G£ÓWNE OKNO
# ==========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Nocny Killer v2.13"
$form.Size = New-Object System.Drawing.Size(1080, 960)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::Black
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Font = New-Object System.Drawing.Font("Consolas", 10)

$script:dragging = $false
$script:dragOffset = New-Object System.Drawing.Point

$headerBar = New-Object System.Windows.Forms.Panel
$headerBar.Size = New-Object System.Drawing.Size(1080, 42)
$headerBar.Location = New-Object System.Drawing.Point(0, 0)
$headerBar.BackColor = [System.Drawing.Color]::FromArgb(14, 65, 124)
$headerBar.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$form.Controls.Add($headerBar)

$headerBar.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $true
        $script:dragOffset = New-Object System.Drawing.Point($_.X, $_.Y)
    }
})
$headerBar.Add_MouseMove({
    if ($script:dragging) {
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $_.X - $script:dragOffset.X),
            ($form.Location.Y + $_.Y - $script:dragOffset.Y)
        )
    }
})
$headerBar.Add_MouseUp({
    $script:dragging = $false
})

$mainTitle = New-Object System.Windows.Forms.Label
$mainTitle.Text = "Nocny Killer v2.13"
$mainTitle.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$mainTitle.ForeColor = [System.Drawing.Color]::White
$mainTitle.AutoSize = $true
$mainTitle.Location = New-Object System.Drawing.Point(8, 9)
$headerBar.Controls.Add($mainTitle)

$dirButton = New-Object System.Windows.Forms.Button
$dirButton.Text = "D"
$dirButton.Size = New-Object System.Drawing.Size(28, 22)
$dirButton.Location = New-Object System.Drawing.Point(990, 9)
$dirButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$dirButton.ForeColor = [System.Drawing.Color]::White
$dirButton.BackColor = [System.Drawing.Color]::FromArgb(14, 65, 124)
$dirButton.Add_Click({
    Ensure-LogDirectory
    Start-Process explorer.exe $LogDir
    Write-Log "Otworzono katalog logów: $LogDir" "INFO"
})
$headerBar.Controls.Add($dirButton)

$miniButton1 = New-Object System.Windows.Forms.Button
$miniButton1.Text = "_"
$miniButton1.Size = New-Object System.Drawing.Size(22, 22)
$miniButton1.Location = New-Object System.Drawing.Point(1020, 9)
$miniButton1.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$miniButton1.ForeColor = [System.Drawing.Color]::White
$miniButton1.BackColor = [System.Drawing.Color]::FromArgb(14, 65, 124)
$miniButton1.Add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$headerBar.Controls.Add($miniButton1)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "X"
$closeButton.Size = New-Object System.Drawing.Size(22, 22)
$closeButton.Location = New-Object System.Drawing.Point(1044, 9)
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.ForeColor = [System.Drawing.Color]::White
$closeButton.BackColor = [System.Drawing.Color]::FromArgb(14, 65, 124)
$closeButton.Add_Click({ $form.Close() })
$headerBar.Controls.Add($closeButton)

# ==========================================================
# 6) CHECKBOXY
# ==========================================================
$checkboxPanel = New-Object System.Windows.Forms.Panel
$checkboxPanel.Location = New-Object System.Drawing.Point(20, 58)
$checkboxPanel.Size = New-Object System.Drawing.Size(1040, 32)
$checkboxPanel.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($checkboxPanel)

$preventSleepCheckbox = New-Object System.Windows.Forms.CheckBox
$preventSleepCheckbox.Text = "Zapobiega usypianiu Windows"
$preventSleepCheckbox.Location = New-Object System.Drawing.Point(0, 4)
$preventSleepCheckbox.Size = New-Object System.Drawing.Size(420, 24)
$preventSleepCheckbox.ForeColor = [System.Drawing.Color]::White
$preventSleepCheckbox.BackColor = [System.Drawing.Color]::Black
$preventSleepCheckbox.Font = New-Object System.Drawing.Font("Consolas", 14)
$preventSleepCheckbox.Checked = [bool]$script:Settings.preventSleepEnabled
$checkboxPanel.Controls.Add($preventSleepCheckbox)

$writeErrorLogCheckbox = New-Object System.Windows.Forms.CheckBox
$writeErrorLogCheckbox.Text = "Zapisuj b³¹d do logu"
$writeErrorLogCheckbox.Location = New-Object System.Drawing.Point(500, 4)
$writeErrorLogCheckbox.Size = New-Object System.Drawing.Size(320, 24)
$writeErrorLogCheckbox.ForeColor = [System.Drawing.Color]::White
$writeErrorLogCheckbox.BackColor = [System.Drawing.Color]::Black
$writeErrorLogCheckbox.Font = New-Object System.Drawing.Font("Consolas", 14)
$writeErrorLogCheckbox.Checked = [bool]$script:Settings.writeErrorLog
$checkboxPanel.Controls.Add($writeErrorLogCheckbox)

$preventSleepCheckbox.Add_CheckedChanged({
    $script:Settings.preventSleepEnabled = $preventSleepCheckbox.Checked
    Set-PreventSleepState -Enabled $preventSleepCheckbox.Checked
    if ($preventSleepCheckbox.Checked) {
        $script:LastAntiSleepLog = Get-Date
        Write-Log "Proces anty-usypiania Windowsa pracuje..." "INFO"
    }
})

$writeErrorLogCheckbox.Add_CheckedChanged({
    $script:Settings.writeErrorLog = $writeErrorLogCheckbox.Checked
    if ($writeErrorLogCheckbox.Checked) {
        Ensure-LogDirectory
        Write-Log "Zapis b³êdów do pliku zosta³ w³¹czony: $ErrorLogPath" "INFO"
    }
    else {
        Write-Log "Zapis b³êdów do pliku zosta³ wy³¹czony" "INFO"
    }
})

# ==========================================================
# 7) TABELA APLIKACJI + PANEL AKCJI
# ==========================================================
$appsGrid = New-Object System.Windows.Forms.DataGridView
$appsGrid.Location = New-Object System.Drawing.Point(20, 110)
$appsGrid.Size = New-Object System.Drawing.Size(760, 340)
$appsGrid.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
$appsGrid.ForeColor = [System.Drawing.Color]::LightGray
$appsGrid.GridColor = [System.Drawing.Color]::Gray
$appsGrid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$appsGrid.RowHeadersVisible = $false
$appsGrid.AllowUserToAddRows = $false
$appsGrid.AllowUserToDeleteRows = $false
$appsGrid.ReadOnly = $false
$appsGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
$appsGrid.AllowUserToResizeColumns = $false
$appsGrid.AllowUserToResizeRows = $false
$appsGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$appsGrid.MultiSelect = $false
$appsGrid.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$appsGrid.Font = New-Object System.Drawing.Font("Consolas", 14)
$appsGrid.ColumnHeadersHeight = 36
$appsGrid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
$appsGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::Gray
$appsGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$appsGrid.ColumnHeadersDefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
$appsGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$appsGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$appsGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$appsGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 38)
$appsGrid.RowTemplate.Height = 28
$form.Controls.Add($appsGrid)
$script:appsGrid = $appsGrid

$enabledCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$enabledCol.Name = "EnabledColumn"
$enabledCol.HeaderText = "Timer"
$enabledCol.Width = 110
$enabledCol.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
$appsGrid.Columns.Add($enabledCol)

$killNowCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$killNowCol.Name = "KillNowColumn"
$killNowCol.HeaderText = "KILLNow"
$killNowCol.Width = 120
$killNowCol.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
$appsGrid.Columns.Add($killNowCol)

$nameCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$nameCol.Name = "NameColumn"
$nameCol.HeaderText = "Nazwa procesu"
$nameCol.Width = 430
$nameCol.ReadOnly = $true
$nameCol.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
$appsGrid.Columns.Add($nameCol)

$minutesCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$minutesCol.Name = "MinutesColumn"
$minutesCol.HeaderText = "Minuty"
$minutesCol.Width = 100
$minutesCol.ReadOnly = $true
$minutesCol.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
$appsGrid.Columns.Add($minutesCol)

$appsGrid.Add_CellMouseDown({
    if ($_.RowIndex -lt 0) { return }
    Select-AppGridRow -RowIndex $_.RowIndex
})

$appsGrid.Add_CellContentClick({
    if ($_.RowIndex -lt 0) { return }

    $rowIndex = [int]$_.RowIndex
    $app = $script:Settings.apps[$rowIndex]
    if ($null -eq $app) { return }

    if ($_.ColumnIndex -eq $appsGrid.Columns["EnabledColumn"].Index) {
        $current = [bool]$appsGrid.Rows[$rowIndex].Cells["EnabledColumn"].Value
        $newValue = -not $current

        $appsGrid.Rows[$rowIndex].Cells["EnabledColumn"].Value = [bool]$newValue
        $app.enabled = [int][bool]$newValue

        Write-Log "Timer: $($app.name) = $($app.enabled)" "INFO"
        RefreshProgressDisplay
        return
    }

    if ($_.ColumnIndex -eq $appsGrid.Columns["KillNowColumn"].Index) {
        $current = [bool]$appsGrid.Rows[$rowIndex].Cells["KillNowColumn"].Value
        $newValue = -not $current

        $appsGrid.Rows[$rowIndex].Cells["KillNowColumn"].Value = [bool]$newValue
        $app.killNow = [int][bool]$newValue

        Write-Log "KILLNow: $($app.name) = $($app.killNow)" "INFO"
    }
})

$panelRight = New-Object System.Windows.Forms.Panel
$panelRight.Location = New-Object System.Drawing.Point(800, 110)
$panelRight.Size = New-Object System.Drawing.Size(260, 340)
$panelRight.BackColor = [System.Drawing.Color]::FromArgb(25,25,25)
$form.Controls.Add($panelRight)

$killSelectedButton = New-Object System.Windows.Forms.Button
$killSelectedButton.Text = "KILL!Now"
$killSelectedButton.Location = New-Object System.Drawing.Point(12, 12)
$killSelectedButton.Size = New-Object System.Drawing.Size(236, 70)
$killSelectedButton.BackColor = [System.Drawing.Color]::Firebrick
$killSelectedButton.ForeColor = [System.Drawing.Color]::White
$killSelectedButton.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
$killSelectedButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$killSelectedButton.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray
$killSelectedButton.FlatAppearance.BorderSize = 1
$killSelectedButton.Add_Click({ Invoke-KillNow })
$panelRight.Controls.Add($killSelectedButton)

$timerButtonRight = New-Object System.Windows.Forms.Button
$timerButtonRight.Text = "Timer"
$timerButtonRight.Location = New-Object System.Drawing.Point(12, 96)
$timerButtonRight.Size = New-Object System.Drawing.Size(236, 70)
$timerButtonRight.BackColor = [System.Drawing.Color]::Blue
$timerButtonRight.ForeColor = [System.Drawing.Color]::White
$timerButtonRight.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
$timerButtonRight.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$timerButtonRight.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray
$timerButtonRight.FlatAppearance.BorderSize = 1
$timerButtonRight.Add_Click({
    if ($script:countdownRunning) {
        $script:cancelCountdown = $true
        $script:countdownRunning = $false
        $script:countdownTimer.Stop()
        $progressBar.Value = 0
        RefreshProgressDisplay
        Write-Log "Odliczanie zatrzymane przez u¿ytkownika" "INFO"
        return
    }

    Start-Countdown
})
$panelRight.Controls.Add($timerButtonRight)

$restartTimerButton = New-Object System.Windows.Forms.Button
$restartTimerButton.Text = "Restart"
$restartTimerButton.Location = New-Object System.Drawing.Point(12, 180)
$restartTimerButton.Size = New-Object System.Drawing.Size(236, 46)
$restartTimerButton.BackColor = [System.Drawing.Color]::FromArgb(52, 152, 219)
$restartTimerButton.ForeColor = [System.Drawing.Color]::White
$restartTimerButton.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
$restartTimerButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$restartTimerButton.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray
$restartTimerButton.FlatAppearance.BorderSize = 1
$restartTimerButton.Add_Click({
    if ($script:countdownRunning) {
        $script:countdownTimer.Stop()
    }

    Start-Countdown
})
$panelRight.Controls.Add($restartTimerButton)

$exitButtonRight = New-Object System.Windows.Forms.Button
$exitButtonRight.Text = "EXIT"
$exitButtonRight.Location = New-Object System.Drawing.Point(12, 236)
$exitButtonRight.Size = New-Object System.Drawing.Size(236, 70)
$exitButtonRight.BackColor = [System.Drawing.Color]::DarkSlateGray
$exitButtonRight.ForeColor = [System.Drawing.Color]::White
$exitButtonRight.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
$exitButtonRight.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$exitButtonRight.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray
$exitButtonRight.FlatAppearance.BorderSize = 1
$exitButtonRight.Add_Click({
    if ($script:countdownRunning -and -not $script:cancelCountdown) {
        $script:cancelCountdown = $true
        $script:countdownRunning = $false
        $script:countdownTimer.Stop()
        $progressBar.Value = 0
        RefreshProgressDisplay
        Write-Log "Odliczanie zatrzymane przez u¿ytkownika" "INFO"
        return
    }

    Set-PreventSleepState -Enabled $false
    Write-Log "Zamykanie aplikacji" "INFO"
    $form.Close()
})
$panelRight.Controls.Add($exitButtonRight)

# ==========================================================
# 8) PASEK POSTÊPU
# ==========================================================
$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Location = New-Object System.Drawing.Point(20, 480)
$progressLabel.Size = New-Object System.Drawing.Size(1038, 32)
$progressLabel.ForeColor = [System.Drawing.Color]::White
$progressLabel.Font = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
$progressLabel.Text = "00:00 / 00:00"
$progressLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($progressLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 515)
$progressBar.Size = New-Object System.Drawing.Size(1038, 30)
$progressBar.Minimum = 0
$progressBar.Value = 0
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressBar.ForeColor = [System.Drawing.Color]::LimeGreen
$progressBar.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
$progressBar.Font = New-Object System.Drawing.Font("Consolas", 12)
$form.Controls.Add($progressBar)

# ==========================================================
# 9) LOGI
# ==========================================================
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(20, 560)
$logBox.Size = New-Object System.Drawing.Size(1038, 355)
$logBox.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$logBox.ForeColor = [System.Drawing.Color]::White
$logBox.Font = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold)
$logBox.ReadOnly = $true
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$logBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$form.Controls.Add($logBox)
$script:logBox = $logBox

$footer = New-Object System.Windows.Forms.LinkLabel
$footer.Text = "Konfigurowalny Nocny Killer | spazma.github.io"
$footer.Location = New-Object System.Drawing.Point(0, 929)
$footer.Size = New-Object System.Drawing.Size(1080, 30)
$footer.BackColor = [System.Drawing.Color]::SaddleBrown
$footer.ForeColor = [System.Drawing.Color]::White
$footer.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$footer.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
$footer.LinkColor = [System.Drawing.Color]::White
$footer.VisitedLinkColor = [System.Drawing.Color]::White
$footer.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$footer.LinkArea = New-Object System.Windows.Forms.LinkArea(0, 0)

$linkText = "spazma.github.io"
$footer.LinkArea = New-Object System.Windows.Forms.LinkArea($footer.Text.IndexOf($linkText), $linkText.Length)
$footer.Add_LinkClicked({
    Start-Process "https://spazma.github.io"
})

$form.Controls.Add($footer)

# ==========================================================
# 10) TIMER
# ==========================================================
$script:countdownRunning = $false
$script:cancelCountdown = $false
$script:countdownTargetSeconds = 0
$script:countdownStart = Get-Date
$script:countdownWarningIssued = $false

$countdownTimer = New-Object System.Windows.Forms.Timer
$countdownTimer.Interval = 1000
$countdownTimer.Enabled = $false

$countdownTimer.Add_Tick({
    if (-not $script:countdownRunning) {
        $countdownTimer.Stop()
        RefreshProgressDisplay
        return
    }

    if ($script:cancelCountdown) {
        $countdownTimer.Stop()
        $script:countdownRunning = $false
        $progressBar.Value = 0
        RefreshProgressDisplay
        Write-Log "Odliczanie przerwane przez u¿ytkownika" "INFO"
        return
    }

    Update-AntiSleepHeartbeat

    $elapsed = [int]((Get-Date) - $script:countdownStart).TotalSeconds
    $target = [int]$script:countdownTargetSeconds
    $remaining = [Math]::Max(0, $target - $elapsed)

    if (-not $script:countdownWarningIssued -and $remaining -le 180) {
        $script:countdownWarningIssued = $true
        Write-Log "OSTRZE¯ENIE: zosta³y 3 minuty do koñca odliczania." "WARN"
        $progressBar.ForeColor = [System.Drawing.Color]::Orange
    }

    $minutesLeft = [Math]::Ceiling($remaining / 60.0)
    if ($remaining -gt 0 -and $minutesLeft -ne $script:lastLoggedTimerMinute) {
        $script:lastLoggedTimerMinute = $minutesLeft
        Write-Log "Timer zakoñczy siê za $minutesLeft min" "INFO"
    }

    if ($elapsed -ge $target) {
        $countdownTimer.Stop()
        $script:countdownRunning = $false
        $appsToKill = Get-EnabledApps
        $totalKilled = 0

        foreach ($app in $appsToKill) {
            if (([int]$app.enabled) -ne 1) {
                Write-Log "$($app.name) pominiêta (Timer = OFF)" "SKIP"
                continue
            }

            $killed = Kill-ProcessByName -ProcessName $app.name
            $totalKilled += $killed

            if ($killed -gt 0) {
                $script:Settings.stats.totalKills += $killed
                Add-AppStatIfMissing -AppName $app.name
                $script:Settings.stats.appKills[$app.name] += $killed
                $app.killNow = 0
                $app.enabled = 0
                Write-Log "$($app.name) zamkniêta po czasie: $killed procesów" "OK"
            }
        }

        $progressBar.Value = 0
        $progressBar.ForeColor = [System.Drawing.Color]::LimeGreen
        RefreshProgressDisplay
        Write-Log "Odliczanie zakoñczone. Zabito ³¹cznie: $totalKilled procesów" "OK"
        Refresh-AppGrid
        return
    }

    if ($remaining -le 60) {
        $progressBar.ForeColor = [System.Drawing.Color]::Red
    }
    elseif ($remaining -le 180) {
        $progressBar.ForeColor = [System.Drawing.Color]::Orange
    }
    else {
        $progressBar.ForeColor = [System.Drawing.Color]::LimeGreen
    }

    $progressBar.Maximum = [Math]::Max(1, $target)
    $progressBar.Value = [Math]::Min($target, $elapsed)
    RefreshProgressDisplay
})

$script:countdownTimer = $countdownTimer

$form.Add_FormClosing({
    Set-PreventSleepState -Enabled $false
    if ($script:countdownTimer) {
        $script:countdownTimer.Stop()
    }
})

# ==========================================================
# 11) START
# ==========================================================
Refresh-AppGrid
RefreshProgressDisplay

if ($script:Config.preventSleepEnabled) {
    Set-PreventSleepState -Enabled $true
    $script:LastAntiSleepLog = Get-Date
    Write-Log "Proces anty-usypiania Windowsa pracuje..." "INFO"
}

Write-Log "Przywrócono konfiguracjê: $($script:Settings.apps.Count) pozycji" "INFO"
Write-Log "Nocny Killer v2.13 uruchomiony. Konfiguracja: $($script:Settings.apps.Count) aplikacji" "INFO"

[void]$form.ShowDialog()