
# MantenerActivo.ps1
# Windows PowerShell 5.1
# API nativa de energia + F15 + contador en consola + icono de bandeja.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("PowerRequestNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class PowerRequestNative {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
}

if (-not ("KeyNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class KeyNative {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern short GetKeyState(int nVirtKey);
}
"@
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:VK_F15 = [byte]0x7E
$script:VK_NUMLOCK = 0x90
$script:KEYEVENTF_KEYUP = [uint32]2

$script:ES_CONTINUOUS       = [uint32]2147483648
$script:ES_SYSTEM_REQUIRED  = [uint32]1
$script:ES_DISPLAY_REQUIRED = [uint32]2

$script:running = $false
$script:endTime = [datetime]::MinValue
$script:lastKeyTime = [datetime]::MinValue
$script:lastConsoleMinute = -1
$script:counterLineActive = $false

function Write-Log {
    param([string]$Level, [string]$Message)

    if ($script:counterLineActive) {
        Write-Host ""
        $script:counterLineActive = $false
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function New-HourglassIcon([System.Drawing.Color]$Color) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $pen = New-Object System.Drawing.Pen($Color, 3)
    $brush = New-Object System.Drawing.SolidBrush($Color)

    $g.DrawLine($pen, 8, 5, 24, 5)
    $g.DrawLine($pen, 8, 27, 24, 27)
    $g.DrawLine($pen, 9, 6, 23, 26)
    $g.DrawLine($pen, 23, 6, 9, 26)

    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,9),
        [System.Drawing.Point]::new(21,9),
        [System.Drawing.Point]::new(16,14)
    ))
    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,23),
        [System.Drawing.Point]::new(21,23),
        [System.Drawing.Point]::new(16,18)
    ))

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)

    $g.Dispose()
    $pen.Dispose()
    $brush.Dispose()
    $bmp.Dispose()

    return $icon
}

function Set-TrayIcon {
    param(
        [System.Drawing.Icon]$Icon,
        [string]$Tip
    )

    $script:notifyIcon.Icon = $Icon
    $script:notifyIcon.Text = $Tip.Substring(
        0, [Math]::Min(63, $Tip.Length)
    )
}

function Clear-PowerRequest {
    try {
        [void][PowerRequestNative]::SetThreadExecutionState(
            $script:ES_CONTINUOUS
        )
        Write-Log "OK" "Solicitud de energia liberada"
    }
    catch {
        Write-Log "ERROR" "No se pudo liberar energia: $($_.Exception.Message)"
    }
}

function Stop-Session {
    if (-not $script:running) { return }

    $script:running = $false
    $script:timer.Stop()

    Write-Log "INFO" "Deteniendo mecanismos de actividad"
    Clear-PowerRequest

    $script:lastKeyTime = [datetime]::MinValue
    $script:lastConsoleMinute = -1
    $script:counterLineActive = $false

    Set-TrayIcon $script:iconRed "MantenerActivo: detenido"
    $script:startItem.Enabled = $true
    $script:stopItem.Enabled = $false
    $script:statusItem.Text = "Estado: detenido"

    Write-Log "INFO" "Sesion detenida"
}

function Start-Session([int]$Minutes) {
    if ($script:running) {
        Stop-Session
    }

    $script:endTime = [datetime]::Now.AddMinutes($Minutes)
    $script:lastKeyTime = [datetime]::MinValue
    $script:lastConsoleMinute = -1

    Write-Log "INFO" "Iniciando sesion de $Minutes minutos"

    $result = [PowerRequestNative]::SetThreadExecutionState(
        [uint32](
            $script:ES_CONTINUOUS -bor
            $script:ES_SYSTEM_REQUIRED -bor
            $script:ES_DISPLAY_REQUIRED
        )
    )

    if ($result -ne 0) {
        Write-Log "OK" "SetThreadExecutionState activo"
        Write-Log "OK" "Solicitud de equipo despierto y pantalla encendida"
    }
    else {
        Write-Log "ERROR" "SetThreadExecutionState fallo"
    }

    $script:running = $true
    $script:startItem.Enabled = $false
    $script:stopItem.Enabled = $true
    $script:statusItem.Text = "Estado: activo"

    Write-Log "INFO" "Simulacion F15: cada 30 segundos"

    $script:timer.Start()
    Update-Session
}

