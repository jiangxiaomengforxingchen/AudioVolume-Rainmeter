@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   AudioVolume - Rainmeter skin installer
echo ==========================================
echo.

rem ---- locate the packaged skin (this file must sit next to the skin folder) ----
set "SRC=%~dp0skin\AudioVolume"
if not exist "%SRC%\AudioVolume.ini" (
  echo [ERROR] skin folder not found:
  echo         %SRC%
  echo         Keep install.bat in the same folder as "skin".
  pause
  exit /b 1
)

rem ---- locate the Rainmeter skins folder ----
set "SKINS=%USERPROFILE%\Documents\Rainmeter\Skins"
if defined RAINMETER_SKINPATH set "SKINS=%RAINMETER_SKINPATH%"

if not exist "%SKINS%" (
  echo [ERROR] Rainmeter skins folder not found:
  echo         %SKINS%
  echo         Install Rainmeter first: https://www.rainmeter.net
  pause
  exit /b 1
)

set "DEST=%SKINS%\AudioVolume"

echo   source : %SRC%
echo   target : %DEST%
echo.

if exist "%DEST%" (
  set /p CONFIRM=  Target exists. Overwrite? (level.txt / state.txt are kept) [Y/N]: 
  if /i not "!CONFIRM!"=="Y" (
    echo   cancelled.
    pause
    exit /b 0
  )
)

robocopy "%SRC%" "%DEST%" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo [ERROR] copy failed. Check permissions and try again.
  pause
  exit /b 1
)
echo   skin files copied.
echo.

rem ---- locate Rainmeter.exe ----
set "RM=C:\Program Files\Rainmeter\Rainmeter.exe"
if not exist "%RM%" for /f "tokens=2,*" %%A in (
  'reg query "HKLM\SOFTWARE\Rainmeter" /v InstallPath 2^>nul ^| find "InstallPath"'
) do set "RM=%%B\Rainmeter.exe"
if not exist "%RM%" set "RM=%ProgramFiles%\Rainmeter\Rainmeter.exe"

if exist "%RM%" (
  echo   asking Rainmeter to refresh and load the skin ...
  "%RM%" "!RefreshApp"
  timeout /t 3 /nobreak >nul
  "%RM%" "!ActivateConfig" "AudioVolume" "AudioVolume.ini"
  echo   done. If nothing shows up:
  echo     right-click the Rainmeter tray icon -^> Skins -^> AudioVolume
) else (
  echo  [NOTE] Rainmeter.exe not found. Refresh manually:
  echo         right-click the Rainmeter tray icon -^> Skins -^> AudioVolume -^> AudioVolume.ini
)

echo.
echo ==========================================
echo  installed
echo ==========================================
echo   left click the SPEAKER card : toggle day / night theme
echo   right click the skin         : sound settings / refresh
echo   stop the capture helper      : @Resources\bin\stop-helper.bat
echo.
pause
