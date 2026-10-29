# MantenerActivo.ps1
# Windows PowerShell 5.1
# Evita bloqueo y apagado de pantalla: PowerRequest + SetThreadExecutionState,
# simulacion de actividad (F15 / raton) con autodiagnostico, icono de bandeja.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("ActivoNative" -as [type])) {
    Add-Type -ReferencedAssemblies System -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

public static class ActivoNative {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr PowerCreateRequest(IntPtr context);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool PowerSetRequest(IntPtr request, int requestType);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool PowerClearRequest(IntPtr request, int requestType);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    static extern short GetKeyState(int nVirtKey);
    [DllImport("user32.dll")]
    static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")]
    static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    static IntPtr request = IntPtr.Zero;
    static IntPtr context = IntPtr.Zero;
    static IntPtr reasonText = IntPtr.Zero;

    // REASON_CONTEXT simple: Version=0, Flags=POWER_REQUEST_CONTEXT_SIMPLE_STRING(1), texto.
    public static bool PowerOn(string reason) {
        PowerOff();
        context = Marshal.AllocHGlobal(64);
        for (int i = 0; i < 64; i += 4) { Marshal.WriteInt32(context, i, 0); }
        reasonText = Marshal.StringToHGlobalUni(reason);
        Marshal.WriteInt32(context, 0, 0);
        Marshal.WriteInt32(context, 4, 1);
        Marshal.WriteIntPtr(context, 8, reasonText);
        IntPtr h = PowerCreateRequest(context);
        if (h == IntPtr.Zero || h == new IntPtr(-1)) { return false; }
        request = h;
        bool a = PowerSetRequest(request, 0); // PowerRequestDisplayRequired
        bool b = PowerSetRequest(request, 1); // PowerRequestSystemRequired
        return a && b;
    }

    public static bool PowerRefresh() {
        if (request == IntPtr.Zero) { return false; }
        bool a = PowerSetRequest(request, 0);
        bool b = PowerSetRequest(request, 1);
        return a && b;
    }

    public static void PowerOff() {
        if (request != IntPtr.Zero) {
            PowerClearRequest(request, 0);
            PowerClearRequest(request, 1);
            CloseHandle(request);
            request = IntPtr.Zero;
        }
        if (reasonText != IntPtr.Zero) { Marshal.FreeHGlobal(reasonText); reasonText = IntPtr.Zero; }
        if (context != IntPtr.Zero) { Marshal.FreeHGlobal(context); context = IntPtr.Zero; }
    }

    public static uint IdleMs() {
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref li)) { return 0; }
        return unchecked((uint)Environment.TickCount - li.dwTime);
    }

    public static void PressF15() {
        bool numBefore = (GetKeyState(0x90) & 1) != 0;
        keybd_event(0x7E, 0, 0, UIntPtr.Zero);
        keybd_event(0x7E, 0, 2, UIntPtr.Zero);
        Thread.Sleep(30);
        bool numAfter = (GetKeyState(0x90) & 1) != 0;
        if (numBefore != numAfter) {
            keybd_event(0x90, 0x45, 1, UIntPtr.Zero);
            keybd_event(0x90, 0x45, 3, UIntPtr.Zero);
        }
    }

    public static void MouseNudge() {
        POINT p;
        GetCursorPos(out p);
        mouse_event(1, 1, 0, 0, UIntPtr.Zero);
        mouse_event(1, -1, 0, 0, UIntPtr.Zero);
        SetCursorPos(p.X, p.Y);
    }
}

public static class SystemWatcher {
    static int events = 0;
    static bool started = false;

    public static void Start() {
        if (started) { return; }
        started = true;
        SystemEvents.PowerModeChanged += OnPower;
        SystemEvents.SessionSwitch += OnSession;
    }

    public static void Stop() {
        if (!started) { return; }
        started = false;
        SystemEvents.PowerModeChanged -= OnPower;
        SystemEvents.SessionSwitch -= OnSession;
    }

    static void OnPower(object sender, PowerModeChangedEventArgs e) {
        if (e.Mode == PowerModes.Resume) { Interlocked.Increment(ref events); }
    }

    static void OnSession(object sender, SessionSwitchEventArgs e) {
        if (e.Reason == SessionSwitchReason.SessionUnlock ||
            e.Reason == SessionSwitchReason.SessionLogon ||
            e.Reason == SessionSwitchReason.ConsoleConnect ||
            e.Reason == SessionSwitchReason.RemoteConnect) {
            Interlocked.Increment(ref events);
        }
    }

