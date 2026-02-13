Option Explicit

Dim shell, fso, scriptDir, baseName, batPath, cmd, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
baseName = fso.GetBaseName(WScript.ScriptName)
batPath = fso.BuildPath(scriptDir, baseName & ".bat")

If Not fso.FileExists(batPath) Then
    WScript.Quit 2
End If

cmd = "cmd.exe /c " & QuoteArg(batPath)
For i = 0 To WScript.Arguments.Count - 1
    cmd = cmd & " " & QuoteArg(WScript.Arguments(i))
Next
cmd = cmd & " <nul"

shell.Run cmd, 0, False

Function QuoteArg(ByVal value)
    QuoteArg = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
