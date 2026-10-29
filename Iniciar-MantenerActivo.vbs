Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
scriptPath = FSO.BuildPath(FSO.GetParentFolderName(WScript.ScriptFullName), "MantenerActivo.ps1")
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """"
WshShell.Run command, 0, False
