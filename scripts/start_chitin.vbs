' Start CHITIN without a console window - same pattern as start_screensaver.vbs:
' a named pythonw copy (CHITIN.exe), one instance at a time.
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
exeName = "CHITIN.exe"
exePath = scriptDir & exeName
chitinDir = "C:\Users\rmanov\algorithmic-arts\CHITIN\"

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

' Kill existing CHITIN only
WshShell.Run "taskkill /F /IM " & exeName, 0, True
WScript.Sleep 500

' Start CHITIN in a normal window (pythonw has no console; style 0 could hide the Tk window)
WshShell.CurrentDirectory = chitinDir
WshShell.Run """" & exePath & """ """ & chitinDir & "battle_evolution.py"" --max-agents 60", 1, False
