# Genera MantenerActivo.ico (reloj de arena verde, igual al de la bandeja)
# y un acceso directo "desbloqueador.lnk" que usa ese icono.
# Un .bat no puede tener icono propio; el acceso directo si.

Add-Type -AssemblyName System.Drawing

$dir = $PSScriptRoot
$icoPath = Join-Path $dir "MantenerActivo.ico"
$lnkPath = Join-Path $dir "desbloqueador.lnk"
$batPath = Join-Path $dir "desbloqueador.bat"

function New-HourglassPng([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.ScaleTransform($Size / 32.0, $Size / 32.0)
    $g.Clear([System.Drawing.Color]::Transparent)

    $color = [System.Drawing.Color]::LimeGreen
    $pen = New-Object System.Drawing.Pen($color, 3)
    $brush = New-Object System.Drawing.SolidBrush($color)

    $g.DrawLine($pen, 8, 5, 24, 5)
    $g.DrawLine($pen, 8, 27, 24, 27)
    $g.DrawLine($pen, 9, 6, 23, 26)
    $g.DrawLine($pen, 23, 6, 9, 26)
    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,9), [System.Drawing.Point]::new(21,9), [System.Drawing.Point]::new(16,14)))
    $g.FillPolygon($brush, [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11,23), [System.Drawing.Point]::new(21,23), [System.Drawing.Point]::new(16,18)))

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $g.Dispose(); $pen.Dispose(); $brush.Dispose(); $bmp.Dispose(); $ms.Dispose()
    return ,$bytes
}

$sizes = 16, 32, 48, 256
$pngs = foreach ($s in $sizes) { , (New-HourglassPng $s) }

$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $dimByte = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dimByte); $bw.Write([byte]$dimByte)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close(); $fs.Close()

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $batPath
$lnk.WorkingDirectory = $dir
$lnk.IconLocation = "$icoPath,0"
$lnk.Description = "MantenerActivo"
$lnk.Save()

Write-Host "Creados: $icoPath y $lnkPath"
