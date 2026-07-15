@echo off
REM ============================================================================
REM relink.bat - Restore the TTS temp symlinks for the Global script & UI AND
REM              every ZHF_*.lua require()'d module.
REM
REM TTS rewrites the temp Global.-1.lua / Global.-1.xml on every game load and
REM can replace the symlinks with stale regular copies. When that happens,
REM Ctrl+Alt+S (Save & Play) publishes OLD code, because the plugin reads those
REM temp files while your edits go to the project files. Running this deletes the
REM temp copies and re-points them at the project source, so the next Save & Play
REM bundles the current code.
REM
REM TTS also DELETES the ZHF_*.lua module symlinks from the temp dir. When a
REM require()'d module is missing, the luabundle step fails and the push is
REM silently dropped - the game keeps running the OLD build (symptom: the
REM ActionVersionStamp never advances no matter how many times you Save & Play).
REM This script re-links all ZHF_*.lua modules too, so the bundle always resolves.
REM
REM Safe to run any time, including mid-game: the running game executes from
REM memory; these files are only read on push and written on load. It does NOT
REM reload the game (only Ctrl+Alt+S does that).
REM
REM Requires Windows Developer Mode (already enabled here) so mklink works
REM without admin.
REM ============================================================================
setlocal
set "TEMP_DIR=%LOCALAPPDATA%\Temp\TabletopSimulator\Tabletop Simulator Lua"
set "PROJ_DIR=%~dp0"

for %%F in (Global.-1.lua Global.-1.xml) do (
  if exist "%TEMP_DIR%\%%F" del /f /q "%TEMP_DIR%\%%F"
  mklink "%TEMP_DIR%\%%F" "%PROJ_DIR%%%F"
)

REM Re-link every require()'d ZHF_*.lua module (TTS wipes these from the temp dir).
for %%F in ("%PROJ_DIR%ZHF_*.lua") do (
  if exist "%TEMP_DIR%\%%~nxF" del /f /q "%TEMP_DIR%\%%~nxF"
  mklink "%TEMP_DIR%\%%~nxF" "%%~fF"
)
endlocal
