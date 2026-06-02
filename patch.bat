@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

:: GitCracken Patcher
:: Usage: patch.bat [feature] [asar_path]
::   feature   = pro (default), standalone, selfhosted, individual
::   asar_path = optional path to app.asar

set "FEATURE=%~1"
if "%FEATURE%"=="" set "FEATURE=pro"

set "ASAR=%~2"

set "ROOT=%~dp0"
set "PKG=%ROOT:~0,-1%"
set "LOG=%ROOT%patch.log"

:: Truncate log from previous run
type nul > "%LOG%"

echo ============================================================ | tee -a "%LOG%"
echo  GitCracken Patcher                                          | tee -a "%LOG%"
echo  Feature : %FEATURE%                                         | tee -a "%LOG%"
echo  Log     : %LOG%                                             | tee -a "%LOG%"
echo ============================================================ | tee -a "%LOG%"
echo. | tee -a "%LOG%"

:: ── Check Node.js ────────────────────────────────────────────────────────────
echo =^> Checking prerequisites | tee -a "%LOG%"
node --version > nul 2>&1
if errorlevel 1 (
    echo   [!!] Node.js not found. Install from https://nodejs.org ^(v16 LTS or later^) | tee -a "%LOG%"
    goto :fail
)
for /f "delims=" %%v in ('node --version 2^>^&1') do (
    echo   [ok] Node.js %%v | tee -a "%LOG%"
)

:: ── Pick package manager ─────────────────────────────────────────────────────
set "PM=npm"
yarn --version > nul 2>&1
if not errorlevel 1 (
    set "PM=yarn"
    echo   [ok] Package manager: yarn | tee -a "%LOG%"
) else (
    echo   [ok] Package manager: npm ^(yarn not found, that is fine^) | tee -a "%LOG%"
)
echo. | tee -a "%LOG%"

:: ── Install dependencies ─────────────────────────────────────────────────────
echo =^> Installing dependencies | tee -a "%LOG%"
pushd "%PKG%"
if not exist "%PKG%" (
    echo   [!!] GitCracken folder not found at: %PKG% | tee -a "%LOG%"
    popd
    goto :fail
)

if "%PM%"=="yarn" (
    yarn install --frozen-lockfile 2>&1 | tee -a "%LOG%"
) else (
    npm install 2>&1 | tee -a "%LOG%"
)
if errorlevel 1 (
    echo   [!!] Dependency install failed | tee -a "%LOG%"
    popd
    goto :fail
)
echo   [ok] Dependencies installed | tee -a "%LOG%"
popd
echo. | tee -a "%LOG%"

:: ── Build TypeScript ─────────────────────────────────────────────────────────
echo =^> Building | tee -a "%LOG%"
pushd "%PKG%"
if "%PM%"=="yarn" (
    yarn build 2>&1 | tee -a "%LOG%"
) else (
    npm run build 2>&1 | tee -a "%LOG%"
)
if errorlevel 1 (
    echo   [!!] Build failed | tee -a "%LOG%"
    popd
    goto :fail
)
echo   [ok] Build complete | tee -a "%LOG%"
popd
echo. | tee -a "%LOG%"

:: ── Run patcher ──────────────────────────────────────────────────────────────
echo =^> Patching GitKraken ^(feature: %FEATURE%^) | tee -a "%LOG%"

set "SCRIPT=%PKG%\dist\bin\gitcracken.js"

if not exist "%SCRIPT%" (
    echo   [!!] Build output not found at: %SCRIPT% | tee -a "%LOG%"
    echo   [!!] Did the build step fail? | tee -a "%LOG%"
    goto :fail
)

if "%ASAR%"=="" (
    echo   --^> Auto-detecting GitKraken installation... | tee -a "%LOG%"
    node "%SCRIPT%" patcher -f %FEATURE% 2>&1 | tee -a "%LOG%"
) else (
    echo   --^> Using custom asar: %ASAR% | tee -a "%LOG%"
    node "%SCRIPT%" patcher -f %FEATURE% -a "%ASAR%" 2>&1 | tee -a "%LOG%"
)
if errorlevel 1 (
    echo   [!!] Patcher failed | tee -a "%LOG%"
    goto :fail
)

:: ── Done ─────────────────────────────────────────────────────────────────────
echo. | tee -a "%LOG%"
echo ============================================================ | tee -a "%LOG%"
echo  Done! Re-launch GitKraken and re-login to apply the license. | tee -a "%LOG%"
echo  Log saved to: %LOG% | tee -a "%LOG%"
echo ============================================================ | tee -a "%LOG%"
echo.
pause
exit /b 0

:fail
echo. | tee -a "%LOG%"
echo  FAILED. See log above or open: %LOG% | tee -a "%LOG%"
echo.
pause
exit /b 1
