' Perro guardian: relanza MantenerActivo.ps1 si termina de forma anormal.
' Una salida normal (menu Salir = codigo 0) no lo relanza.
Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
scriptPath = FSO.BuildPath(FSO.GetParentFolderName(WScript.ScriptFullName), "MantenerActivo.ps1")
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """"

crashes = 0
Do
    startedAt = Now
    rc = WshShell.Run(command, 0, True)
    If rc = 0 Then Exit Do

    ' Si aguanto mas de 5 minutos, no cuenta como fallo repetido.
    If DateDiff("s", startedAt, Now) > 300 Then
        crashes = 0
    Else
        crashes = crashes + 1
    End If

    ' Evita un bucle infinito si el script falla al arrancar.
    If crashes >= 5 Then Exit Do
    WScript.Sleep 5000
Loop
