@echo off
cd /d "%~dp0"
echo AudioLevelHelper running - close this window to stop it.
AudioLevelHelper.exe --out "%~dp0level.txt" --interval 80 --decay 0.86
