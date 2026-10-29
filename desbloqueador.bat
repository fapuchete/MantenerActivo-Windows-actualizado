
@echo off
cd /d "%~dp0"

if not exist "%~dp0MantenerActivo.ps1" (
    echo ERROR: No se encuentra MantenerActivo.ps1
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0MantenerActivo.ps1"

echo.
echo El programa ha terminado. Revisa los mensajes anteriores.
pause
