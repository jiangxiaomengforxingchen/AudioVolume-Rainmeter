Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
exe  = here & "\AudioLevelHelper.exe"
out  = here & "\level.txt"
If Not fso.FileExists(exe) Then WScript.Quit
sh.Run """" & exe & """ --out """ & out & """ --interval 80 --decay 0.86", 0, False
