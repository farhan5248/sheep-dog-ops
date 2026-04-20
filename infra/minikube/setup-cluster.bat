@echo off
REM Wrapper around setup-cluster-local.bat for machines that host services
REM for the whole LAN (e.g. windows-desktop running Nexus). Exposes the
REM ingress ports (80 + 443) via netsh portproxy so other machines on the
REM LAN can reach them, THEN hands off to the base script (which ends with
REM a foreground `minikube tunnel`).
REM
REM Why portproxy setup comes FIRST:
REM   setup-cluster-local.bat ends with `minikube tunnel` as a foreground
REM   process, so anything after the `call` never runs. We configure
REM   exposure before the call.
REM
REM Why this is needed at all:
REM   `minikube tunnel` only binds to 127.0.0.1, so the minikube ingress is
REM   not reachable across the LAN by default. The portproxy forwards
REM   <LAN-IP>:80 -> 127.0.0.1:80 and <LAN-IP>:443 -> 127.0.0.1:443 on this
REM   host. Port 443 is needed now that nexus serves HTTPS (#217).
REM
REM Requirements:
REM   - Must be run as Administrator (portproxy + firewall rules are privileged)
REM   - Only run on machines that intentionally serve the LAN
REM
REM Usage:
REM   Run as admin: setup-cluster.bat

REM Check for admin. fltmc.exe requires admin; it's a reliable probe.
fltmc >nul 2>&1
if errorlevel 1 (
    echo ERROR: this script must be run as Administrator.
    exit /b 1
)

echo === Configuring LAN exposure ===

REM Detect this machine's LAN IPv4 address. We bind the portproxy to this
REM specific address (not 0.0.0.0) because 0.0.0.0:80 would collide with
REM `minikube tunnel`'s 127.0.0.1:80 listener and prevent the tunnel from
REM binding.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /C:"IPv4 Address"') do (
    set LAN_IP=%%a
    goto :got_ip
)
:got_ip
set LAN_IP=%LAN_IP: =%
if "%LAN_IP%"=="" (
    echo ERROR: could not detect LAN IP via ipconfig.
    exit /b 1
)
echo Detected LAN IP: %LAN_IP%

echo Removing any existing portproxy rules on ports 80 and 443...
netsh interface portproxy delete v4tov4 listenport=80  listenaddress=0.0.0.0   >nul 2>&1
netsh interface portproxy delete v4tov4 listenport=80  listenaddress=%LAN_IP%  >nul 2>&1
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0   >nul 2>&1
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=%LAN_IP%  >nul 2>&1

echo Adding portproxy: %LAN_IP%:80 -^> 127.0.0.1:80...
netsh interface portproxy add v4tov4 listenport=80 listenaddress=%LAN_IP% connectport=80 connectaddress=127.0.0.1
if errorlevel 1 (
    echo ERROR: failed to add portproxy rule for port 80.
    exit /b 1
)

echo Adding portproxy: %LAN_IP%:443 -^> 127.0.0.1:443...
netsh interface portproxy add v4tov4 listenport=443 listenaddress=%LAN_IP% connectport=443 connectaddress=127.0.0.1
if errorlevel 1 (
    echo ERROR: failed to add portproxy rule for port 443.
    exit /b 1
)

echo Ensuring firewall rule "Nexus ingress :80" allows inbound TCP/80...
netsh advfirewall firewall delete rule name="Nexus ingress :80" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus ingress :80" dir=in action=allow protocol=TCP localport=80
if errorlevel 1 (
    echo ERROR: failed to add firewall rule for port 80.
    exit /b 1
)

echo Ensuring firewall rule "Nexus ingress :443" allows inbound TCP/443...
netsh advfirewall firewall delete rule name="Nexus ingress :443" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus ingress :443" dir=in action=allow protocol=TCP localport=443
if errorlevel 1 (
    echo ERROR: failed to add firewall rule for port 443.
    exit /b 1
)

echo LAN exposure configured. Verify later with:
echo     netsh interface portproxy show v4tov4
echo     netsh advfirewall firewall show rule name="Nexus ingress :80"
echo     netsh advfirewall firewall show rule name="Nexus ingress :443"
echo.

echo === Starting minikube ^(base script^) ===
call "%~dp0setup-cluster-local.bat"