function Update-Session {
    if (-not $script:running) { return }

    $remaining = $script:endTime - [datetime]::Now

    if ($remaining.TotalSeconds -le 0) {
        Write-Log "INFO" "Tiempo finalizado"
        Stop-Session
        return
    }

    # Segundo mecanismo: enviar F15 cada 30 segundos.
    if (
        ($script:lastKeyTime -eq [datetime]::MinValue) -or
        (([datetime]::Now - $script:lastKeyTime).TotalSeconds -ge 30)
    ) {
        try {
            # keybd_event no toca Bloq Num (SendKeys de WScript.Shell si puede).
            $numBefore = [KeyNative]::GetKeyState($script:VK_NUMLOCK) -band 1
            [KeyNative]::keybd_event($script:VK_F15, 0, 0, [UIntPtr]::Zero)
            [KeyNative]::keybd_event($script:VK_F15, 0, $script:KEYEVENTF_KEYUP, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50

            # Salvaguarda: si Bloq Num cambio, restaurarlo.
            $numAfter = [KeyNative]::GetKeyState($script:VK_NUMLOCK) -band 1
            if ($numAfter -ne $numBefore) {
                [KeyNative]::keybd_event([byte]$script:VK_NUMLOCK, 0x45, 1, [UIntPtr]::Zero)
                [KeyNative]::keybd_event([byte]$script:VK_NUMLOCK, 0x45, 3, [UIntPtr]::Zero)
                Write-Log "INFO" "Bloq Num restaurado"
            }

            $script:lastKeyTime = [datetime]::Now
            Write-Log "EVENTO" "Pulsacion F15 enviada"
        }
        catch {
            Write-Log "ERROR" "Fallo al enviar F15: $($_.Exception.Message)"
        }
    }

    # Contador: una actualizacion por minuto.
    $minuteMarker = [int][Math]::Floor($remaining.TotalSeconds / 60)
    $text = "{0:00}:{1:00}:{2:00}" -f `
        [int][Math]::Floor($remaining.TotalHours),
        $remaining.Minutes,
        $remaining.Seconds

    if ($minuteMarker -ne $script:lastConsoleMinute) {
        if ($script:counterLineActive) {
            Write-Host "`r" -NoNewline
        }

        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host -NoNewline "[$timestamp] Tiempo restante: $text"

        $script:counterLineActive = $true
        $script:lastConsoleMinute = $minuteMarker
    }

    # Actualizar cada segundo el tiempo restante visible en el tooltip.
    $tooltip = "Restante: $text"

    if ($remaining.TotalMinutes -le 5) {
        Set-TrayIcon $script:iconYellow "AMARILLO - $tooltip"
    }
    else {
        Set-TrayIcon $script:iconGreen "VERDE - $tooltip"
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "       MANTENER ACTIVO - WINDOWS"
Write-Host "========================================"
Write-Log "INFO" "Aplicacion iniciada"

$script:iconGreen  = New-HourglassIcon ([System.Drawing.Color]::LimeGreen)
$script:iconYellow = New-HourglassIcon ([System.Drawing.Color]::Gold)
$script:iconRed    = New-HourglassIcon ([System.Drawing.Color]::Red)

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:startItem = New-Object System.Windows.Forms.ToolStripMenuItem("Iniciar / cambiar duracion...")
$script:stopItem  = New-Object System.Windows.Forms.ToolStripMenuItem("Detener")
$script:statusItem = New-Object System.Windows.Forms.ToolStripMenuItem("Estado: detenido")
$script:statusItem.Enabled = $false
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Salir")

[void]$menu.Items.Add($script:startItem)
[void]$menu.Items.Add($script:stopItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:statusItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)

$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon = $script:iconRed
$script:notifyIcon.Text = "MantenerActivo: detenido"
$script:notifyIcon.ContextMenuStrip = $menu
$script:notifyIcon.Visible = $true

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 1000
$script:timer.Add_Tick({ Update-Session })

$script:startItem.Add_Click({
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MantenerActivo - Duracion"
    $form.FormBorderStyle = "FixedDialog"
    $form.StartPosition = "CenterScreen"
    $form.ClientSize = New-Object System.Drawing.Size(340, 145)
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Duracion en minutos (bloques de 15):"
    $label.Location = New-Object System.Drawing.Point(12, 15)
    $label.Size = New-Object System.Drawing.Size(310, 25)

    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Location = New-Object System.Drawing.Point(15, 45)
    $numeric.Size = New-Object System.Drawing.Size(120, 25)
    $numeric.Minimum = 15
    $numeric.Maximum = 720
    $numeric.Increment = 15
    $numeric.Value = 60

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Iniciar"
    $ok.Location = New-Object System.Drawing.Point(145, 95)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancelar"
    $cancel.Location = New-Object System.Drawing.Point(230, 95)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($label, $numeric, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-Session ([int]$numeric.Value)
    }

    $form.Dispose()
})

$script:stopItem.Add_Click({ Stop-Session })

$exitItem.Add_Click({
    Stop-Session
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    $script:timer.Dispose()

    Clear-PowerRequest

    $script:iconGreen.Dispose()
    $script:iconYellow.Dispose()
    $script:iconRed.Dispose()

    [System.Windows.Forms.Application]::Exit()
})

$script:notifyIcon.Add_DoubleClick({
    $script:startItem.PerformClick()
})

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    if ($script:running) {
        Stop-Session
    }
    else {
        Clear-PowerRequest
    }

    if ($script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
}