    public static int TakeEvents() { return Interlocked.Exchange(ref events, 0); }
}
"@
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Una sola instancia (tambien evita duplicados con el perro guardian).
$createdNew = $false
$script:mutex = [System.Threading.Mutex]::new($true, "Local\MantenerActivo_Tray", [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "MantenerActivo ya esta en ejecucion."
    exit 0
}

$script:ES_CONTINUOUS       = [uint32]2147483648
$script:ES_SYSTEM_REQUIRED  = [uint32]1
$script:ES_DISPLAY_REQUIRED = [uint32]2

$script:dataDir    = Join-Path $env:APPDATA "MantenerActivo"
$script:configFile = Join-Path $script:dataDir "config.json"
$script:stateFile  = Join-Path $script:dataDir "session.json"
$script:runKey     = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:runName    = "MantenerActivo"
if (-not (Test-Path $script:dataDir)) {
    New-Item -ItemType Directory -Path $script:dataDir | Out-Null
}

# Estado de la sesion.
$script:running = $false
$script:mode = 'minutes'            # minutes | until | process | indefinite
$script:endTime = [datetime]::MaxValue
$script:startTime = [datetime]::Now
$script:totalSeconds = 1.0
$script:procName = ''
$script:warned = $false
$script:tick = 0
$script:lastTickTime = [datetime]::Now
$script:lastPowerTime = [datetime]::MinValue
$script:lastSimTime = [datetime]::MinValue
$script:lastBattTime = [datetime]::MinValue
$script:lastConsoleMinute = -1
$script:counterLineActive = $false
$script:battLevel = 100
$script:balloonKind = ''
$script:lastNoInputWarn = [datetime]::MinValue
$script:curHandle = [IntPtr]::Zero

# Metodos de simulacion; rota solos si el autodiagnostico detecta que no sirven.
$script:methods = @('F15', 'Raton', 'Ambos')
$script:methodIdx = 0
$script:simFails = 0
$script:rotations = 0
$script:IdleThresholdMs = 20000

function Write-Log {
    param([string]$Level, [string]$Message)

    if ($script:counterLineActive) {
        Write-Host ""
        $script:counterLineActive = $false
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# ---------- Configuracion persistente ----------

function Get-AppConfig {
    $cfg = @{ mode = 'minutes'; minutes = 60; untilTime = '18:00'; procName = ''; smart = $true }
    if (Test-Path $script:configFile) {
        try {
            $json = Get-Content -Path $script:configFile -Raw | ConvertFrom-Json
            foreach ($key in @($cfg.Keys)) {
                if ($null -ne $json.$key) { $cfg[$key] = $json.$key }
            }
        }
        catch { }
    }
    return $cfg
}

function Save-AppConfig {
    try {
        $script:config | ConvertTo-Json | Set-Content -Path $script:configFile -Encoding UTF8
    }
    catch {
        Write-Log "ERROR" "No se pudo guardar la configuracion: $($_.Exception.Message)"
    }
}

function Save-State {
    try {
        @{
            mode  = $script:mode
            end   = $script:endTime.ToString('o')
            total = $script:totalSeconds
            proc  = $script:procName
        } | ConvertTo-Json | Set-Content -Path $script:stateFile -Encoding UTF8
    }
    catch { }
}

function Clear-State {
    Remove-Item -Path $script:stateFile -Force -ErrorAction SilentlyContinue
}

# ---------- Inicio con Windows ----------

function Get-Autostart {
    $prop = Get-ItemProperty -Path $script:runKey -Name $script:runName -ErrorAction SilentlyContinue
    return ($null -ne $prop)
}

function Set-Autostart([bool]$Enable) {
    if ($Enable) {
        $vbs = Join-Path $PSScriptRoot "Iniciar-MantenerActivo.vbs"
        if (-not (Test-Path $vbs)) {
            Write-Log "ERROR" "No se encuentra Iniciar-MantenerActivo.vbs"
            return
        }
        Set-ItemProperty -Path $script:runKey -Name $script:runName -Value "wscript.exe `"$vbs`""
        Write-Log "OK" "Inicio con Windows activado"
    }
    else {
        Remove-ItemProperty -Path $script:runKey -Name $script:runName -ErrorAction SilentlyContinue
        Write-Log "OK" "Inicio con Windows desactivado"
    }
}

# ---------- Icono de bandeja ----------

# Reloj de arena con "respiracion" (Alpha), barra de progreso o marquesina.
function New-StateIcon {
    param(
        [System.Drawing.Color]$Color,
        [int]$Alpha = 255,
        [string]$Bar = 'none',
        [double]$Fraction = 0,
        [int]$Tick = 0
    )

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $soft = [System.Drawing.Color]::FromArgb($Alpha, $Color.R, $Color.G, $Color.B)
    $pen = New-Object System.Drawing.Pen($soft, 3)
    $brush = New-Object System.Drawing.SolidBrush($soft)
    $solid = New-Object System.Drawing.SolidBrush($Color)
    $track = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 128, 128, 128))

    $g.DrawLine($pen, 8, 4, 24, 4)
    $g.DrawLine($pen, 8, 26, 24, 26)
    $g.DrawLine($pen, 9, 5, 23, 25)
    $g.DrawLine($pen, 23, 5, 9, 25)
    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,8),
        [System.Drawing.Point]::new(21,8),
        [System.Drawing.Point]::new(16,13)
    ))
    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,22),
        [System.Drawing.Point]::new(21,22),
        [System.Drawing.Point]::new(16,17)
    ))

    if ($Bar -ne 'none') {
        $g.FillRectangle($track, 2, 29, 28, 3)
        if ($Bar -eq 'bar') {
            $w = [int][Math]::Round(28 * $Fraction)
            if ($w -gt 0) { $g.FillRectangle($solid, 2, 29, $w, 3) }
        }
        else {
            $x = 2 + (($Tick * 3) % 21)
            $g.FillRectangle($solid, $x, 29, 7, 3)
        }
    }

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)

    $g.Dispose(); $pen.Dispose(); $brush.Dispose(); $solid.Dispose(); $track.Dispose(); $bmp.Dispose()

    return @{ Icon = $icon; Handle = $hIcon }
}

function Set-TrayIcon {
    param($Spec, [string]$Tip)

    $old = $script:curHandle
    $script:notifyIcon.Icon = $Spec.Icon
    $script:curHandle = $Spec.Handle
    if ($old -ne [IntPtr]::Zero) { [void][ActivoNative]::DestroyIcon($old) }

    $script:notifyIcon.Text = $Tip.Substring(0, [Math]::Min(63, $Tip.Length))
}

function Show-Balloon {
    param([string]$Title, [string]$Text, [string]$Kind = 'info', [string]$Icon = 'Info')

    $script:balloonKind = $Kind
    $script:notifyIcon.BalloonTipTitle = $Title
    $script:notifyIcon.BalloonTipText = $Text
    $script:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::$Icon
    $script:notifyIcon.ShowBalloonTip(10000)
}

# ---------- Energia ----------

function Set-PowerRequest {
    param([switch]$Rebuild)

    $ok = $false
    if (-not $Rebuild) { $ok = [ActivoNative]::PowerRefresh() }
    if (-not $ok) { $ok = [ActivoNative]::PowerOn("MantenerActivo: mantener equipo y pantalla activos") }

    $flags = [uint32]($script:ES_CONTINUOUS -bor $script:ES_SYSTEM_REQUIRED -bor $script:ES_DISPLAY_REQUIRED)
    $legacy = [ActivoNative]::SetThreadExecutionState($flags)

    $script:lastPowerTime = [datetime]::Now
    if (-not $ok -and $legacy -eq 0) {
        Write-Log "ERROR" "No se pudo solicitar energia (PowerRequest ni SetThreadExecutionState)"
    }
    elseif ($Rebuild) {
        Write-Log "OK" "Solicitud de energia activa (PowerRequest=$ok, ExecutionState=$($legacy -ne 0))"
    }
}

function Clear-PowerRequest {
    try {
        [ActivoNative]::PowerOff()
        [void][ActivoNative]::SetThreadExecutionState($script:ES_CONTINUOUS)
        Write-Log "OK" "Solicitud de energia liberada"
    }
    catch {
        Write-Log "ERROR" "No se pudo liberar energia: $($_.Exception.Message)"
    }
}

# ---------- Simulacion de actividad con autodiagnostico ----------

function Invoke-Simulation {
    $method = $script:methods[$script:methodIdx]
    try {
        switch ($method) {
            'F15'   { [ActivoNative]::PressF15() }
            'Raton' { [ActivoNative]::MouseNudge() }
            'Ambos' { [ActivoNative]::PressF15(); [ActivoNative]::MouseNudge() }
        }
        Start-Sleep -Milliseconds 60
        $script:lastSimTime = [datetime]::Now

        # Si la entrada fue aceptada, el tiempo de inactividad vuelve a ~0.
        if ([ActivoNative]::IdleMs() -lt 2000) {
            $script:simFails = 0
            $script:rotations = 0
            Write-Log "EVENTO" "Actividad simulada ($method)"
        }
        else {
            $script:simFails++
            Write-Log "AVISO" "La actividad simulada ($method) no reinicio la inactividad ($($script:simFails)/2)"
            if ($script:simFails -ge 2) { Switch-Method }
        }
    }
    catch {
        Write-Log "ERROR" "Fallo la simulacion ($method): $($_.Exception.Message)"
        Switch-Method
    }
}

function Switch-Method {
    $script:simFails = 0
    $script:rotations++
    $script:methodIdx = ($script:methodIdx + 1) % $script:methods.Count
    Write-Log "INFO" "Cambiando metodo de simulacion a: $($script:methods[$script:methodIdx])"
    Update-MenuState

    if ($script:rotations -ge $script:methods.Count) {
        $script:rotations = 0
        if (([datetime]::Now - $script:lastNoInputWarn).TotalMinutes -ge 10) {
            $script:lastNoInputWarn = [datetime]::Now
            Show-Balloon "Ayuda, este equipo no despierta" "Probe F15, raton y ambos, y nada. Puede ser sesion bloqueada o una politica de TI. Ojo con tu agente." 'warn' 'Warning'
        }
    }
}

# ---------- Bateria ----------

function Test-Battery {
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    if ($ps.BatteryChargeStatus.ToString() -match 'NoSystemBattery') { return }

    $pct = [int]($ps.BatteryLifePercent * 100)
    if ($pct -gt 100) { return }

    if ($ps.PowerLineStatus.ToString() -eq 'Offline') {
        if ($pct -le 10 -and $script:battLevel -gt 10) {
            $script:battLevel = 10
            Show-Balloon "Bateria critica ($pct%)" "Enchufa el cargador YA, no dejes a tu agente a medias. Sigo con la pantalla encendida y eso gasta bateria." 'batt' 'Error'
        }
        elseif ($pct -le 20 -and $script:battLevel -gt 20) {
            $script:battLevel = 20
            Show-Balloon "Bateria baja ($pct%)" "Busca el cargador antes de que se apague tu agente. Sigo forzando la pantalla encendida, y eso cuesta bateria." 'batt' 'Warning'
        }
    }
    elseif ($script:battLevel -lt 100) {
        $script:battLevel = 100
    }
}

# ---------- Procesos ----------

function Get-ProcName([string]$Text) {
    $name = ($Text -split ' \| ')[0].Trim()
    return ($name -replace '\.exe$', '')
}

function Test-ProcessRunning([string]$Name) {
    if (-not $Name) { return $false }
    return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Get-ProcessChoices {
    $list = @()
    try {
        $list = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle } |
            Sort-Object ProcessName -Unique |
            ForEach-Object {
                $title = $_.MainWindowTitle
                if ($title.Length -gt 40) { $title = $title.Substring(0, 40) }
                "{0} | {1}" -f $_.ProcessName, $title
            }
    }
    catch { }
    return @($list)
}

# ---------- Sesion ----------

function Update-MenuState {
    $timed = ($script:mode -eq 'minutes' -or $script:mode -eq 'until')
    $script:stopItem.Enabled = $script:running
    $script:addItem.Enabled = ($script:running -and $timed)

    if (-not $script:running) {
        $script:statusItem.Text = "Estado: descansando"
        return
    }

    $method = $script:methods[$script:methodIdx]
    switch ($script:mode) {
        'process'    { $script:statusItem.Text = "Vigilando mientras corra: $($script:procName) [$method]" }
        'indefinite' { $script:statusItem.Text = "Vigilando sin hora de fin [$method]" }
        default      { $script:statusItem.Text = "Vigilando hasta las $($script:endTime.ToString('HH:mm')) [$method]" }
    }
}

function Stop-Session {
    if (-not $script:running) { return }

    $script:running = $false
    $script:timer.Stop()

    Write-Log "INFO" "Deteniendo mecanismos de actividad"
    Clear-PowerRequest
    Clear-State

    $script:lastConsoleMinute = -1
    $script:counterLineActive = $false

    Set-TrayIcon (New-StateIcon -Color ([System.Drawing.Color]::Red)) "Descansando: la pantalla hace lo que quiere"
    Update-MenuState
    Write-Log "INFO" "Sesion detenida"
}

function Start-Session {
    param(
        [string]$Mode,
        [datetime]$End = [datetime]::MaxValue,
        [string]$ProcName = '',
        [double]$Total = 0
    )

    if ($script:running) { Stop-Session }

    $now = [datetime]::Now
    $script:mode = $Mode
    $script:endTime = $End
    $script:procName = $ProcName
    $script:startTime = $now
    $script:warned = $false
    $script:tick = 0
    $script:lastTickTime = $now
    $script:lastSimTime = [datetime]::MinValue
    $script:lastBattTime = [datetime]::MinValue
    $script:lastConsoleMinute = -1
    $script:battLevel = 100
    $script:simFails = 0
    $script:rotations = 0

    if ($Mode -eq 'minutes' -or $Mode -eq 'until') {
        $script:totalSeconds = if ($Total -gt 0) { $Total } else { [Math]::Max(1.0, ($End - $now).TotalSeconds) }
    }

    Write-Log "INFO" "Iniciando sesion: modo $Mode"
    Set-PowerRequest -Rebuild

    $script:running = $true
    Save-State
    Update-MenuState
    Write-Log "INFO" "Simulacion de actividad: $($script:methods[$script:methodIdx]) (solo con inactividad: $($script:config.smart))"

    [void][SystemWatcher]::TakeEvents()
    $script:timer.Start()
    Update-Session
}

function Add-Time([int]$Minutes) {
    if (-not $script:running) { return }
    if ($script:mode -ne 'minutes' -and $script:mode -ne 'until') { return }

    $script:endTime = $script:endTime.AddMinutes($Minutes)
    $script:totalSeconds += $Minutes * 60
    $script:warned = $false
    Save-State
    Update-MenuState
    Write-Log "INFO" "Se agregaron $Minutes minutos"
    Show-Balloon "Prorroga concedida" "$Minutes minutos mas de pantalla encendida. Nuevo fin: $($script:endTime.ToString('HH:mm')). Sigue con tus flexiones." 'info'
}

function Restore-SavedSession {
    if (-not (Test-Path $script:stateFile)) { return }

    try {
        $s = Get-Content -Path $script:stateFile -Raw | ConvertFrom-Json
        $mode = [string]$s.mode
        $proc = [string]$s.proc
        $total = [double]$s.total

        if ($s.end -is [datetime]) { $end = $s.end }
        else {
            $end = [datetime]::Parse(
                [string]$s.end,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }

        $valid = $false
        switch ($mode) {
            'process'    { $valid = (Test-ProcessRunning $proc) }
            'indefinite' { $valid = $true }
            { $_ -eq 'minutes' -or $_ -eq 'until' } { $valid = ($end -gt [datetime]::Now) }
        }

        if ($valid) {
            Write-Log "INFO" "Reanudando sesion guardada ($mode)"
            Start-Session -Mode $mode -End $end -ProcName $proc -Total $total
            Show-Balloon "Aqui seguimos" "Retome la vigilancia donde la dejamos. La pantalla sigue encendida." 'info'
        }
        else {
            Clear-State
        }
    }
    catch {
        Write-Log "ERROR" "No se pudo reanudar la sesion: $($_.Exception.Message)"
        Clear-State
    }
}

function Update-Session {
    if (-not $script:running) { return }

    $now = [datetime]::Now
    $script:tick++

    # Reanudacion tras suspension / desbloqueo: reconstruir la solicitud de energia.
    $gap = ($now - $script:lastTickTime).TotalSeconds
    $script:lastTickTime = $now
    $watchEvents = [SystemWatcher]::TakeEvents()
    if ($gap -gt 15 -or $watchEvents -gt 0) {
        Write-Log "INFO" "Reanudacion o desbloqueo detectado: se reactiva la sesion"
        Set-PowerRequest -Rebuild
        $script:lastSimTime = [datetime]::MinValue
        if ($gap -gt 15) {
            Show-Balloon "Buenos dias, equipo" "Se desperto de la siesta y ya volvi a vigilar la pantalla." 'info'
        }
    }

    $timed = ($script:mode -eq 'minutes' -or $script:mode -eq 'until')
    $remaining = [timespan]::Zero

    if ($timed) {
        $remaining = $script:endTime - $now
        if ($remaining.TotalSeconds -le 0) {
            Write-Log "INFO" "Tiempo finalizado"
            Stop-Session
            Show-Balloon "Se acabo el tiempo" "Listo, la pantalla vuelve a su rutina normal. Gracias por la compania." 'end'
            return
        }

        if (-not $script:warned -and $remaining.TotalSeconds -le 300) {
            $script:warned = $true
            Show-Balloon "Quedan 5 minutos" "Si tu agente aun no termina, haz clic aqui y le doy 30 minutos mas." 'warn' 'Warning'
        }
    }
    elseif ($script:mode -eq 'process' -and ($script:tick % 5) -eq 0) {
        if (-not (Test-ProcessRunning $script:procName)) {
            $name = $script:procName
            Write-Log "INFO" "El programa $name se cerro"
            Stop-Session
            Show-Balloon "$name termino" "Ya puedes dejar de rezar: la pantalla vuelve a su rutina normal." 'end'
            return
        }
    }

    # Reafirmar la solicitud de energia cada 30 s.
    if (($now - $script:lastPowerTime).TotalSeconds -ge 30) {
        Set-PowerRequest
    }

    # Simular actividad: solo si hay inactividad real (modo inteligente) o cada 30 s.
    $sinceSim = ($now - $script:lastSimTime).TotalSeconds
    if ($script:config.smart) {
        if ([ActivoNative]::IdleMs() -ge $script:IdleThresholdMs -and $sinceSim -ge 5) { Invoke-Simulation }
    }
    elseif ($sinceSim -ge 30) {
        Invoke-Simulation
    }

    if (($now - $script:lastBattTime).TotalSeconds -ge 30) {
        $script:lastBattTime = $now
        Test-Battery
    }

    # Contador en consola: una actualizacion por minuto.
    $span = if ($timed) { $remaining } else { $now - $script:startTime }
    $text = "{0:00}:{1:00}:{2:00}" -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    $minuteMarker = [int][Math]::Floor($span.TotalSeconds / 60)

    if ($minuteMarker -ne $script:lastConsoleMinute) {
        if ($script:counterLineActive) { Write-Host "`r" -NoNewline }
        $label = if ($timed) { "Tiempo restante" } else { "Tiempo activo" }
        Write-Host -NoNewline "[$(Get-Date -Format 'HH:mm:ss')] ${label}: $text"
        $script:counterLineActive = $true
        $script:lastConsoleMinute = $minuteMarker
    }

    # Icono: respira, y muestra progreso (o marquesina si no hay fin fijo).
    $alpha = @(255, 225, 195, 225)[$script:tick % 4]
    if ($timed) {
        if ($remaining.TotalMinutes -le 5) { $color = [System.Drawing.Color]::Gold; $name = "AMARILLO" }
        else { $color = [System.Drawing.Color]::LimeGreen; $name = "VERDE" }
        $fraction = [Math]::Max(0.0, [Math]::Min(1.0, $remaining.TotalSeconds / $script:totalSeconds))
        $spec = New-StateIcon -Color $color -Alpha $alpha -Bar 'bar' -Fraction $fraction
        Set-TrayIcon $spec "$name - Restante: $text"
    }
    else {
        $spec = New-StateIcon -Color ([System.Drawing.Color]::DodgerBlue) -Alpha $alpha -Bar 'marquee' -Tick $script:tick
        $desc = if ($script:mode -eq 'process') { "Mientras corra: $($script:procName)" } else { "Indefinido" }
        Set-TrayIcon $spec "$desc ($text)"
    }
}

# ---------- Dialogo de inicio ----------

function Update-DialogState {
    $d = $script:dlg
    $d.numeric.Enabled = $d.rbMinutes.Checked
    $d.picker.Enabled = $d.rbUntil.Checked
    $d.combo.Enabled = $d.rbProcess.Checked
    $d.refresh.Enabled = $d.rbProcess.Checked
}

function Update-ProcessCombo {
    $d = $script:dlg
    $current = $d.combo.Text
    $d.combo.Items.Clear()
    [void]$d.combo.Items.AddRange([object[]](Get-ProcessChoices))
    $d.combo.Text = $current
}

function Show-StartDialog {
    $d = @{}
    $script:dlg = $d

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MantenerActivo - Cuanto tiempo rezamos?"
    $form.FormBorderStyle = "FixedDialog"
    $form.StartPosition = "CenterScreen"
    $form.ClientSize = New-Object System.Drawing.Size(410, 255)
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $d.form = $form

    $d.rbMinutes = New-Object System.Windows.Forms.RadioButton
    $d.rbMinutes.Text = "Por minutos (bloques de 15), a hacer flexiones:"
    $d.rbMinutes.Location = New-Object System.Drawing.Point(15, 15)
    $d.rbMinutes.Size = New-Object System.Drawing.Size(370, 22)

    $d.numeric = New-Object System.Windows.Forms.NumericUpDown
    $d.numeric.Location = New-Object System.Drawing.Point(38, 40)
    $d.numeric.Size = New-Object System.Drawing.Size(100, 25)
    $d.numeric.Minimum = 15
    $d.numeric.Maximum = 720
    $d.numeric.Increment = 15
    $d.numeric.Value = [Math]::Min(720, [Math]::Max(15, [int]$script:config.minutes))

    $d.rbUntil = New-Object System.Windows.Forms.RadioButton
    $d.rbUntil.Text = "Hasta una hora (si ya paso, sera manana):"
    $d.rbUntil.Location = New-Object System.Drawing.Point(15, 78)
    $d.rbUntil.Size = New-Object System.Drawing.Size(370, 22)

    $d.picker = New-Object System.Windows.Forms.DateTimePicker
    $d.picker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $d.picker.CustomFormat = "HH:mm"
    $d.picker.ShowUpDown = $true
    $d.picker.Location = New-Object System.Drawing.Point(38, 103)
    $d.picker.Size = New-Object System.Drawing.Size(100, 25)
    try {
        $d.picker.Value = [datetime]::ParseExact(
            [string]$script:config.untilTime, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch { }

    $d.rbProcess = New-Object System.Windows.Forms.RadioButton
    $d.rbProcess.Text = "Mientras trabaje tu agente favorito (elige o escribe):"
    $d.rbProcess.Location = New-Object System.Drawing.Point(15, 141)
    $d.rbProcess.Size = New-Object System.Drawing.Size(380, 22)

    $d.combo = New-Object System.Windows.Forms.ComboBox
    $d.combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $d.combo.Location = New-Object System.Drawing.Point(38, 166)
    $d.combo.Size = New-Object System.Drawing.Size(260, 25)
    $d.combo.Text = [string]$script:config.procName
    [void]$d.combo.Items.AddRange([object[]](Get-ProcessChoices))

    $d.refresh = New-Object System.Windows.Forms.Button
    $d.refresh.Text = "Actualizar"
    $d.refresh.Location = New-Object System.Drawing.Point(305, 164)
    $d.refresh.Size = New-Object System.Drawing.Size(85, 27)
    $d.refresh.Add_Click({ Update-ProcessCombo })

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Vigilar"
    $ok.Location = New-Object System.Drawing.Point(225, 215)
    $ok.Add_Click({
        $dd = $script:dlg
        if ($dd.rbProcess.Checked) {
            $name = Get-ProcName $dd.combo.Text
            if (-not $name) {
                [void][System.Windows.Forms.MessageBox]::Show("Dime a quien vigilo: elige un programa o escribe su nombre.", "MantenerActivo")
                return
            }
            if (-not (Test-ProcessRunning $name)) {
                [void][System.Windows.Forms.MessageBox]::Show("'$name' todavia no esta corriendo. Abrelo primero y vuelve a intentarlo.", "MantenerActivo")
                return
            }
        }
        $dd.form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancelar"
    $cancel.Location = New-Object System.Drawing.Point(310, 215)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@(
        $d.rbMinutes, $d.numeric, $d.rbUntil, $d.picker,
        $d.rbProcess, $d.combo, $d.refresh, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    switch ([string]$script:config.mode) {
        'until'   { $d.rbUntil.Checked = $true }
        'process' { $d.rbProcess.Checked = $true }
        default   { $d.rbMinutes.Checked = $true }
    }
    $d.rbMinutes.Add_CheckedChanged({ Update-DialogState })
    $d.rbUntil.Add_CheckedChanged({ Update-DialogState })
    $d.rbProcess.Add_CheckedChanged({ Update-DialogState })
    Update-DialogState

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($d.rbProcess.Checked) {
            $name = Get-ProcName $d.combo.Text
            $script:config.mode = 'process'
            $script:config.procName = $name
            Save-AppConfig
            Start-Session -Mode 'process' -ProcName $name
        }
        elseif ($d.rbUntil.Checked) {
            $t = $d.picker.Value
            $target = [datetime]::Today.AddHours($t.Hour).AddMinutes($t.Minute)
            if ($target -le [datetime]::Now.AddMinutes(1)) { $target = $target.AddDays(1) }
            $script:config.mode = 'until'
            $script:config.untilTime = $t.ToString('HH:mm')
            Save-AppConfig
            Start-Session -Mode 'until' -End $target
        }
        else {
            $minutes = [int]$d.numeric.Value
            $script:config.mode = 'minutes'
            $script:config.minutes = $minutes
            Save-AppConfig
            Start-Session -Mode 'minutes' -End ([datetime]::Now.AddMinutes($minutes))
        }
    }

    $form.Dispose()
}

# ---------- Arranque ----------

Write-Host ""
Write-Host "========================================"
Write-Host "       MANTENER ACTIVO - WINDOWS"
Write-Host "  Pantalla encendida mientras tu agente trabaja"
Write-Host "========================================"
Write-Log "INFO" "Aplicacion iniciada"

$script:config = Get-AppConfig

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:statusItem = New-Object System.Windows.Forms.ToolStripMenuItem("Estado: descansando")
$script:statusItem.Enabled = $false

$quickItem = New-Object System.Windows.Forms.ToolStripMenuItem("Inicio rapido")
foreach ($preset in @(
        @("30 minutos (unas flexiones)", 30), @("1 hora (un buen rezo)", 60), @("2 horas", 120),
        @("4 horas (medio dia de fe)", 240), @("8 horas (jornada completa)", 480),
        @("Indefinido (hasta que el agente termine)", 0))) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($preset[0])
    $item.Tag = $preset[1]
    $item.Add_Click({
        $minutes = [int]$this.Tag
        if ($minutes -eq 0) { Start-Session -Mode 'indefinite' }
        else { Start-Session -Mode 'minutes' -End ([datetime]::Now.AddMinutes($minutes)) }
    })
    [void]$quickItem.DropDownItems.Add($item)
}

$script:startItem = New-Object System.Windows.Forms.ToolStripMenuItem("Personalizado...")
$script:addItem = New-Object System.Windows.Forms.ToolStripMenuItem("Dame 30 minutos mas")
$script:stopItem = New-Object System.Windows.Forms.ToolStripMenuItem("Dejar descansar la pantalla")

$smartItem = New-Object System.Windows.Forms.ToolStripMenuItem("Solo moverme si no estas usando el equipo")
$smartItem.CheckOnClick = $true
$smartItem.Checked = [bool]$script:config.smart

$autoItem = New-Object System.Windows.Forms.ToolStripMenuItem("Arrancar con Windows (para que no se te olvide)")
$autoItem.CheckOnClick = $true
$autoItem.Checked = (Get-Autostart)

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Salir (la pantalla vuelve a su vida)")

[void]$menu.Items.Add($script:statusItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($quickItem)
[void]$menu.Items.Add($script:startItem)
[void]$menu.Items.Add($script:addItem)
[void]$menu.Items.Add($script:stopItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($smartItem)
[void]$menu.Items.Add($autoItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)

$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.ContextMenuStrip = $menu
$script:notifyIcon.Visible = $true
Set-TrayIcon (New-StateIcon -Color ([System.Drawing.Color]::Red)) "Descansando: la pantalla hace lo que quiere"
Update-MenuState

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 1000
$script:timer.Add_Tick({
    try { Update-Session }
    catch { Write-Log "ERROR" "Error en el ciclo: $($_.Exception.Message)" }
})

$script:startItem.Add_Click({ Show-StartDialog })
$script:addItem.Add_Click({ Add-Time 30 })
$script:stopItem.Add_Click({ Stop-Session })
$smartItem.Add_Click({
    $script:config.smart = $this.Checked
    Save-AppConfig
})
$autoItem.Add_Click({ Set-Autostart $this.Checked })

$script:notifyIcon.Add_BalloonTipClicked({
    if ($script:balloonKind -eq 'warn' -and $script:running) { Add-Time 30 }
})
$script:notifyIcon.Add_DoubleClick({ Show-StartDialog })

$exitItem.Add_Click({
    Stop-Session
    Clear-State
    [System.Windows.Forms.Application]::Exit()
})

[SystemWatcher]::Start()

try {
    Restore-SavedSession
    [System.Windows.Forms.Application]::Run()
}
finally {
    # No se borra session.json aqui: si el cierre fue un fallo, el perro guardian reanuda la sesion.
    $script:timer.Stop()
    [SystemWatcher]::Stop()
    Clear-PowerRequest

    if ($script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    if ($script:curHandle -ne [IntPtr]::Zero) { [void][ActivoNative]::DestroyIcon($script:curHandle) }

    try { $script:mutex.ReleaseMutex() } catch { }
    $script:mutex.Dispose()
}

exit 0
