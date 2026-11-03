#Requires -Version 5.1
# =============================================================================
# preflight.ps1 - read-only checks before running parsvt.ps1 (v2.11)
# Usage (elevated): powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
# Read-only: downloads go to %TEMP% and are deleted at the end.
# Exit code 0: only PASS/WARN.  Exit code 1: at least one FAIL.
# Keep this file pure ASCII (Windows PowerShell 5.1 reads it as ANSI).
# =============================================================================
param([string]$TargetDrive = "C", [string]$Installer = "")
$ErrorActionPreference = "Continue"; $ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Results = New-Object System.Collections.Generic.List[object]; $TempFiles = New-Object System.Collections.Generic.List[string]
# Runs one check; an unexpected exception becomes a FAIL for that check only.
function Invoke-Check($Id, $Name, [scriptblock]$Body) {
    try { & $Body } catch { Add-Result $Id $Name FAIL "check error: $($_.Exception.Message)" }
}
function Add-Result($Id, $Name, $Status, $Detail) {
    $Results.Add([pscustomobject]@{ Id = $Id; Check = $Name; Status = $Status; Detail = $Detail })
    $c = @{ PASS = "Green"; WARN = "Yellow"; FAIL = "Red" }[$Status]
    Write-Host ("[{0}] {1,-3} {2}: {3}" -f $Status, $Id, $Name, $Detail) -ForegroundColor $c
}
# ---- Download URLs: read from parsvt.ps1 so there is one source of truth ----
if (-not $Installer) { $Installer = Join-Path $PSScriptRoot "parsvt.ps1" }
$Urls = [ordered]@{
    Apache   = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/httpd-2.4.69-261002-Win64-VS18.zip"
    ModFcgid = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/mod_fcgid-2.3.10-win64-VS18.zip"
    PHP74    = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/php-7.4.33-nts-Win32-vc15-x64.zip"
    PHP83    = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/php-8.3.33-nts-Win32-vs16-x64.zip"
    MariaDB  = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/mariadb-10.11.10-winx64.msi"
    WinAcme  = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/win-acme.v2.2.9.1701.x64.pluggable.zip"
    VCRedist = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/VC_redist.x64.exe"
}
$IonCube = [ordered]@{
    "7.4" = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/ioncube_loader_win_7.4.dll"
    "8.3" = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/ioncube_loader_win_8.3.dll"
}
$Mirror = ""; $UrlSource = "built-in defaults"
if (Test-Path $Installer) {
    $src = Get-Content $Installer -Raw
    foreach ($m in [regex]::Matches($src, '(?m)^\s*(\w+)\s*=\s*@\{\s*Url\s*=\s*"(https?://[^"]+)"')) { $Urls[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches($src, '(?m)^\s*"(\d\.\d)"\s*=\s*"(https?://[^"]+\.dll)"')) { $IonCube[$m.Groups[1].Value] = $m.Groups[2].Value }
    if ($src -match '(?m)^\s*VCRedistURL\s*=\s*"([^"]+)"') { $Urls["VCRedist"] = $Matches[1] }
    if ($src -match '(?m)^\s*Mirror\s*=\s*"([^"]*)"') { $Mirror = $Matches[1] }
    $UrlSource = $Installer
}
Write-Host "ParsVT preflight (read-only). URLs from: $UrlSource`n" -ForegroundColor Cyan
function Save-Temp($Url) {
    $f = Join-Path $env:TEMP ("parsvt-preflight-" + [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath))
    $TempFiles.Add($f)
    Invoke-WebRequest -Uri $Url -OutFile $f -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
    return $f
}
# HEAD request (GET when the server refuses HEAD); returns "200 (12.3 MB)" or throws.
function Test-Url($Url) {
    foreach ($method in "HEAD", "GET") {
        $req = [Net.HttpWebRequest]::Create($Url); $req.Method = $method; $req.Timeout = 30000; $req.AllowAutoRedirect = $true
        try {
            $resp = $req.GetResponse()
            $len = $resp.ContentLength; $code = [int]$resp.StatusCode; $resp.Close(); $req.Abort()
            $size = ""; if ($len -gt 0) { $size = " ({0:N1} MB)" -f ($len / 1MB) }
            return "$code$size"
        } catch [Net.WebException] {
            $r = $_.Exception.Response
            if ($r -and [int]$r.StatusCode -in 403, 405, 501 -and $method -eq "HEAD") { continue }
            if ($r) { throw "HTTP $([int]$r.StatusCode)" } else { throw $_.Exception.Message }
        }
    }
}
# PE header + import and delay-import DLL names (no PEReader in .NET Framework).
function Get-PEInfo($Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return $null }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -lt 0 -or $pe + 24 -gt $b.Length -or [BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { return $null }
    $machine = [BitConverter]::ToUInt16($b, $pe + 4)
    $nSec = [BitConverter]::ToUInt16($b, $pe + 6)
    $opt = $pe + 24
    $dd = $opt + 96; if ([BitConverter]::ToUInt16($b, $opt) -eq 0x20B) { $dd = $opt + 112 }
    $secs = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
    $toOff = {
        param($rva)
        for ($i = 0; $i -lt $nSec; $i++) {
            $s = $secs + 40 * $i
            $va = [BitConverter]::ToUInt32($b, $s + 12); $vs = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
            if ($rva -ge $va -and $rva -lt $va + $vs) { return [int]($rva - $va + [BitConverter]::ToUInt32($b, $s + 20)) }
        }
        return -1
    }
    $readStr = { param($off) $e = $off; while ($e -lt $b.Length -and $b[$e] -ne 0) { $e++ }; [Text.Encoding]::ASCII.GetString($b, $off, $e - $off) }
    $names = @()
    foreach ($dir in @(@{ Idx = 1; Size = 20; NameAt = 12 }, @{ Idx = 13; Size = 32; NameAt = 4 })) {
        $rva = [BitConverter]::ToUInt32($b, $dd + 8 * $dir.Idx)
        if ($rva -eq 0) { continue }
        $off = & $toOff $rva
        while ($off -ge 0 -and $off + $dir.Size -le $b.Length) {
            $nameRva = [BitConverter]::ToUInt32($b, $off + $dir.NameAt)
            if ($nameRva -eq 0) { break }
            $no = & $toOff $nameRva
            if ($no -ge 0) { $names += (& $readStr $no) }
            $off += $dir.Size
        }
    }
    return [pscustomobject]@{ Machine = $machine; Imports = $names }
}

try {
    Invoke-Check 1 "Windows version" {
        $os = Get-WmiObject Win32_OperatingSystem
        $script:build = [Environment]::OSVersion.Version.Build
        $known = @{ 14393 = "Server 2016"; 17763 = "Server 2019"; 20348 = "Server 2022" }
        if ($PSVersionTable.PSVersion -lt [Version]"5.1") { Add-Result 1 "Windows version" FAIL "PowerShell $($PSVersionTable.PSVersion); 5.1 is required" }
        elseif ($known.ContainsKey($script:build)) { Add-Result 1 "Windows version" PASS "$($os.Caption) build $script:build ($($known[$script:build]))" }
        else { Add-Result 1 "Windows version" WARN "$($os.Caption) build $script:build is not 14393/17763/20348 (not tested)" }
    }
    Invoke-Check 2 "Administrator" {
        $wp = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if ($wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Add-Result 2 "Administrator" PASS "running elevated" }
        else { Add-Result 2 "Administrator" FAIL "not elevated; right-click PowerShell > Run as administrator" }
    }
    Invoke-Check 3 "Internet" {
        foreach ($scheme in "https", "http") {
            try { $r = Invoke-WebRequest "$($scheme)://aweb.co/" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop; Add-Result 3 "aweb.co $scheme" PASS "HTTP $($r.StatusCode)" }
            catch { if ($scheme -eq "https") { Add-Result 3 "aweb.co https" FAIL $_.Exception.Message } else { Add-Result 3 "aweb.co http" WARN "$($_.Exception.Message) (installer uses HTTPS)" } }
        }
    }
    Invoke-Check 4 "aweb.co certificate" {
        try {
            $script:certInfo = $null
            $cb = [Net.Security.RemoteCertificateValidationCallback] {
                param($s, $cert, $chain, $errors)
                $c2 = New-Object Security.Cryptography.X509Certificates.X509Certificate2($cert)
                $script:certInfo = @{ Subject = $c2.Subject; Issuer = $c2.Issuer; NotAfter = $c2.NotAfter; Errors = $errors
                    Chain = (@($chain.ChainStatus | ForEach-Object { $_.Status }) -join ",") }
                return $true
            }
            $tcp = New-Object Net.Sockets.TcpClient("aweb.co", 443)
            $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, $cb)
            try { $ssl.AuthenticateAsClient("aweb.co", $null, [Security.Authentication.SslProtocols]::Tls12, $false) } finally { $ssl.Dispose(); $tcp.Close() }
            $ci = $script:certInfo
            $d = "subject '$($ci.Subject)', issuer '$($ci.Issuer)', expires $($ci.NotAfter.ToString('yyyy-MM-dd'))"
            if ("$($ci.Errors)" -ne "None") { Add-Result 4 "aweb.co certificate" FAIL "$d; errors: $($ci.Errors) $($ci.Chain) (check date/time and root certificate updates)" }
            elseif ($ci.NotAfter -lt (Get-Date).AddDays(14)) { Add-Result 4 "aweb.co certificate" WARN "$d (expires soon)" }
            else { Add-Result 4 "aweb.co certificate" PASS $d }
        } catch { Add-Result 4 "aweb.co certificate" FAIL $_.Exception.Message }
    }
    Invoke-Check 5 "ionCube DLLs (x64, NTS)" {
        foreach ($v in $IonCube.Keys) {
            $name = "ioncube_loader_win_$v.dll"; $major = $v.Split(".")[0]
            try {
                $info = Get-PEInfo (Save-Temp $IonCube[$v])
                $imp = @($info.Imports | ForEach-Object { $_.ToLowerInvariant() })
                if (-not $info) { Add-Result 5 $name FAIL "not a Windows DLL (download returned something else?)" }
                elseif ($info.Machine -ne 0x8664) { Add-Result 5 $name FAIL ("{0} : x86 or other (machine 0x{1:X4}) (MUST be replaced on aweb.co)" -f $name, $info.Machine) }
                elseif ($imp -contains "php$($major)ts.dll") { Add-Result 5 $name FAIL "$name : TS x64 (MUST be replaced on aweb.co)" }
                elseif ($imp -contains "php$major.dll") { Add-Result 5 $name PASS "$name : NTS x64 (OK)" }   # VC15/VC16/VC17 all accepted
                else { Add-Result 5 $name WARN "$name : x64, no php$major.dll import found (imports: $($imp -join ', '))" }
            } catch { Add-Result 5 $name FAIL "download failed: $($_.Exception.Message)" }
        }
    }
    Invoke-Check 6 "Download sources" {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        foreach ($k in @("Apache", "ModFcgid")) {
            $want = @{ Apache = "bin/httpd.exe"; ModFcgid = "mod_fcgid.so" }[$k]
            try {
                $z = [IO.Compression.ZipFile]::OpenRead((Save-Temp $Urls[$k]))
                try { $e = $z.Entries | Where-Object { $_.FullName.Replace('\', '/').EndsWith($want, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 } finally { $z.Dispose() }
                if ($e) { Add-Result 6 "$k zip" PASS "found $($e.FullName)" } else { Add-Result 6 "$k zip" FAIL "no $want inside $($Urls[$k])" }
            } catch { Add-Result 6 "$k zip" FAIL "$($Urls[$k]): $($_.Exception.Message)" }
        }
        # VC++ redistributable: downloaded and its version read, because the
        # Apache VS18 build needs 14.51.36247+ and an older file still installs
        # "successfully" (exit code 0) without providing it.
        try {
            $vcExe = Save-Temp $Urls["VCRedist"]
            $ev = (Get-Item $vcExe).VersionInfo
            $vcVer = New-Object Version($ev.FileMajorPart, $ev.FileMinorPart, $ev.FileBuildPart)
            if ($ev.FileMajorPart -eq 0) { Add-Result 6 "VCRedist version" WARN "cannot read the version of $($Urls['VCRedist'])" }
            elseif ($vcVer -lt [Version]"14.51.36247") { Add-Result 6 "VCRedist version" FAIL "$($Urls['VCRedist']) is $vcVer; the Apache VS18 build needs 14.51.36247+ (download https://aka.ms/vc14/vc_redist.x64.exe and upload it there)" }
            else { Add-Result 6 "VCRedist version" PASS "$($Urls['VCRedist']) is $vcVer" }
        } catch { Add-Result 6 "VCRedist version" FAIL "$($Urls['VCRedist']): $($_.Exception.Message)" }
        foreach ($k in @("PHP74", "PHP83", "MariaDB", "WinAcme")) {
            $cands = @($Urls[$k])
            if ($Mirror) { $cands = @(($Mirror.TrimEnd('/') + "/" + [IO.Path]::GetFileName(([Uri]$Urls[$k]).AbsolutePath)), $Urls[$k]) }
            $ok = $null; $errs = @()
            foreach ($u in $cands) { try { $ok = "$u -> $(Test-Url $u)"; break } catch { $errs += "$u -> $($_.Exception.Message)" } }
            if ($ok) { Add-Result 6 "$k download" PASS $ok }
            elseif ($k -in "PHP74", "WinAcme") { Add-Result 6 "$k download" WARN "$($errs -join '; ') (needed only for Vtiger 7 / SSL)" }
            else { Add-Result 6 "$k download" FAIL ($errs -join "; ") }
        }
    }
    Invoke-Check 7 "Ports 80/443" {
        foreach ($port in 80, 443) {
            $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $c) { Add-Result 7 "Port $port" PASS "free"; continue }
            $pn = "System (HTTP.sys: IIS, WinRM, SSRS)"; if ($c.OwningProcess -ne 4) { $pn = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName }
            Add-Result 7 "Port $port" WARN "in use by $pn (PID $($c.OwningProcess)); choose another port or stop it"
        }
    }
    Invoke-Check 8 "Disk space" {
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$($TargetDrive.TrimEnd(':')):'"
        if (-not $disk) { Add-Result 8 "Disk $TargetDrive" FAIL "drive not found" }
        else {
            $gb = [Math]::Round($disk.FreeSpace / 1GB, 1)
            if ($gb -lt 2) { Add-Result 8 "Disk $($disk.DeviceID)" FAIL "$gb GB free (install alone needs about 2 GB)" }
            elseif ($gb -lt 10) { Add-Result 8 "Disk $($disk.DeviceID)" WARN "$gb GB free; 10 GB recommended for backups" }
            else { Add-Result 8 "Disk $($disk.DeviceID)" PASS "$gb GB free" }
        }
    }
    Invoke-Check 9 "VC++ runtime" {
        $rk = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
        if (-not $rk) { $rk = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue }
        $dll = Join-Path $env:SystemRoot "System32\vcruntime140.dll"
        $fv = $null; if (Test-Path $dll) { $fv = (Get-Item $dll).VersionInfo }
        $reg = "none"; if ($rk) { $reg = "$($rk.Major).$($rk.Minor).$($rk.Bld)" }
        if ($fv -and (New-Object Version($fv.FileMajorPart, $fv.FileMinorPart, $fv.FileBuildPart)) -ge [Version]"14.51.36247") { Add-Result 9 "VC++ runtime" PASS "vcruntime140.dll $($fv.FileVersion), registry $reg" }
        else { Add-Result 9 "VC++ runtime" WARN "file $(if ($fv) { $fv.FileVersion } else { 'missing' }), registry $reg; below 14.51.36247 (needed by the Apache VS18 build), the installer will install it" }
    }
    Invoke-Check 10 "Existing services" {
        foreach ($svc in "Apache2.4", "MariaDB", "W3SVC") {
            $s = Get-WmiObject Win32_Service -Filter "Name='$svc'"
            if (-not $s) { Add-Result 10 "Service $svc" PASS "not installed"; continue }
            $why = "re-running the installer reuses/overwrites it"; if ($svc -eq "W3SVC") { $why = "IIS usually holds port 80" }
            Add-Result 10 "Service $svc" WARN "exists ($($s.State)), $($s.PathName); $why"
        }
    }
    Invoke-Check 11 "LongPathsEnabled" {
        $lp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -ErrorAction SilentlyContinue).LongPathsEnabled
        if ($lp -eq 1) { Add-Result 11 "LongPathsEnabled" PASS "1" } else { Add-Result 11 "LongPathsEnabled" WARN "not enabled; paths over 260 characters fail in zip extraction" }
    }
    Invoke-Check 12 "Firewall policy" {
        $gpo = @("DomainProfile", "PrivateProfile", "PublicProfile", "StandardProfile") | ForEach-Object { Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\$_" -ErrorAction SilentlyContinue } | Where-Object { $_ }
        $merge = @($gpo | Where-Object { $_.AllowLocalPolicyMerge -eq 0 })
        $active = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Where-Object { $_.PolicyStoreSourceType -eq "GroupPolicy" })
        if ($merge.Count) { Add-Result 12 "Firewall" WARN "Group Policy sets AllowLocalPolicyMerge=0: rules made by the installer are ignored; ask the domain admin to open the web port" }
        elseif ($gpo -or $active.Count) { Add-Result 12 "Firewall" WARN "profiles are GPO-managed; New-NetFirewallRule may be overridden" }
        else { Add-Result 12 "Firewall" PASS ((@(Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", ") + " (local policy)") }
    }
    Invoke-Check 13 "Support lifecycle" {
        if ($script:build -eq 14393 -and (Get-Date) -gt [datetime]"2027-01-12") { Add-Result 13 "Support lifecycle" WARN "Server 2016 extended support ended 2027-01-12; no more security updates" }
        elseif ($script:build -eq 14393) { Add-Result 13 "Support lifecycle" PASS "Server 2016 extended support until 2027-01-12" }
        else { Add-Result 13 "Support lifecycle" PASS "supported" }
    }
    Invoke-Check 14 "Installer file" {
        if (-not (Test-Path $Installer)) { Add-Result 14 "parsvt.ps1" WARN "not found next to preflight.ps1 ($Installer)" }
        elseif (Get-Item $Installer -Stream Zone.Identifier -ErrorAction SilentlyContinue) { Add-Result 14 "parsvt.ps1" WARN "downloaded file is blocked: run Unblock-File '$Installer' or use -ExecutionPolicy Bypass" }
        else { Add-Result 14 "parsvt.ps1" PASS "$Installer ($((Get-Content $Installer).Count) lines)" }
    }
} finally {
    foreach ($f in $TempFiles) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
$Results | Format-Table Id, Status, Check, Detail -AutoSize -Wrap | Out-String -Width 220 | Write-Host
$fails = @($Results | Where-Object { $_.Status -eq "FAIL" }).Count
$warns = @($Results | Where-Object { $_.Status -eq "WARN" }).Count
Write-Host "Summary: $($Results.Count) checks, $fails FAIL, $warns WARN" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Cyan
if ($fails) { Write-Host "  Fix items marked FAIL above before running parsvt.ps1" -ForegroundColor Red; exit 1 }
if ($warns) { Write-Host "  Read the WARN items, then run parsvt.ps1" -ForegroundColor Yellow } else { Write-Host "  Run parsvt.ps1" -ForegroundColor Green }
exit 0
