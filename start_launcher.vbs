Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
exeName = "MouseLauncher.exe"
exePath = scriptDir & exeName

' Copy pythonw.exe if not exists
If Not fso.FileExists(exePath) Then
    pythonPath = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python314\pythonw.exe")
    If Not fso.FileExists(pythonPath) Then
        ' Try to find via where command
        Set exec = WshShell.Exec("cmd /c where pythonw.exe")
        pythonPath = Trim(exec.StdOut.ReadLine())
    End If
    If fso.FileExists(pythonPath) Then
        fso.CopyFile pythonPath, exePath
    End If
End If

' Kill existing MouseLauncher only
WshShell.Run "taskkill /F /IM " & exeName, 0, True
WScript.Sleep 500

' Start launcher
WshShell.Run """" & exePath & """ """ & scriptDir & "launcher.pyw""", 0, False
