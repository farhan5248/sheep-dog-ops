@echo off
REM Wrapper around minikube_start.bat for machines that host services for the
REM whole LAN (e.g. windows-desktop running Nexus). Exposes the ingress port
REM on 0.0.0.0 via netsh portproxy so other machines on the LAN can reach it,
REM THEN hands off to the base script (which ends with a foreground
REM `minikube tunnel`).
REM
REM Why portproxy setup comes FIRST:
REM   minikube_start.bat ends with `minikube tunnel` as a foreground process,
REM   so anything after the `call` never runs. We configure exposure before
REM   the call.
REM
REM Why this is needed at all:
REM   `minikube tunnel` only binds to 127.0.0.1, so the minikube ingress is
REM   not reachable across the LAN by default. The portproxy forwards
REM   0.0.0.0:80 -> 127.0.0.1:80 on this host.
REM
REM Requirements:
REM   - Must be run as Administrator (portproxy + firewall rules are privileged)
REM   - Only run on machines that intentionally serve the LAN
REM
REM Usage:
REM   Run as admin: minikube_start_server.bat

REM Check for admin. fltmc.exe requires admin; it's a reliable probe.
fltmc >nul 2>&1
if errorlevel 1 (
    echo ERROR: this script must be run as Administrator.
    exit /b 1
)

echo === Configuring LAN exposure ===

echo Removing any existing portproxy rule on 0.0.0.0:80...
netsh interface portproxy delete v4tov4 listenport=80 listenaddress=0.0.0.0 >nul 2>&1

echo Adding portproxy: 0.0.0.0:80 -^> 127.0.0.1:80...
netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=127.0.0.1
if errorlevel 1 (
    echo ERROR: failed to add portproxy rule.
    exit /b 1
)

echo Ensuring firewall rule "Nexus ingress :80" allows inbound TCP/80...
netsh advfirewall firewall delete rule name="Nexus ingress :80" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus ingress :80" dir=in action=allow protocol=TCP localport=80
if errorlevel 1 (
    echo ERROR: failed to add firewall rule.
    exit /b 1
)

echo LAN exposure configured. Verify later with:
echo     netsh interface portproxy show v4tov4
echo     netsh advfirewall firewall show rule name="Nexus ingress :80"
echo.

echo === Starting minikube ^(base script^) ===
call "%~dp0minikube_start.bat"
