@echo off
REM ============================================================================
REM relink.bat - Restore the TTS temp symlinks for the Global script & UI.
REM
REM TTS rewrites the temp Global.-1.lua / Global.-1.xml on every game load and
REM can replace the symlinks with stale regular copies. When that happens,
REM Ctrl+Alt+S (Save & Play) publishes OLD code, because the plugin reads those
REM temp files while your edits go to the project files. Running this deletes the
REM temp copies and re-points them at the project source, so the next Save & Play
REM bundles the current code.
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
endlocal
