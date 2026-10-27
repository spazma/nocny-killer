Option Explicit

Dim objShell, fso, scriptDir, ps1Path, cmd
Set objShell = CreateObject("Wscript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
ps1Path = scriptDir & "nk-script.ps1"

If Not fso.FileExists(ps1Path) Then
    MsgBox "Brak pliku: " & ps1Path, vbExclamation, "Błąd"
    WScript.Quit
End If

cmd = """C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1Path & """"
objShell.Run cmd, 0, False