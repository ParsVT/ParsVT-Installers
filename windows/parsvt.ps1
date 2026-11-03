#Requires -Version 5.1
#Requires -RunAsAdministrator

# =============================================================================
# parsvt.ps1 - ParsVT CRM installer for Windows Server 2016 / 2019 / 2022
# Version: 2.11
# Native PowerShell. No Cygwin, no XAMPP.
#
# Keep this file pure ASCII. Windows PowerShell 5.1 reads a .ps1 without a BOM
# in the system ANSI code page; a UTF-8 em-dash inside a double-quoted string
# then contains a byte that PowerShell treats as a closing quote and the whole
# script fails to parse.
#
# Changes in 2.11 (REST API on the real server):
#   - REST API / Portal / SOAP / MCP pretty URLs (modules/ParsVT/ws/api/...)
#     returned "No input file specified". After the .htaccess rewrite to
#     Api.php/<path>, php-cgi with cgi.fix_pathinfo=1 sees REDIRECT_URL and
#     PATH_TRANSLATED and opens PATH_TRANSLATED as the script. The folders in
#     PathInfoDirs now get their own php-cgi class with cgi.fix_pathinfo=0 and
#     cgi.discard_path=1; parsvt-pathinfo.php restores PHP_SELF as mod_php
#     sets it. The rest of the CRM keeps cgi.fix_pathinfo=1.
#   - Root .htaccess: error-page targets with a wrong prefix are pointed at
#     /modules/ParsVT/errors/ ("/test/DEV/" and "/test/DEV0/" from developer
#     machines, "\/" from ParsVT's generator on Windows, which Apache shows
#     as plain text), and "Options +Indexes" becomes "-Indexes". A backup is
#     kept next to the file. Runs on install and repair.
#   - The Vtiger cron task calls http://<server IP>/vtigercron.php (the IP
#     chosen during install) instead of 127.0.0.1.
#   - -Quick on a server where the CRM is already installed runs Repair
#     instead of a new install.
#   - ionCube: an unchanged loader is not copied again; a loader held open
#     by php-cgi.exe is replaced after stopping Apache briefly (install
#     failed with "being used by another process" while Apache was running).
#   - License key: invisible characters and quotes from pasting are removed,
#     and the error says what is wrong (length or prefix).
#
# Changes in 2.10 (second real run, Windows Server 2022):
#   - VC++ runtime: the version of vc_redist.x64.exe is read before it runs;
#     one that is too old is skipped and VCRedistFallbackURL (Microsoft's
#     always-current link) is tried next.
#   - Support report zip uses "/" in entry names (PS 5.1 wrote "\", which
#     non-Windows tools show as one flat file name).
#
# Changes in 2.9 (first real run, Windows Server 2022):
#   - ionCube load test: the DLL path is quoted. %TEMP% can be an 8.3 short
#     path (C:\Users\ADMINI~1\...) and PHP's ini parser reads an unquoted
#     "~" as an operator ("syntax error, unexpected '~'").
#   - preflight output is written to the install log once, not twice.
#   - An empty install folder (created while checking the paths) is removed
#     instead of being moved to "<dir>.incomplete-<time>".
#   - The VC++ runtime version is checked again after vc_redist.x64.exe ran.
#
# Changes in 2.8:
#   - php.ini matches the Linux installer: error_reporting without notices
#     and warnings, session.use_strict_mode = 1, and the ldap, odbc,
#     pdo_odbc, sockets (and xmlrpc on 7.4) extensions it installs.
#
# Changes in 2.7:
#   - Vtiger cron uses curl.exe by default (VtigerCronMode = "curl"): the
#     ParsVT package's vtigercron.php accepts the local HTTP call. php.exe
#     is still used on Server 2016, which has no curl.exe.
#
# Changes in 2.6:
#   - Vtiger cron: curl.exe over HTTP (as on the Linux installer) when this
#     vtigercron.php accepts web requests; php.exe otherwise and on Server
#     2016 (no curl.exe). Stock Vtiger answers HTTP calls with "Access denied!"
#     and HTTP 200, so curl alone would silently run nothing. VtigerCronMode
#     in Config forces one of them.
#   - VC++ runtime minimum raised to 14.51.36247 (Apache Lounge VS18 builds),
#     and the build number is now part of the comparison.
#
# Changes in 2.5:
#   - -Quick runs preflight.ps1 (next to this file) before anything is
#     installed and stops, with the support report, when a check FAILs.
#     -SkipPreflight turns this off. Interactive mode does not run it.
#
# Changes in 2.4:
#   - -Quick: only the license key is asked; everything else uses the
#     defaults (Vtiger 8, port 80, default paths, no domain, no SSL,
#     phpMyAdmin restricted, Defender exclusions). Typed OVERWRITE stays.
#   - Every failed run writes ParsVT-Report-<time>.zip (logs with secrets
#     removed, system information) to the Desktop and shows a Persian
#     message box. Used by the "Install ParsVT.cmd" launcher.
#
# Changes in 2.3:
#   - ionCube check no longer pins a VC version (VC15/VC16/VC17 are all
#     accepted). Before copying, the DLL must be x64 and import php7.dll /
#     php8.dll (NTS), read from the real PE import table; PHP's own load
#     test then decides, and its message is shown when it refuses the DLL.
#
# Changes in 2.2:
#   - phpMyAdmin (cookie login, no stored password) under the /phpmyadmin
#     Alias, installed outside the web root; restricted to localhost and
#     private networks unless the operator chooses otherwise.
#
# Changes in 2.1:
#   - External programs are always started by full path (robocopy, mysql,
#     msiexec); the MariaDB folder is taken from the MariaDB service.
#   - Optional Windows Defender exclusions for the binaries, the backups and
#     the MariaDB data (the web root, which holds uploads, is never excluded).
#
# Changes in 2.0:
#   - Configurable web server port, install paths and domain name; they are
#     saved to install-state.json so Repair and ionCube-only use them.
#   - restore.ps1 is generated next to backup.ps1.
#   - Desktop / Start Menu shortcuts (all users) to restart Apache and MariaDB.
#   - ionCube DLL is checked before it is copied: PHP build (NTS), DLL
#     architecture and PHP import (NTS/TS), and a load test from %TEMP%.
#   - Visual C++ runtime is checked by version, not just by file presence.
#   - Every external program (httpd, mysql, mysqldump, php, robocopy, wacs)
#     runs through Invoke-Native: exit code checked, stderr shown, step aborted.
#   - Active PHP directory and MariaDB bin are added to the machine PATH.
#
# Changes in 1.1 (kept):
#   - PHP through mod_fcgid (NTS builds), VC++ runtime first, mirror + SHA256
#     downloads, staged Vtiger extraction, typed OVERWRITE confirmation,
#     SQL through mysql stdin with checked exit codes, vtigercron via php.exe,
#     backup with --result-file + streaming gzip + .NET zip, SSL chain file and
#     reload hook, install log, early credential persistence, directory ACLs.
# =============================================================================

param(
    [switch]$DryRun,
    [switch]$Quick,         # only the license key is asked; see Main-Install and the Get-* prompts
    [switch]$SkipPreflight  # -Quick only: do not run preflight.ps1 first
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # PS 5.1 progress bar makes Invoke-WebRequest many times slower
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Config = @{
    PrimarySite      = "aweb.co"
    ApacheDir        = "C:\Apache24"           # default; Get-InstallPaths may change it
    WebRoot          = "C:\Apache24\htdocs"    # default; Get-InstallPaths may change it
    ApachePort       = 80                      # default; Get-ApachePort may change it
    ApacheService    = "Apache2.4"
    PHPBaseDir       = "C:\PHP"
    PHP74Dir         = "C:\PHP\7.4"
    PHP83Dir         = "C:\PHP\8.3"
    MariaDBDir       = "C:\Program Files\MariaDB 10.11"
    BackupDir        = "C:\backup"
    LogDir           = "C:\parsvt-logs"
    BackupScriptDir  = "C:\Program Files\ParsVT"
    ShortcutsDir     = "C:\Program Files\ParsVT\Shortcuts"
    StateFile        = "C:\Program Files\ParsVT\install-state.json"
    CertsDir         = "C:\Program Files\ParsVT\certs"
    WinAcmeDir       = "C:\Program Files\win-acme"
    CredentialsFile  = "C:\parsvt-credentials.txt"

    # Optional mirror (for example on aweb.co). When set, every third-party
    # download is tried as "<Mirror>/<file name>" first, then the upstream URL.
    Mirror           = ""

    VCRedistURL      = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/VC_redist.x64.exe"
    # Tried when the file above is older than VCRedistMinVersion or cannot be
    # downloaded: Microsoft's link that always serves the newest 14.x runtime
    # (the one Apache Lounge points to). Empty = no fallback.
    VCRedistFallbackURL = "https://aka.ms/vc14/vc_redist.x64.exe"
    VCRedistMinVersion = "14.51.36247"   # Apache Lounge VS18 (Visual Studio 2026) builds need this runtime or newer
    # "curl" (default): curl.exe calls http://<ServerIP>:<port>/vtigercron.php, as the Linux installer does;
    #   needs the ParsVT vtigercron.php, which accepts that call. php.exe on Server 2016 (no curl.exe).
    # "php": php.exe -f vtigercron.php. "auto": curl only when vtigercron.php has no command-line-only check.
    VtigerCronMode     = "curl"
    # Web-root-relative folders whose scripts are reached through rewrites to
    # "<script>.php/<path>" (PATH_INFO). Each gets its own php-cgi class; see
    # Set-ApachePHPConfig. Add a folder here if another module shows
    # "No input file specified" on its pretty URLs.
    PathInfoDirs       = @("modules/ParsVT/ws")

    # Third-party downloads. Fill Sha256 to enforce integrity; empty = warn only.
    Downloads        = @{
        VCRedist = @{ Url = ""; File = "vc_redist.x64.exe"; Sha256 = "" }   # Url comes from VCRedistURL
        Apache   = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/httpd-2.4.69-261002-Win64-VS18.zip"; File = "httpd-2.4.69-261002-Win64-VS18.zip"; Sha256 = "" }
        ModFcgid = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/mod_fcgid-2.3.10-win64-VS18.zip"; File = "mod_fcgid-2.3.10-win64-VS18.zip"; Sha256 = "" }
        PHP74    = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/php-7.4.33-nts-Win32-vc15-x64.zip"; File = "php-7.4.33-nts-Win32-vc15-x64.zip"; Sha256 = "" }
        PHP83    = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/php-8.3.33-nts-Win32-vs16-x64.zip"; File = "php-8.3.33-nts-Win32-vs16-x64.zip"; Sha256 = "" }
        MariaDB  = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/mariadb-10.11.10-winx64.msi"; File = "mariadb-10.11.10-winx64.msi"; Sha256 = "" }
        WinAcme  = @{ Url = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/win-acme.v2.2.9.1701.x64.pluggable.zip"; File = "win-acme.v2.2.9.1701.x64.pluggable.zip"; Sha256 = "" }
    }

    LicenseEndpoint  = "https://aweb.co/modules/addons/easyservice/Installer/check.php"
    DownloadEndpoint = "https://aweb.co/modules/addons/easyservice/Installer/download.php"
    # Must be the NON-thread-safe (NTS) x64 loaders: PHP is installed as NTS.
    IonCubeURLs      = @{
        "7.4" = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/ioncube_loader_win_7.4.dll"
        "8.3" = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/ioncube_loader_win_8.3.dll"
    }
    VtigerToPHP      = @{ 7 = "7.4"; 8 = "8.3" }
    DBName           = "parsvt"
    DBUser           = "root"
    DBHost           = "localhost"
    DBPort           = ""
    LicenseKey       = ""
    ServerIP         = "127.0.0.1"
    ExtToken         = ""
    ExtURL           = ""
    AdminPassword    = ""   # CRM "admin" user password (plain text, shown once)
    MySQLPassword    = ""   # password of DBUser (root on fresh installs)
    Domain           = ""
    SslEnabled       = $false
    PhpMyAdminVersion    = "5.2.3"   # 5.2.1 lacks the PMASA-2025-1/2/3 fixes (released in 5.2.2)
    PhpMyAdminURL        = "https://license.aweb.co/ExtensionsZip/NightlyBuilds/WindowsInstaller/phpMyAdmin-5.2.3-all-languages.zip"
    PhpMyAdminRestricted = $true     # Require ip localhost + private networks
    VtigerVersion    = 0
    PHPVersion       = ""
}
$script:TranscriptOn = $false
$script:FailureReported = $false
$script:OverwriteConfirmed = $false
$script:InstallLog   = ""

# =============================================================================
# Utilities
# =============================================================================

function Write-Step { param($m) Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [X] $m" -ForegroundColor Red }

# Every exit with a non-zero code goes through here, including the top-level
# catch, so every failure produces a support report and the Persian message.
# Code 0 (cancelled by the operator) produces neither.
function Stop-Install {
    param([string]$Message, [int]$Code = 1)
    if ($Message) { Write-Err $Message }
    if ($script:InstallLog) { Write-Host "  Install log: $($script:InstallLog)" -ForegroundColor Yellow }
    Suspend-InstallLog
    if ($Code -ne 0) { Invoke-FailureReport -Reason $Message -Code $Code }
    exit $Code
}

function Start-InstallLog {
    if ($DryRun) { return }
    New-Dir $Config.LogDir
    Set-DirAcl -Path $Config.LogDir
    $script:InstallLog = Join-Path $Config.LogDir ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    try { Start-Transcript -Path $script:InstallLog -Append | Out-Null; $script:TranscriptOn = $true } catch { }
}
function Suspend-InstallLog {
    if ($script:TranscriptOn) { try { Stop-Transcript | Out-Null } catch { }; $script:TranscriptOn = $false }
}
function Resume-InstallLog {
    if ($script:InstallLog -and -not $script:TranscriptOn) {
        try { Start-Transcript -Path $script:InstallLog -Append | Out-Null; $script:TranscriptOn = $true } catch { }
    }
}

# Quotes one argument for the Windows command line (MSVCRT rules), so values
# with spaces, quotes or trailing backslashes reach the program unchanged.
function ConvertTo-WinArgument {
    param([string]$Arg)
    if ($Arg -eq "") { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs) { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * ($bs * 2))
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Runs an external program and checks its exit code.
#  - stdout and stderr are captured completely (System.Diagnostics.Process;
#    Start-Process -PassThru can return an empty ExitCode for short-lived
#    processes on PS 5.1, which would be a silent failure).
#  - -StdinFile streams a file's raw bytes to stdin (mysql imports).
#  - On an exit code outside -SuccessCodes the last 15 lines of stderr (or
#    stdout) are printed and the step is aborted with an exception, unless
#    -AllowFailure is given; then the caller inspects .Ok / .ExitCode.
function Invoke-Native {
    param(
        [string]$Exe,
        [string[]]$Arguments = @(),
        [string]$WorkDir = "",
        [string]$StdinFile = "",
        [int[]]$SuccessCodes = @(0),
        [string]$Step = "",
        [switch]$AllowFailure
    )
    $name = $Step
    if (-not $name) { $name = Split-Path $Exe -Leaf }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (@($Arguments) | ForEach-Object { ConvertTo-WinArgument $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = [bool]$StdinFile
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $out = ""; $err = ""; $rc = -1
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if ($StdinFile) {
            $fs = [IO.File]::OpenRead($StdinFile)
            try { $fs.CopyTo($p.StandardInput.BaseStream) } catch { $err = "stdin: $($_.Exception.Message)`n" } finally { $fs.Dispose() }
            try { $p.StandardInput.Close() } catch { }
        }
        $p.WaitForExit()
        $out = $outTask.Result
        $err = $err + $errTask.Result
        $rc = $p.ExitCode
    } catch {
        $err = $err + "Could not run $Exe : $($_.Exception.Message)"
        $rc = -1
    } finally { $p.Dispose() }

    $ok = ($SuccessCodes -contains $rc)
    $all = (@($out, $err) | Where-Object { $_ -and $_.Trim() }) -join "`n"
    $res = [pscustomobject]@{ ExitCode = $rc; Ok = $ok; Output = "$out".TrimEnd(); Error = "$err".TrimEnd(); All = "$all".TrimEnd() }
    if (-not $ok -and -not $AllowFailure) {
        Write-Err "$name failed (exit code $rc). Last output lines:"
        $src = $err
        if (-not "$src".Trim()) { $src = $out }
        @("$src" -split "\r?\n" | Where-Object { $_.Trim() }) | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }
        throw "$name failed with exit code $rc"
    }
    return $res
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Internet {
    try {
        Invoke-WebRequest -Uri "https://$($Config.PrimarySite)/" -UseBasicParsing -TimeoutSec 15 | Out-Null
        return $true
    } catch { return $false }
}

function Test-WindowsVersion {
    $v = [Environment]::OSVersion.Version
    return @{ Build = $v.Build; Full = $v; Supported = ($v.Build -ge 14393) }
}

function Test-PortListening {
    param($Port)
    $t = New-Object Net.Sockets.TcpClient
    try { $t.Connect("127.0.0.1", $Port); return $true } catch { return $false } finally { $t.Close() }
}

function Test-PortFree {
    param([int]$Port)
    if (Get-PortOwner $Port) { return $false }
    return -not (Test-PortListening $Port)
}

# Returns the process name listening on a port, or "" when the port is free.
function Get-PortOwner {
    param([int]$Port)
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return "" }
    if ($c.OwningProcess -eq 4) { return "System (HTTP.sys - IIS, WinRM/HTTP listener, SSRS or Web Deploy)" }
    $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName }
    return "PID $($c.OwningProcess)"
}

function New-RandomPassword {
    param([int]$Length = 15)
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $s = [Convert]::ToBase64String($bytes) -replace '[+/=]', 'x'
    return $s.Substring(0, $Length)
}

function New-Dir { param($Path) if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function Write-TextFile {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function ConvertTo-ApachePath { param([string]$Path) return ($Path -replace '\\', '/') }

function Get-CrmUrl {
    if ([int]$Config.ApachePort -eq 80) { return "http://$($Config.ServerIP)/" }
    return "http://$($Config.ServerIP):$($Config.ApachePort)/"
}

# Downloads $Url (or the mirror copy) to $OutFile and checks SHA256 when given.
function Invoke-Download {
    param([string]$Url, [string]$OutFile, [string]$Sha256 = "", [string]$MirrorName = "")
    if ($DryRun) { Write-Host "  [DRY] Download $Url -> $OutFile" -ForegroundColor DarkGray; return $true }
    $candidates = @()
    if ($Config.Mirror -and $MirrorName) { $candidates += ($Config.Mirror.TrimEnd('/') + "/" + $MirrorName) }
    $candidates += $Url
    foreach ($u in $candidates) {
        Write-Host "  Downloading $u" -ForegroundColor Gray
        try {
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
            Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec 900
        } catch {
            Write-Warn "Download failed: $($_.Exception.Message)"
            continue
        }
        if ($Sha256) {
            $h = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
            if ($h -ne $Sha256.ToUpperInvariant()) {
                Write-Err "SHA256 mismatch for $u (got $h)."
                Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
                continue
            }
        } elseif ($MirrorName) {
            Write-Warn "No SHA256 configured for $(Split-Path $OutFile -Leaf); integrity not verified."
        }
        return $true
    }
    Write-Err "Could not download $Url"
    return $false
}

function Invoke-ConfiguredDownload {
    param([string]$Name, [string]$OutFile)
    $d = $Config.Downloads[$Name]
    return (Invoke-Download -Url $d.Url -OutFile $OutFile -Sha256 $d.Sha256 -MirrorName $d.File)
}

# Expand-Archive on PS 5.1 is very slow on large archives; ZipFile is not.
# Extracts into an empty directory only (.NET Framework cannot overwrite).
function Expand-ZipFile {
    param($ZipPath, $DestPath)
    if ($DryRun) { Write-Host "  [DRY] Extract $ZipPath -> $DestPath" -ForegroundColor DarkGray; return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $DestPath) { Remove-Item $DestPath -Recurse -Force }
    New-Dir $DestPath
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestPath)
}

# Merges $Source into $Dest (overwriting). robocopy exit codes below 8 mean success.
function Copy-Tree {
    param([string]$Source, [string]$Dest)
    New-Dir $Dest
    Invoke-Native (Join-Path $env:SystemRoot "System32\robocopy.exe") @($Source, $Dest, "/E", "/R:2", "/W:2", "/NFL", "/NDL", "/NJH", "/NJS", "/NP") -SuccessCodes @(0, 1, 2, 3, 4, 5, 6, 7) -Step "robocopy" | Out-Null
}

# Files: Administrators + SYSTEM only, inherited ACEs removed.
function Set-FileAcl-AdminsOnly {
    param($Path)
    if ($DryRun) { return }
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, "FullControl", "Allow")))
    }
    (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
}

# Directories: Administrators + SYSTEM full control; Users read only when -UsersRead.
# Removes the "Authenticated Users: Modify" that every new folder under C:\ inherits.
function Set-DirAcl {
    param([string]$Path, [switch]$UsersRead)
    if ($DryRun -or -not (Test-Path $Path)) { return }
    $inh = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, "FullControl", $inh, $prop, "Allow")))
    }
    if ($UsersRead) {
        $id = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, "ReadAndExecute", $inh, $prop, "Allow")))
    }
    (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
}

function Get-SystemInfo {
    $os = Get-WmiObject Win32_OperatingSystem
    $ver = Test-WindowsVersion
    $panel = "none"
    if (Test-Path "C:\Program Files (x86)\Plesk") { $panel = "Plesk" }
    if (Test-Path "C:\Program Files\Parallels")    { $panel = "Plesk" }

    Write-Host ""
    Write-Host "System information:" -ForegroundColor Yellow
    Write-Host "  Operating system  : $($os.Caption)"
    Write-Host "  Version           : $($os.Version) (Build $($ver.Build))"
    Write-Host "  Architecture      : $($os.OSArchitecture)"
    Write-Host "  PowerShell        : $($PSVersionTable.PSVersion)"
    Write-Host "  Control panel     : $panel"
    Write-Host "  IIS (W3SVC)       : $(if (Get-Service -Name W3SVC -ErrorAction SilentlyContinue) { 'installed' } else { 'not installed' })"
    Write-Host "  Apache            : $(if (Test-Path (Join-Path $Config.ApacheDir 'bin\httpd.exe')) { "installed at $($Config.ApacheDir), port $($Config.ApachePort)" } else { 'not installed' })"
    Write-Host "  PHP 7.4           : $(if (Test-Path "$($Config.PHP74Dir)\php.exe") { 'installed' } else { 'not installed' })"
    Write-Host "  PHP 8.3           : $(if (Test-Path "$($Config.PHP83Dir)\php.exe") { 'installed' } else { 'not installed' })"
    Write-Host "  MariaDB service   : $(if (Get-Service -Name MariaDB -ErrorAction SilentlyContinue) { 'installed' } else { 'not installed' })"
    $crmVer = "none"
    $v = Get-VtigerVersion
    if ($v) { $crmVer = "Vtiger $v" }
    Write-Host "  CRM at $($Config.WebRoot): $crmVer"
    Write-Host ""
    return @{ Panel = $panel; Version = $ver; CRMVersion = $crmVer }
}

function Get-VtigerVersion {
    param([string]$Dir = $Config.WebRoot)
    $vf = Join-Path $Dir "vtigerversion.php"
    if (-not (Test-Path $vf)) { return "" }
    $content = Get-Content $vf -Raw
    if ($content -match '\$vtiger_current_version\s*=\s*[''"]([\d\.]+)[''"]') { return $Matches[1] }
    return ""
}

function Get-PHPDir { param([string]$Version) if ($Version -eq "7.4") { return $Config.PHP74Dir } return $Config.PHP83Dir }

# Asks the operator to type a word before anything destructive happens.
function Confirm-Typed {
    param([string]$Prompt, [string]$Word)
    Write-Host ""
    Write-Host $Prompt -ForegroundColor Red
    $a = Read-Host "Type $Word to continue, anything else cancels"
    return ($a -ceq $Word)
}

# =============================================================================
# Support report and Persian messages
# =============================================================================

# Persian text is stored as \u escapes so this file stays pure ASCII.
# Never put a path or other backslash text inside these strings: add it with
# string concatenation instead ([regex]::Unescape would read it as an escape).
$script:FaText = @{
    ErrorTitle = [regex]::Unescape('\u062e\u0637\u0627 \u062f\u0631 \u0646\u0635\u0628')
    ErrorBody  = [regex]::Unescape('\u0645\u062a\u0623\u0633\u0641\u0627\u0646\u0647 \u0646\u0635\u0628 \u0628\u0627 \u062e\u0637\u0627 \u0645\u0648\u0627\u062c\u0647 \u0634\u062f. \u0641\u0627\u06cc\u0644 \u06af\u0632\u0627\u0631\u0634 \u062f\u0631 \u062f\u0633\u06a9\u062a\u0627\u067e \u0634\u0645\u0627 \u0630\u062e\u06cc\u0631\u0647 \u0634\u062f. \u0644\u0637\u0641\u0627\u064b \u0622\u0646 \u0631\u0627 \u0628\u0631\u0627\u06cc \u067e\u0634\u062a\u06cc\u0628\u0627\u0646\u06cc \u0627\u0631\u0633\u0627\u0644 \u06a9\u0646\u06cc\u062f.')
    ReportPath = [regex]::Unescape('\u0645\u0633\u06cc\u0631 \u0641\u0627\u06cc\u0644 \u06af\u0632\u0627\u0631\u0634:')
    NoReport   = [regex]::Unescape('\u0645\u062a\u0623\u0633\u0641\u0627\u0646\u0647 \u0646\u0635\u0628 \u0628\u0627 \u062e\u0637\u0627 \u0645\u0648\u0627\u062c\u0647 \u0634\u062f \u0648 \u0633\u0627\u062e\u062a \u0641\u0627\u06cc\u0644 \u06af\u0632\u0627\u0631\u0634 \u0647\u0645 \u0645\u0645\u06a9\u0646 \u0646\u0634\u062f. \u0644\u0637\u0641\u0627\u064b \u0645\u062d\u062a\u0648\u06cc\u0627\u062a \u0627\u06cc\u0646 \u067e\u0648\u0634\u0647 \u0631\u0627 \u0628\u0631\u0627\u06cc \u067e\u0634\u062a\u06cc\u0628\u0627\u0646\u06cc \u0627\u0631\u0633\u0627\u0644 \u06a9\u0646\u06cc\u062f:')
    Detail     = [regex]::Unescape('\u062c\u0632\u0626\u06cc\u0627\u062a \u062e\u0637\u0627 (\u0628\u0631\u0627\u06cc \u067e\u0634\u062a\u06cc\u0628\u0627\u0646\u06cc):')
}

# Persian message box (RTL). Falls back to the console when Windows Forms is
# not available (Server Core) or no one is logged on interactively.
function Show-FaMessage {
    param([string]$Title, [string]$Text, [string]$Icon = "Error")
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        # An invisible top-most owner keeps the box in front of the console.
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.Opacity = 0
        $owner.StartPosition = "CenterScreen"; $owner.Show(); $owner.Activate()
        try {
            $opts = [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor [System.Windows.Forms.MessageBoxOptions]::RightAlign
            [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::$Icon, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $opts)
        } finally { $owner.Close(); $owner.Dispose() }
        return $true
    } catch {
        Write-Warn "Message box not available ($($_.Exception.Message)); see the messages above."
        return $false
    }
}

# Replaces secrets in log text: the db_password URL parameter (the _install.php
# call), PASSWORD=... in MSI logs, and every secret this run knows literally
# (MariaDB password, CRM admin password, license key), plain and URL-encoded.
function Protect-LogText {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = [regex]::Replace($Text, '(?i)(db_password=)[^&\s"'']*', '$1***REDACTED***')
    $t = [regex]::Replace($t, '(?-i)\b(PASSWORD\s*=\s*)("[^"]*"|[^\s;]+)', '$1***REDACTED***')
    foreach ($secret in @($Config.MySQLPassword, $Config.AdminPassword, $Config.LicenseKey)) {
        if (-not $secret -or $secret.Length -lt 6) { continue }
        foreach ($form in @($secret, [Uri]::EscapeDataString($secret)) | Select-Object -Unique) {
            $t = $t.Replace($form, "***REDACTED***")
        }
    }
    return $t
}

# Copies the last $MaxBytes of a log (files Apache/MariaDB keep open are read
# with sharing), removes secrets and writes it as UTF-8.
function Copy-LogTail {
    param([string]$Source, [string]$Dest, [long]$MaxBytes = 5MB)
    $fs = New-Object IO.FileStream($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $head = New-Object byte[] 3
        $n = $fs.Read($head, 0, 3)
        $enc = [Text.Encoding]::UTF8; $skip = 0
        if ($n -ge 2 -and $head[0] -eq 0xFF -and $head[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode; $skip = 2 }
        elseif ($n -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) { $skip = 3 }
        $start = [Math]::Max([long]$skip, $fs.Length - $MaxBytes)
        if ($enc -eq [Text.Encoding]::Unicode -and (($start - $skip) % 2) -ne 0) { $start++ }
        [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($fs.Length - $start))
        $read = 0
        while ($read -lt $buf.Length) { $r = $fs.Read($buf, $read, $buf.Length - $read); if ($r -le 0) { break }; $read += $r }
        $text = $enc.GetString($buf, 0, $read)
        if ($start -gt $skip) { $text = "[... only the last $([Math]::Round($MaxBytes / 1MB)) MB of $Source ...]`r`n" + $text }
    } finally { $fs.Dispose() }
    New-Dir (Split-Path $Dest -Parent)
    Write-TextFile $Dest (Protect-LogText $text)
}

# Text file with what support needs first. Every probe is independent: one
# failing probe never stops the report.
function Get-SupportSystemInfo {
    param([string]$Reason, [int]$Code)
    $o = New-Object System.Collections.Generic.List[string]
    $add = { param($title, [scriptblock]$probe)
        $o.Add(""); $o.Add("== $title")
        try { foreach ($line in @(& $probe)) { $o.Add("$line") } } catch { $o.Add("(probe failed: $($_.Exception.Message))") }
    }
    $o.Add("ParsVT support report - parsvt.ps1 v2.11")
    $o.Add("Created:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $o.Add("Computer:  $env:COMPUTERNAME")
    $o.Add("Mode:      $(if ($Quick) { 'Quick' } else { 'Interactive' })$(if ($DryRun) { ' (DryRun)' })")
    $o.Add("Exit code: $Code")
    $o.Add("Reason:    $(Protect-LogText $Reason)")
    & $add "Operating system" {
        $os = Get-WmiObject Win32_OperatingSystem
        "$($os.Caption) $($os.Version) build $([Environment]::OSVersion.Version.Build) $($os.OSArchitecture)"
        "Install language: $((Get-Culture).Name), UI: $((Get-UICulture).Name), system locale: $((Get-WinSystemLocale -ErrorAction SilentlyContinue).Name)"
        "Last boot: $($os.ConvertToDateTime($os.LastBootUpTime))"
    }
    & $add "PowerShell / .NET" {
        "PowerShell $($PSVersionTable.PSVersion), CLR $($PSVersionTable.CLRVersion)"
        $rel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Release
        ".NET Framework 4 release key: $rel"
    }
    & $add "Configured paths" {
        "ApacheDir=$($Config.ApacheDir)  WebRoot=$($Config.WebRoot)  Port=$($Config.ApachePort)"
        "PHP=$($Config.PHPVersion)  MariaDBDir=$($Config.MariaDBDir)  Domain=$($Config.Domain)"
    }
    & $add "Machine PATH (registry)" { ([Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:EnvRegPath)).GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -split ';' }
    & $add "Process PATH" { $env:PATH -split ';' }
    & $add "Services" {
        foreach ($n in @($Config.ApacheService, "MariaDB", "W3SVC")) {
            $s = Get-WmiObject Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
            if ($s) { "$n : $($s.State), start=$($s.StartMode), $($s.PathName)" } else { "$n : not installed" }
        }
    }
    & $add "Listening ports" {
        foreach ($port in @(80, 443, 3306, [int]$Config.ApachePort) | Select-Object -Unique) {
            $owner = Get-PortOwner $port
            if ($owner) { "$port : $owner" } else { "$port : free" }
        }
    }
    & $add "Disk" { Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { "{0} {1:N1} GB free of {2:N1} GB" -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB) } }
    & $add "Visual C++ runtime" { (Get-Item (Join-Path $env:SystemRoot "System32\vcruntime140.dll") -ErrorAction Stop).VersionInfo.FileVersion }
    & $add "httpd -t" {
        $h = Join-Path $Config.ApacheDir "bin\httpd.exe"
        if (Test-Path $h) { (Invoke-Native $h @("-t") -WorkDir (Join-Path $Config.ApacheDir "bin") -AllowFailure).All } else { "httpd.exe not found" }
    }
    & $add "php -v" {
        $php = Join-Path (Get-PHPDir $Config.PHPVersion) "php.exe"
        if ($Config.PHPVersion -and (Test-Path $php)) { (Invoke-Native $php @("-v") -AllowFailure).All } else { "php.exe not found" }
    }
    & $add "Scheduled tasks" {
        Get-ScheduledTask -TaskName "ParsVT-*" -ErrorAction SilentlyContinue | ForEach-Object {
            $i = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            "$($_.TaskName): $($_.State), last run $($i.LastRunTime), last result $($i.LastTaskResult)"
        }
    }
    & $add "Application event log (errors, last 3 days)" {
        $since = (Get-Date).AddDays(-3)
        Get-WinEvent -FilterHashtable @{ LogName = "Application"; Level = 1, 2; StartTime = $since } -MaxEvents 200 -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'Apache|MariaDB|MySQL|SideBySide|Application Error|Windows Error Reporting|MsiInstaller' } |
            Select-Object -First 40 | ForEach-Object { "[$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))] $($_.ProviderName) $($_.Id): $(($_.Message -replace '\s+', ' ').Trim())" }
    }
    return (Protect-LogText ($o -join "`r`n"))
}

# Builds Desktop\ParsVT-Report-<yyyyMMdd-HHmmss>.zip and returns its path, or
# "" when it could not be created. Never throws: a broken report must not
# hide the original error.
#
# Included: C:\parsvt-logs\*.log, Apache error/access/ssl logs, MariaDB *.err,
# install-state.json, the ParsVT Apache configuration, php.ini, system-info.txt.
# Never included: parsvt-credentials.txt, backup.cnf, config.inc.php (CRM and
# phpMyAdmin): they hold passwords. Logs are scrubbed by Protect-LogText.
function New-SupportBundle {
    param([string]$Reason = "", [int]$Code = 1)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $name = "ParsVT-Report-$stamp"
    $work = Join-Path ([IO.Path]::GetTempPath()) $name
    $desk = [Environment]::GetFolderPath("Desktop")
    if (-not $desk -or -not (Test-Path $desk)) { $desk = $Config.LogDir }
    $zip = Join-Path $desk "$name.zip"
    try {
        New-Dir $work
        $items = New-Object System.Collections.Generic.List[object]
        if (Test-Path $Config.LogDir) {
            Get-ChildItem $Config.LogDir -File -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object { $items.Add(@($_.FullName, "parsvt-logs\$($_.Name)")) }
        }
        foreach ($f in @("error.log", "access.log", "parsvt-ssl-error.log", "parsvt-ssl-access.log")) {
            $items.Add(@((Join-Path $Config.ApacheDir "logs\$f"), "apache-logs\$f"))
        }
        Get-ChildItem (Join-Path $Config.MariaDBDir "data") -File -Filter "*.err" -ErrorAction SilentlyContinue | ForEach-Object { $items.Add(@($_.FullName, "mariadb\$($_.Name)")) }
        $items.Add(@($Config.StateFile, "install-state.json"))
        $items.Add(@((Join-Path $Config.ApacheDir "conf\httpd.conf"), "apache-conf\httpd.conf"))
        Get-ChildItem (Join-Path $Config.ApacheDir "conf\extra") -File -Filter "parsvt-*.conf" -ErrorAction SilentlyContinue | ForEach-Object { $items.Add(@($_.FullName, "apache-conf\extra\$($_.Name)")) }
        if ($Config.PHPVersion) { $items.Add(@((Join-Path (Get-PHPDir $Config.PHPVersion) "php.ini"), "php\php-$($Config.PHPVersion).ini")) }
        # .htaccess files decide REST API routing and error pages; they hold no secrets.
        $items.Add(@((Join-Path $Config.WebRoot ".htaccess"), "htaccess\root.htaccess"))
        $items.Add(@((Join-Path $Config.WebRoot "modules\ParsVT\ws\.htaccess"), "htaccess\ws.htaccess"))

        $never = @($Config.CredentialsFile, (Join-Path $Config.BackupScriptDir "backup.cnf")) | ForEach-Object { $_.ToLowerInvariant() }
        $copied = 0
        foreach ($it in $items) {
            $src = $it[0]
            if (-not $src -or -not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
            if ($never -contains $src.ToLowerInvariant() -or (Split-Path $src -Leaf) -eq "config.inc.php") { continue }
            try { Copy-LogTail -Source $src -Dest (Join-Path $work $it[1]); $copied++ }
            catch { Add-Content -Path (Join-Path $work "skipped.txt") -Value "$src : $($_.Exception.Message)" }
        }
        Write-TextFile (Join-Path $work "system-info.txt") (Get-SupportSystemInfo -Reason $Reason -Code $Code)

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $zip) { Remove-Item $zip -Force }
        # Entries are added one by one with "/" separators: ZipFile.CreateFromDirectory
        # in PowerShell 5.1 (.NET Framework legacy mode) writes "\", which
        # non-Windows unzip tools show as one flat file name.
        $root = (Resolve-Path $work).Path.TrimEnd('\', '/')
        $fs = [IO.File]::Open($zip, [IO.FileMode]::Create)
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in Get-ChildItem $work -Recurse -File -Force) {
                $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
            }
        } finally { $za.Dispose(); $fs.Dispose() }
        Write-Ok "Support report: $zip ($copied files, $([Math]::Round((Get-Item $zip).Length / 1KB)) KB)"
        return $zip
    } catch {
        Write-Warn "Could not create the support report: $($_.Exception.Message)"
        return ""
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Report + Persian message box, at most once per run.
function Invoke-FailureReport {
    param([string]$Reason = "", [int]$Code = 1)
    if ($script:FailureReported) { return }
    $script:FailureReported = $true
    if ($DryRun) { Write-Warn "Dry run: no support report is written."; return }
    Write-Step "Creating a support report..."
    $zip = New-SupportBundle -Reason $Reason -Code $Code
    $detail = "$Reason".Trim()
    if (-not $detail) { $detail = "Exit code $Code. See the console window." }
    if ($zip) {
        $text = $script:FaText.ErrorBody + "`r`n`r`n" + $script:FaText.ReportPath + "`r`n" + $zip
    } else {
        $text = $script:FaText.NoReport + "`r`n" + $Config.LogDir
    }
    $text += "`r`n`r`n" + $script:FaText.Detail + "`r`n" + (Protect-LogText $detail)
    [void](Show-FaMessage -Title $script:FaText.ErrorTitle -Text $text -Icon "Error")
    if ($zip -and $Quick) {
        try { Start-Process -FilePath (Join-Path $env:SystemRoot "explorer.exe") -ArgumentList "/select,`"$zip`"" } catch { }
    }
}

# =============================================================================
# Install state (paths, port, domain) - read by Repair and ionCube-only
# =============================================================================

$script:StateKeys = @("ApacheDir", "WebRoot", "ApachePort", "Domain", "PHPVersion", "VtigerVersion", "DBName", "ServerIP", "SslEnabled", "PhpMyAdminRestricted")

function Save-InstallState {
    if ($DryRun) { return }
    New-Dir $Config.BackupScriptDir
    Set-DirAcl -Path $Config.BackupScriptDir
    $o = [ordered]@{ Version = "2.11"; Saved = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    foreach ($k in $script:StateKeys) { $o[$k] = $Config[$k] }
    Write-TextFile $Config.StateFile ((New-Object PSObject -Property $o) | ConvertTo-Json)
}

# Returns the Apache directory the Apache2.4 service runs from, or "".
function Get-ApacheDirFromService {
    $s = Get-WmiObject Win32_Service -Filter "Name='$($Config.ApacheService)'" -ErrorAction SilentlyContinue
    if (-not $s -or -not $s.PathName) { return "" }
    $exe = $s.PathName
    if ($exe -match '^"([^"]+)"') { $exe = $Matches[1] } else { $exe = ($exe -split '\s+')[0] }
    return (Split-Path (Split-Path $exe -Parent) -Parent)
}

# Returns the MariaDB folder the MariaDB service runs from, or "".
function Get-MariaDBDirFromService {
    $s = Get-WmiObject Win32_Service -Filter "Name='MariaDB'" -ErrorAction SilentlyContinue
    if (-not $s -or -not $s.PathName) { return "" }
    $exe = $s.PathName
    if ($exe -match '^"([^"]+)"') { $exe = $Matches[1] } else { $exe = ($exe -split '\s+')[0] }
    return (Split-Path (Split-Path $exe -Parent) -Parent)
}

function Import-InstallState {
    $mdir = Get-MariaDBDirFromService
    if ($mdir -and (Test-Path (Join-Path $mdir "bin\mysql.exe"))) { $Config.MariaDBDir = $mdir }
    if (Test-Path $Config.StateFile) {
        try {
            $s = Get-Content $Config.StateFile -Raw | ConvertFrom-Json
            foreach ($k in $script:StateKeys) {
                if ($null -ne $s.$k -and "$($s.$k)" -ne "") { $Config[$k] = $s.$k }
            }
            $Config.ApachePort = [int]$Config.ApachePort
            $Config.VtigerVersion = [int]$Config.VtigerVersion
            return
        } catch { Write-Warn "Cannot read $($Config.StateFile): $($_.Exception.Message)" }
    }
    # Installs made by 1.x have no state file: take what Apache itself says.
    $dir = Get-ApacheDirFromService
    if ($dir) {
        $Config.ApacheDir = $dir
        $Config.WebRoot = Join-Path $dir "htdocs"
    }
    $base = Join-Path $Config.ApacheDir "conf\extra\parsvt-base.conf"
    if (Test-Path $base) {
        $c = Get-Content $base -Raw
        if ($c -match '(?m)^\s*Listen\s+(?:[\d\.]+:)?(\d+)') { $Config.ApachePort = [int]$Matches[1] }
        if ($c -match '(?m)^\s*DocumentRoot\s+"([^"]+)"') { $Config.WebRoot = ($Matches[1] -replace '/', '\') }
    }
}

# =============================================================================
# Credentials file (written as soon as each secret exists, so a failed run
# never loses the generated MariaDB root password)
# =============================================================================

function Save-CredentialsFile {
    if ($DryRun) { return }
    $lines = @(
        "ParsVT CRM - generated by parsvt.ps1 v2.11",
        "Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "CRM URL: $(Get-CrmUrl)"
    )
    if ($Config.Domain)        { $lines += "Domain: $($Config.Domain)" }
    if ($Config.AdminPassword) { $lines += "CRM Username: admin"; $lines += "CRM Password: $($Config.AdminPassword)" }
    if ($Config.PHPVersion)    { $lines += "PHP: $($Config.PHPVersion)" }
    $lines += "Apache: $($Config.ApacheDir) (port $($Config.ApachePort))"
    $lines += "Web root: $($Config.WebRoot)"
    $lines += "Database: $($Config.DBName)"
    $lines += "Database user: $($Config.DBUser)"
    if ($Config.MySQLPassword) { $lines += "MariaDB password: $($Config.MySQLPassword)" }
    $lines += "Backup script: $($Config.BackupScriptDir)\backup.ps1"
    $lines += "Restore script: $($Config.BackupScriptDir)\restore.ps1"
    $lines += "Backup directory: $($Config.BackupDir)"
    if (Test-Path (Join-Path (Get-PhpMyAdminDir) "index.php")) {
        $lines += "phpMyAdmin: $(Get-PhpMyAdminUrl) (log in with the MariaDB user and password above)"
        if ($Config.PhpMyAdminRestricted) { $lines += "phpMyAdmin access: localhost and private networks only" } else { $lines += "phpMyAdmin access: anyone (not restricted)" }
    }
    if (-not (Test-Path $Config.CredentialsFile)) { New-Item -ItemType File -Path $Config.CredentialsFile -Force | Out-Null }
    Set-FileAcl-AdminsOnly $Config.CredentialsFile
    Write-TextFile $Config.CredentialsFile (($lines -join "`r`n") + "`r`n")
}

function Read-SavedMySQLPassword {
    if (-not (Test-Path $Config.CredentialsFile)) { return "" }
    foreach ($l in (Get-Content $Config.CredentialsFile)) {
        if ($l -match '^MariaDB (root )?password:\s*(.+)$') { return $Matches[2].Trim() }
    }
    return ""
}

# =============================================================================
# Menu
# =============================================================================

function Show-Menu {
    Write-Host ""
    Write-Host "Please enter the item number you want to use:" -ForegroundColor Cyan
    Write-Host "  [1] Install ParsVT CRM - Vtiger 8 / PHP 8.3 (recommended)" -ForegroundColor Cyan
    Write-Host "  [2] Install ParsVT CRM - Vtiger 7 / PHP 7.4 (DEPRECATED)"  -ForegroundColor Yellow
    Write-Host "  [3] Repair installation"                                  -ForegroundColor Cyan
    Write-Host "  [4] Update ionCube loader only"                           -ForegroundColor Cyan
    Write-Host "  [0] Cancel"                                               -ForegroundColor Yellow
    Write-Host ""
    return Read-Host "Please select an action (0-4)"
}

# =============================================================================
# License
# =============================================================================

function Get-LicenseInfo {
    for ($i = 0; $i -lt 4; $i++) {
        # Keys pasted from e-mail or messengers often carry invisible characters
        # (zero-width space, BOM, RTL marks) or quotes; drop them.
        $key = (Read-Host "Please enter your ParsVT CRM license key") -replace '[\u200B-\u200F\u202A-\u202E\u2060\uFEFF"''\s]', ''
        $len = $key.Length
        $okLen = ($len -eq 25 -or $len -eq 26)
        $okPrefix = ($key.StartsWith("ParsVT", [StringComparison]::OrdinalIgnoreCase) -or $key.StartsWith("Cloud", [StringComparison]::OrdinalIgnoreCase))
        if ($okLen -and $okPrefix) { $Config.LicenseKey = $key; return $true }
        $why = @()
        if (-not $okLen)    { $why += "$len characters, expected 25 or 26" }
        if (-not $okPrefix) { $why += "must start with ParsVT or Cloud" }
        Write-Err ("Invalid license key format (" + ($why -join "; ") + ").")
    }
    Write-Err "Too many invalid attempts."
    return $false
}

function Get-ServerIP {
    $ips = @("127.0.0.1")
    $addrs = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
    foreach ($a in $addrs) { foreach ($ip in $a.IPAddress) { if ($ip -match '^\d+\.\d+\.\d+\.\d+$') { $ips += $ip } } }
    $ips = @($ips | Select-Object -Unique)
    if ($ips.Count -eq 1) { $Config.ServerIP = $ips[0]; return }
    if ($Quick) {
        # The address of the adapter with a default gateway (the one the
        # license server sees); otherwise the first non-loopback address.
        $gw = @($addrs | Where-Object { $_.DefaultIPGateway } | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
        if ($gw.Count -gt 0) { $Config.ServerIP = $gw[0] } else { $Config.ServerIP = $ips[1] }
        Write-Host "`nQuick mode: ParsVT CRM will be installed on $($Config.ServerIP)"
        return
    }
    Write-Host "`nAvailable IP addresses:"
    for ($i = 0; $i -lt $ips.Count; $i++) { Write-Host "  # $i - $($ips[$i])" }
    $sel = Read-Host "Please select an IP address"
    if ($sel -match '^\d+$' -and [int]$sel -lt $ips.Count) { $Config.ServerIP = $ips[[int]$sel] }
    else { $Config.ServerIP = $ips[0] }
    Write-Host "`nParsVT CRM will be installed on $($Config.ServerIP)"
}

function Invoke-LicenseCheck {
    Write-Step "Validating license..."
    if ($DryRun) { Write-Host "  [DRY] POST to $($Config.LicenseEndpoint)"; return $true }
    $body = "licenseid=$([System.Uri]::EscapeDataString($Config.LicenseKey))&serverip=$([System.Uri]::EscapeDataString($Config.ServerIP))"
    try {
        $r = Invoke-WebRequest -Uri $Config.LicenseEndpoint -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -TimeoutSec 30
    } catch {
        Write-Err "License check failed: $($_.Exception.Message)"
        return $false
    }
    $parts = "$($r.Content)".Trim() -split ';'
    if ($parts[0] -ne "Active" -or $parts.Count -lt 3 -or [string]::IsNullOrWhiteSpace($parts[2])) {
        Write-Err "License status: $($parts[0])"
        if ($parts.Count -ge 2) { Write-Err $parts[1] }
        return $false
    }
    # The extensions zip is unpacked into the web root and executed, so only
    # accept it from aweb.co (or a subdomain).
    $u = $null
    if (-not [Uri]::TryCreate($parts[2].Trim(), [UriKind]::Absolute, [ref]$u) -or
        -not ($u.Host -eq $Config.PrimarySite -or $u.Host.EndsWith("." + $Config.PrimarySite))) {
        Write-Err "License server returned an unexpected extensions URL host. Aborting."
        return $false
    }
    $Config.ExtToken = $parts[1].Trim()
    $Config.ExtURL   = $u.AbsoluteUri
    Write-Ok "License active."
    return $true
}

# =============================================================================
# Interactive settings: domain, install paths, web server port
# =============================================================================

function Test-DomainName {
    param([string]$Name)
    return ($Name -match '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' -and $Name.Length -le 253)
}

function Get-DomainName {
    if ($Quick) {
        # No domain on a new server; a re-run keeps the domain already saved.
        if ($Config.Domain) { Write-Ok "Quick mode: keeping domain $($Config.Domain)." } else { Write-Ok "Quick mode: no domain." }
        return
    }
    for ($i = 0; $i -lt 4; $i++) {
        $prompt = "Please enter your domain name (leave blank to skip)"
        if ($Config.Domain) { $prompt = "Please enter your domain name (leave blank to keep $($Config.Domain), '-' to remove)" }
        $d = (Read-Host $prompt).Trim().ToLowerInvariant()
        if ($d -eq "") { return }
        if ($d -eq "-") { $Config.Domain = ""; return }
        $d = ($d -replace '^https?://', '').TrimEnd('/').TrimEnd('.')
        if (Test-DomainName $d) { $Config.Domain = $d; Write-Ok "Domain: $d"; return }
        Write-Err "Invalid domain name. Use letters, digits, '-' and dots; write non-English (IDN) names in punycode (xn--...)."
    }
    Write-Warn "No valid domain entered; continuing without a domain."
    $Config.Domain = ""
}

# Absolute local path, plain ASCII, no characters that break Apache or cmd.exe.
function Test-InstallPath {
    param([string]$Path, [string]$What)
    if ($Path -notmatch '^[A-Za-z]:\\[\x20-\x7E]+$' -or $Path -match '["%;<>|*?]' -or $Path -match '\\\\' -or $Path.EndsWith("\")) {
        Write-Err "$What must be an absolute local path in English characters, without double quotes, % ; < > | * ? or a trailing backslash (example: D:\Apache24)."
        return $false
    }
    if (-not (Test-Path ($Path.Substring(0, 3)))) { Write-Err "Drive $($Path.Substring(0, 2)) does not exist."; return $false }
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        if ($DryRun) { return $true }
        try { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        catch { Write-Err "Cannot create $parent : $($_.Exception.Message)"; return $false }
    }
    return $true
}

function Test-IsSubPath {
    param([string]$Child, [string]$Parent)
    $c = $Child.TrimEnd('\') + '\'; $p = $Parent.TrimEnd('\') + '\'
    return $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
}

function Get-InstallPaths {
    $svcDir = Get-ApacheDirFromService
    if ($svcDir) {
        Write-Warn "The $($Config.ApacheService) service already runs Apache from $svcDir; that directory is used."
        $Config.ApacheDir = $svcDir
    } elseif ($Quick) {
        if (-not (Test-InstallPath $Config.ApacheDir "The Apache directory")) { Stop-Install "Quick mode: cannot use $($Config.ApacheDir)." }
    } else {
        for ($i = 0; ; $i++) {
            if ($i -ge 4) { Stop-Install "Too many invalid paths." }
            $a = (Read-Host "Apache base directory (default: $($Config.ApacheDir))").Trim().TrimEnd('\')
            if ($a -eq "") { $a = $Config.ApacheDir }
            if (Test-InstallPath $a "The Apache directory") { $Config.ApacheDir = $a; break }
        }
    }
    $defaultWeb = $Config.WebRoot
    if (-not (Test-IsSubPath $defaultWeb $Config.ApacheDir) -and $defaultWeb -like "*\htdocs") { $defaultWeb = Join-Path $Config.ApacheDir "htdocs" }
    for ($i = 0; ; $i++) {
        if ($i -ge 4) { Stop-Install "Too many invalid paths." }
        if ($Quick -and $i -gt 0) { Stop-Install "Quick mode: the web root $defaultWeb cannot be used (see the error above)." }
        if ($Quick) { $w = $defaultWeb } else { $w = (Read-Host "Web root directory (default: $defaultWeb)").Trim().TrimEnd('\') }
        if ($w -eq "") { $w = $defaultWeb }
        if (-not (Test-InstallPath $w "The web root")) { continue }
        $bad = $false
        foreach ($p in @($Config.PHPBaseDir, $Config.BackupDir, $Config.LogDir, $Config.BackupScriptDir, $Config.MariaDBDir)) {
            if ((Test-IsSubPath $w $p) -or (Test-IsSubPath $p $w)) { Write-Err "The web root cannot be inside or contain $p."; $bad = $true }
        }
        if ($w -eq $Config.ApacheDir -or (Test-IsSubPath $Config.ApacheDir $w)) { Write-Err "The web root cannot be the Apache directory or contain it."; $bad = $true }
        foreach ($sub in @("bin", "conf", "logs", "modules")) {
            if (Test-IsSubPath $w (Join-Path $Config.ApacheDir $sub)) { Write-Err "The web root cannot be inside $($Config.ApacheDir)\$sub."; $bad = $true }
        }
        if (-not $bad) { $Config.WebRoot = $w; break }
    }
    Write-Ok "Apache: $($Config.ApacheDir)   Web root: $($Config.WebRoot)"
}

function Get-ApachePort {
    if ($Quick) {
        # Port 80 on a new server, the saved port on a re-run. A busy port
        # stops the install: a non-technical user would not know which port
        # the CRM ended up on.
        $port = [int]$Config.ApachePort
        $owner = Get-PortOwner $port
        if ($owner -and $owner -ne "httpd") {
            Stop-Install "Port $port is used by $owner. Stop that program (for IIS: Stop-Service W3SVC; Set-Service W3SVC -StartupType Disabled), or run parsvt.ps1 without -Quick to choose another port." 4
        }
        Write-Ok "Quick mode: web server port $port."
        return
    }
    for ($i = 0; ; $i++) {
        if ($i -ge 5) { Stop-Install "Too many invalid port entries." }
        $a = (Read-Host "Please enter the web server port (default: $($Config.ApachePort))").Trim()
        if ($a -eq "") { $a = "$($Config.ApachePort)" }
        if ($a -notmatch '^\d{1,5}$' -or [int]$a -lt 1 -or [int]$a -gt 65535) { Write-Err "Enter a number between 1 and 65535."; continue }
        $port = [int]$a
        if ($port -eq 443) { Write-Err "Port 443 is reserved for HTTPS. Choose another port."; continue }
        if ($port -eq 3306) { Write-Err "Port 3306 is used by MariaDB. Choose another port."; continue }
        $owner = Get-PortOwner $port
        if ($owner -eq "httpd") {
            Write-Warn "Port $port is already served by Apache (re-run); keeping it."
        } elseif (-not (Test-PortFree $port)) {
            if (-not $owner) { $owner = "another program" }
            Write-Warn "Port $port is in use by $owner. Choose another port, or stop that service first."
            continue
        }
        $Config.ApachePort = $port
        if ($port -ne 80) { Write-Warn "Using port $port. Let's Encrypt certificates still need port 80 reachable (see the SSL step)." }
        Write-Ok "Web server port: $port"
        return
    }
}

# =============================================================================
# Prerequisites
# =============================================================================

# Optional, default "no". Path exclusions are recursive, so only folders that
# hold binaries, backups or database files are offered: the web root (and
# with it storage\, where CRM users upload attachments) stays scanned.
function Add-DefenderExclusions {
    if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) { return }   # Defender not installed
    $paths = @((Join-Path $Config.ApacheDir "bin"), (Join-Path $Config.ApacheDir "modules"), $Config.PHPBaseDir,
               $Config.BackupDir, (Join-Path $Config.MariaDBDir "data"))
    Write-Host ""
    Write-Host "Windows Defender exclusions (faster PHP, backups and MariaDB; the web root is NOT excluded):"
    $paths | ForEach-Object { Write-Host "    $_" }
    if ($Quick) { $a = "y"; Write-Host "  Quick mode: adding them." }
    else { $a = Read-Host "Add these folders to Windows Defender exclusions? (recommended, y/n)" }
    if ($a -notmatch '^[yY]') { return }
    if ($DryRun) { Write-Host "  [DRY] Add-MpPreference -ExclusionPath ..."; return }
    $added = 0
    foreach ($p in $paths) {
        try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; $added++ } catch { $err = $_.Exception.Message }
    }
    if ($added -gt 0) { Write-Ok "Defender exclusions added: $added of $($paths.Count)." }
    elseif ($err) { Write-Warn "Defender exclusions not added (Defender inactive or managed by policy): $err" }
}

function Install-VCRedist {
    # File presence alone is not enough: older 2015/2017 runtimes install the
    # same vcruntime140.dll, but Apache VS17 and PHP vs16 need a newer one.
    $min = [Version]$Config.VCRedistMinVersion
    $dll = Join-Path $env:SystemRoot "System32\vcruntime140.dll"
    $fileOk = $false
    if (Test-Path $dll) {
        $fv = (Get-Item $dll).VersionInfo
        $v = New-Object Version($fv.FileMajorPart, $fv.FileMinorPart, $fv.FileBuildPart)
        $fileOk = ($v -ge $min)
        if ($fileOk) { Write-Ok "Visual C++ runtime $($fv.FileVersion) present ($dll)."; return $true }
        Write-Warn "vcruntime140.dll $($fv.FileVersion) is older than $min; updating."
    }
    Write-Step "Installing the Visual C++ x64 runtime $min or newer (needed by Apache and PHP)..."
    $sources = @($Config.VCRedistURL, $Config.VCRedistFallbackURL) | Where-Object { $_ } | Select-Object -Unique
    $tooOld = @()
    foreach ($url in $sources) {
        $exe = Join-Path $env:TEMP $Config.Downloads.VCRedist.File
        $sha = ""; $mirror = ""
        if ($url -eq $Config.VCRedistURL) { $sha = $Config.Downloads.VCRedist.Sha256; $mirror = $Config.Downloads.VCRedist.File }
        if (-not (Invoke-Download -Url $url -OutFile $exe -Sha256 $sha -MirrorName $mirror)) { continue }
        if ($DryRun) { return $true }
        try {
            # vc_redist.x64.exe carries the runtime version it installs
            # (FileVersion 14.44.35211.0 installs vcruntime140.dll 14.44.35211).
            $ev = (Get-Item $exe).VersionInfo
            if ($ev.FileMajorPart -gt 0) {
                $exeVer = New-Object Version($ev.FileMajorPart, $ev.FileMinorPart, $ev.FileBuildPart)
                Write-Host "  vc_redist.x64.exe from $url is version $exeVer"
                if ($exeVer -lt $min) {
                    Write-Warn "That file is older than $min; it is not run."
                    $tooOld += "$url ($exeVer)"
                    continue
                }
            }
            $r = Invoke-Native $exe @("/install", "/quiet", "/norestart") -SuccessCodes @(0, 1638, 3010) -Step "vc_redist.x64.exe" -AllowFailure
        } finally { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
        switch ($r.ExitCode) {
            0       { Write-Ok "vc_redist.x64.exe finished." }
            1638    { Write-Ok "vc_redist.x64.exe: a newer Visual C++ runtime is already installed." }
            3010    { Write-Warn "vc_redist.x64.exe finished; Windows asks for a reboot. Continuing." }
            default { Write-Err "vc_redist.x64.exe failed with exit code $($r.ExitCode)."; continue }
        }
        # The exit code does not prove the version: an older vc_redist.x64.exe
        # also ends with 0 or 1638.
        if (-not (Test-Path $dll)) { Write-Err "vcruntime140.dll is still missing after vc_redist.x64.exe."; continue }
        $fv = (Get-Item $dll).VersionInfo
        $v = New-Object Version($fv.FileMajorPart, $fv.FileMinorPart, $fv.FileBuildPart)
        if ($v -ge $min) { break }
        Write-Err "vcruntime140.dll is $($fv.FileVersion) after vc_redist.x64.exe from $url, older than $min."
    }
    if (-not $fv -or $v -lt $min) {
        if ($tooOld.Count) { Write-Err "Too old: $($tooOld -join '; '). Upload the current Visual C++ 2017-2026 x64 redistributable ($($Config.VCRedistFallbackURL)) as $($Config.VCRedistURL)." }
        Write-Err "Visual C++ runtime $min or newer could not be installed; the Apache build needs it."
        return $false
    }
    Write-Ok "Visual C++ runtime $($fv.FileVersion) installed."
    return $true
}

# =============================================================================
# Apache
# =============================================================================

function Install-Apache {
    $httpd = Join-Path $Config.ApacheDir "bin\httpd.exe"
    $svcDir = Get-ApacheDirFromService
    if ($svcDir -and $svcDir -ne $Config.ApacheDir) {
        Write-Err "Service $($Config.ApacheService) already points to $svcDir, not $($Config.ApacheDir)."
        return $false
    }
    if (Test-Path $httpd) {
        Write-Ok "Apache binaries present at $($Config.ApacheDir)."
    } else {
        Write-Step "Installing Apache 2.4 into $($Config.ApacheDir)..."
        $zip = Join-Path $env:TEMP $Config.Downloads.Apache.File
        if (-not (Invoke-ConfiguredDownload "Apache" $zip)) { return $false }
        if ($DryRun) { return $true }
        $extract = Join-Path $env:TEMP "parsvt-apache-extract"
        Expand-ZipFile $zip $extract
        $inner = Get-ChildItem $extract -Directory | Where-Object { Test-Path (Join-Path $_.FullName "bin\httpd.exe") } | Select-Object -First 1
        if (-not $inner) { Write-Err "Unexpected Apache archive structure (no */bin/httpd.exe)."; return $false }
        if (Test-Path $Config.ApacheDir) {
            # Test-InstallPath creates the web root's parent while checking the
            # paths, so on a new server this folder exists but holds no files.
            $anyFile = Get-ChildItem $Config.ApacheDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $anyFile) {
                Remove-Item $Config.ApacheDir -Recurse -Force
            } else {
                $old = "$($Config.ApacheDir).incomplete-$(Get-Date -Format 'yyyyMMddHHmmss')"
                Write-Warn "Moving incomplete $($Config.ApacheDir) to $old"
                Move-Item $Config.ApacheDir $old
            }
        }
        Move-Item $inner.FullName $Config.ApacheDir
        Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Apache extracted to $($Config.ApacheDir)."
    }
    if ($DryRun) { return $true }

    Set-DirAcl -Path $Config.ApacheDir -UsersRead

    # SRVROOT must match the real location, or every relative path in httpd.conf breaks.
    $mainConf = Join-Path $Config.ApacheDir "conf\httpd.conf"
    $c = Get-Content $mainConf -Raw
    $srv = ConvertTo-ApachePath $Config.ApacheDir
    $c = $c -replace '(?m)^Define SRVROOT .*$', "Define SRVROOT `"$srv`""
    Write-TextFile $mainConf $c

    if (-not (Install-ModFcgid)) { return $false }

    if (-not (Get-Service -Name $Config.ApacheService -ErrorAction SilentlyContinue)) {
        $r = Invoke-Native $httpd @("-k", "install", "-n", $Config.ApacheService) -WorkDir (Join-Path $Config.ApacheDir "bin") -AllowFailure
        if (-not (Get-Service -Name $Config.ApacheService -ErrorAction SilentlyContinue)) {
            Write-Err "Apache service install failed: $($r.All)"
            return $false
        }
    }
    Set-Service -Name $Config.ApacheService -StartupType Automatic
    Write-Ok "Apache service '$($Config.ApacheService)' registered."
    return $true
}

function Install-ModFcgid {
    $so = Join-Path $Config.ApacheDir "modules\mod_fcgid.so"
    if (Test-Path $so) { return $true }
    Write-Step "Installing mod_fcgid..."
    $zip = Join-Path $env:TEMP $Config.Downloads.ModFcgid.File
    if (-not (Invoke-ConfiguredDownload "ModFcgid" $zip)) { return $false }
    if ($DryRun) { return $true }
    $extract = Join-Path $env:TEMP "parsvt-fcgid-extract"
    Expand-ZipFile $zip $extract
    $found = Get-ChildItem $extract -Recurse -Filter "mod_fcgid.so" | Select-Object -First 1
    if (-not $found) { Write-Err "mod_fcgid.so not found in the archive."; return $false }
    Copy-Item $found.FullName $so -Force
    Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "mod_fcgid installed."
    return $true
}

function Test-ApacheConfig {
    $r = Invoke-Native (Join-Path $Config.ApacheDir "bin\httpd.exe") @("-t") -WorkDir (Join-Path $Config.ApacheDir "bin") -AllowFailure
    if (-not $r.Ok) { Write-Err "Apache configuration test failed:`n$($r.All)"; return $false }
    return $true
}

function Stop-Apache {
    if ($DryRun) { return }
    $s = Get-Service -Name $Config.ApacheService -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Stopped") { Stop-Service $Config.ApacheService -Force; $s.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(60)) }
}

# Tests the config first, so a broken httpd.conf never takes a running site down.
function Restart-Apache {
    if ($DryRun) { Write-Host "  [DRY] Restart $($Config.ApacheService)" -ForegroundColor DarkGray; return $true }
    if (-not (Get-Service -Name $Config.ApacheService -ErrorAction SilentlyContinue)) { Write-Err "Apache service is not installed."; return $false }
    if (-not (Test-ApacheConfig)) { return $false }
    try { Restart-Service $Config.ApacheService -Force } catch { Write-Err "Apache did not restart: $($_.Exception.Message)" }
    $port = [int]$Config.ApachePort
    for ($i = 0; $i -lt 15; $i++) { if (Test-PortListening $port) { break }; Start-Sleep -Seconds 1 }
    if ((Get-Service $Config.ApacheService).Status -ne "Running" -or -not (Test-PortListening $port)) {
        Write-Err "Apache is not running on port $port. Last lines of the error log:"
        $log = Join-Path $Config.ApacheDir "logs\error.log"
        if (Test-Path $log) { Get-Content $log -Tail 15 | ForEach-Object { Write-Host "    $_" } }
        return $false
    }
    Write-Ok "Apache is running on port $port."
    return $true
}

function Add-HttpdInclude {
    param([string]$ConfName)
    $mainConf = Join-Path $Config.ApacheDir "conf\httpd.conf"
    $c = Get-Content $mainConf -Raw
    $line = "Include conf/extra/$ConfName"
    if ($c -notmatch ("(?m)^" + [regex]::Escape($line) + "\s*$")) {
        $c = $c.TrimEnd() + "`r`n$line`r`n"
        Write-TextFile $mainConf $c
    }
}

# =============================================================================
# PHP
# =============================================================================

# Extension module name -> DLL names to try (7.4 ships gd as php_gd2.dll).
# Modules with no DLL here (xml, bcmath on Windows builds) are compiled in.
$script:PHPExtensions = [ordered]@{
    "mysqli" = @("mysqli"); "pdo_mysql" = @("pdo_mysql"); "curl" = @("curl"); "gd" = @("gd", "gd2")
    "mbstring" = @("mbstring"); "openssl" = @("openssl"); "zip" = @("zip"); "fileinfo" = @("fileinfo")
    "imap" = @("imap"); "intl" = @("intl"); "soap" = @("soap"); "bcmath" = @("bcmath"); "exif" = @("exif")
    # Also installed by the Linux installer (php-ldap, php-odbc, php-sockets,
    # php-xmlrpc on 7.x): LDAP login, the SQL Server / ODBC connectors.
    "ldap" = @("ldap"); "odbc" = @("odbc"); "pdo_odbc" = @("pdo_odbc"); "sockets" = @("sockets"); "xmlrpc" = @("xmlrpc")
}
# Loaded when the PHP build ships the DLL; a missing one is a warning, not a failure.
$script:PHPOptionalModules = @("exif", "ldap", "odbc", "pdo_odbc", "sockets", "xmlrpc")
$script:PHPRequiredModules = @("mysqli", "pdo_mysql", "curl", "gd", "mbstring", "openssl", "xml", "zip", "fileinfo", "imap", "intl", "soap", "bcmath")

# Rebuilds the "ParsVT managed" block at the end of php.ini. Later directives
# win in php.ini, so the block overrides php.ini-production without regex
# surgery. ionCube is the first zend_extension, as the loader requires.
function Write-PHPIni {
    param([string]$Version, [string]$PHPDir)
    $ini  = Join-Path $PHPDir "php.ini"
    $prod = Join-Path $PHPDir "php.ini-production"
    if (-not (Test-Path $ini)) {
        if (Test-Path $prod) { Copy-Item $prod $ini } else { Write-TextFile $ini "" }
    }
    $c = Get-Content $ini -Raw
    if ($null -eq $c) { $c = "" }
    $c = [regex]::Replace($c, '(?s)\r?\n?; >>> ParsVT managed.*?; <<< ParsVT managed[^\n]*\n?', '')

    $ext = ConvertTo-ApachePath (Join-Path $PHPDir "ext")
    $log = ConvertTo-ApachePath (Join-Path $Config.LogDir "php-$Version-error.log")
    $b = New-Object System.Collections.Generic.List[string]
    $b.Add("; >>> ParsVT managed - rewritten by parsvt.ps1, edit outside this block")
    $b.Add("extension_dir = `"$ext`"")
    $ion = Join-Path $PHPDir "ext\ioncube_loader_win_$Version.dll"
    if (Test-Path $ion) { $b.Add("zend_extension = `"$(ConvertTo-ApachePath $ion)`"") }
    if (Test-Path (Join-Path $PHPDir "ext\php_opcache.dll")) { $b.Add("zend_extension = opcache") }
    foreach ($m in $script:PHPExtensions.Keys) {
        foreach ($dll in $script:PHPExtensions[$m]) {
            if (Test-Path (Join-Path $PHPDir "ext\php_$dll.dll")) {
                # drop an uncommented duplicate from php.ini-production, if any
                $c = $c -replace "(?m)^[ \t]*extension[ \t]*=[ \t]*(php_)?$dll(\.dll)?[ \t]*(?=\r?$)", ";`$0"
                $b.Add("extension = $dll")
                break
            }
        }
    }
    $settings = [ordered]@{
        "max_execution_time" = "600"; "max_input_time" = "600"; "memory_limit" = "512M"
        "max_input_vars" = "10000"; "post_max_size" = "128M"; "upload_max_filesize" = "128M"
        "date.timezone" = "Asia/Tehran"; "display_errors" = "Off"; "display_startup_errors" = "Off"
        "log_errors" = "On"; "error_log" = "`"$log`""; "expose_php" = "Off"; "output_buffering" = "4096"
        "short_open_tag" = "On"; "default_socket_timeout" = "600"; "cgi.fix_pathinfo" = "1"
        "session.gc_maxlifetime" = "21600"; "session.cookie_httponly" = "1"; "session.use_strict_mode" = "1"
        # Same as the Linux installer: notices and warnings are not logged
        # (Vtiger produces thousands of them and they hide real errors).
        "error_reporting" = "E_ALL & ~E_NOTICE & ~E_WARNING & ~E_DEPRECATED & ~E_STRICT"
        "opcache.enable" = "1"; "opcache.memory_consumption" = "128"; "opcache.max_accelerated_files" = "20000"
        "opcache.validate_timestamps" = "1"; "opcache.revalidate_freq" = "2"
    }
    foreach ($k in $settings.Keys) { $b.Add("$k = $($settings[$k])") }
    $b.Add("; <<< ParsVT managed")
    $c = $c.TrimEnd() + "`r`n`r`n" + ($b -join "`r`n") + "`r`n"
    Write-TextFile $ini $c
}

function Test-PHPModules {
    param([string]$PHPDir)
    $php = Join-Path $PHPDir "php.exe"
    $r = Invoke-Native $php @("-c", (Join-Path $PHPDir "php.ini"), "-m") -Step "php -m" -AllowFailure
    if (-not $r.Ok) { Write-Err "php.exe -m failed: $($r.All)"; return $false }
    $loaded = @($r.Output -split "\r?\n" | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $missing = @($script:PHPRequiredModules | Where-Object { $loaded -notcontains $_ })
    if ($missing.Count -gt 0) { Write-Err "PHP modules not loaded: $($missing -join ', ')"; return $false }
    if ($loaded -notcontains "zend opcache") { Write-Warn "OPcache is not loaded (performance only)." }
    # Optional modules whose DLL is present but did not load (for example a
    # missing dependency DLL) are reported, not fatal.
    $notLoaded = @($script:PHPOptionalModules | Where-Object {
        $m = $_; $loaded -notcontains $m -and @($script:PHPExtensions[$m] | Where-Object { Test-Path (Join-Path $PHPDir "ext\php_$_.dll") }).Count -gt 0 })
    if ($notLoaded.Count -gt 0) { Write-Warn "Optional PHP modules present but not loaded: $($notLoaded -join ', '). See $(Join-Path $Config.LogDir 'php-*-error.log')." }
    return $true
}

function Install-PHP {
    param([string]$Version, [string]$DownloadName)
    $PHPDir = Get-PHPDir $Version
    if (Test-Path (Join-Path $PHPDir "php-cgi.exe")) {
        Write-Ok "PHP $Version present at $PHPDir."
    } else {
        Write-Step "Installing PHP $Version (NTS)..."
        $zip = Join-Path $env:TEMP $Config.Downloads[$DownloadName].File
        if (-not (Invoke-ConfiguredDownload $DownloadName $zip)) { return $false }
        if ($DryRun) { return $true }
        Expand-ZipFile $zip $PHPDir
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
    if ($DryRun) { return $true }
    New-Dir $Config.LogDir
    Write-PHPIni -Version $Version -PHPDir $PHPDir
    if (-not (Test-PHPModules $PHPDir)) { return $false }
    Write-Ok "PHP $Version configured."
    return $true
}

# =============================================================================
# ionCube
# =============================================================================

# Parses "php -i" text: Thread Safety and PHP Extension Build
# (e.g. "API20190902,NTS,VC15" for 7.4, "API20230831,NTS,VS16" for 8.3).
function Get-PHPBuildInfo {
    param([string]$PhpInfoText)
    $ts = ""; $build = ""
    if ($PhpInfoText -match '(?m)^Thread Safety\s*=>\s*(\S+)') { $ts = $Matches[1] }
    if ($PhpInfoText -match '(?m)^PHP Extension Build\s*=>\s*(\S+)') { $build = $Matches[1] }
    $compiler = 0
    if ($build -match ',V[CS](\d+)\b') { $compiler = [int]$Matches[1] }
    return [pscustomobject]@{
        ThreadSafety = $ts
        Build        = $build
        IsNTS        = ($ts -eq "disabled" -and $build -match ',NTS,')
        Compiler     = $compiler
    }
}

# Only NTS is required. The compiler (VC15 / VS16 / VS17) is not compared:
# all of them use the VC++ 2015-2022 runtime, and whether PHP accepts a given
# loader is decided by PHP itself in the load test (it compares build IDs and
# prints "Cannot load ... whereas running engine is ..." when they differ).
function Test-PHPBuildForIonCube {
    param([string]$Version, $Info)
    return [bool]$Info.IsNTS
}

# Reads a DLL's PE header and the DLL names in its import and delay-import
# tables. A PHP extension imports php7.dll / php8.dll when built NTS and
# php7ts.dll / php8ts.dll when built TS. Same parser as preflight.ps1 check 5;
# a plain text search is not used because strings inside the DLL could match.
function Get-DllInfo {
    param([string]$Path, [string]$PhpMajor)
    $b = [IO.File]::ReadAllBytes($Path)
    $r = [pscustomobject]@{ IsPE = $false; Is64 = $false; Machine = 0; ImportsNTS = $false; ImportsTS = $false; Imports = @() }
    if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return $r }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -lt 0 -or $pe + 24 -gt $b.Length -or [BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { return $r }
    $r.IsPE = $true
    $r.Machine = [BitConverter]::ToUInt16($b, $pe + 4)
    $r.Is64 = ($r.Machine -eq 0x8664)
    $nSec = [BitConverter]::ToUInt16($b, $pe + 6)
    $opt = $pe + 24
    $dd = $opt + 96; if ([BitConverter]::ToUInt16($b, $opt) -eq 0x20B) { $dd = $opt + 112 }
    $secs = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
    $toOff = {
        param($rva)
        for ($i = 0; $i -lt $nSec; $i++) {
            $s = $secs + 40 * $i
            if ($s + 40 -gt $b.Length) { break }
            $va = [BitConverter]::ToUInt32($b, $s + 12)
            $vs = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
            if ($rva -ge $va -and $rva -lt $va + $vs) { return [int]($rva - $va + [BitConverter]::ToUInt32($b, $s + 20)) }
        }
        return -1
    }
    $names = @()
    foreach ($dir in @(@{ Idx = 1; Size = 20; NameAt = 12 }, @{ Idx = 13; Size = 32; NameAt = 4 })) {
        if ($dd + 8 * $dir.Idx + 4 -gt $b.Length) { continue }
        $rva = [BitConverter]::ToUInt32($b, $dd + 8 * $dir.Idx)
        if ($rva -eq 0) { continue }
        $off = & $toOff $rva
        while ($off -ge 0 -and $off + $dir.Size -le $b.Length) {
            $nameRva = [BitConverter]::ToUInt32($b, $off + $dir.NameAt)
            if ($nameRva -eq 0) { break }
            $no = & $toOff $nameRva
            if ($no -ge 0 -and $no -lt $b.Length) {
                $e = $no; while ($e -lt $b.Length -and $b[$e] -ne 0) { $e++ }
                $names += [Text.Encoding]::ASCII.GetString($b, $no, $e - $no).ToLowerInvariant()
            }
            $off += $dir.Size
        }
    }
    $r.Imports = $names
    $r.ImportsTS  = ($names -contains "php$($PhpMajor)ts.dll")
    $r.ImportsNTS = ($names -contains "php$($PhpMajor).dll")
    return $r
}

function Install-IonCube {
    param([string]$PHPVersion)
    $PHPDir = Get-PHPDir $PHPVersion
    $php = Join-Path $PHPDir "php.exe"
    $phpMajor = $PHPVersion.Split(".")[0]
    $incompatible = "The downloaded ionCube DLL is not compatible with PHP $PHPVersion. It must be the Non-TS x64 loader for PHP $PHPVersion (VC15, VC16 or VC17 are all fine). Please verify the files at aweb.co."
    Write-Step "Installing ionCube for PHP $PHPVersion..."
    $url = $Config.IonCubeURLs[$PHPVersion]
    if (-not $url) { Write-Err "ionCube URL for PHP $PHPVersion is not configured."; return $false }
    $dll = Join-Path $env:TEMP "ioncube_loader_win_$PHPVersion.dll"
    if (-not (Invoke-Download -Url $url -OutFile $dll)) { return $false }
    if ($DryRun) { return $true }
    try {
        $hash = (Get-FileHash -Path $dll -Algorithm SHA256).Hash
        Write-Host "  Downloaded $(Split-Path $dll -Leaf): $([Math]::Round((Get-Item $dll).Length / 1KB)) KB, SHA256 $hash"
        # 1. The PHP build must be NTS (the compiler version is not compared).
        $i = Invoke-Native $php @("-n", "-i") -Step "php -i"
        $info = Get-PHPBuildInfo $i.Output
        Write-Host "  PHP $PHPVersion build: Thread Safety=$($info.ThreadSafety), Extension Build=$($info.Build)"
        if (-not (Test-PHPBuildForIonCube $PHPVersion $info)) {
            Write-Err "PHP at $PHPDir is not a Non-TS build (found '$($info.Build)'). Install the NTS x64 build of PHP $PHPVersion."
            return $false
        }
        # 2. The DLL: x64 PE whose import table has php7.dll / php8.dll, not the TS library.
        $d = Get-DllInfo $dll $phpMajor
        if (-not $d.IsPE) { Write-Err "$incompatible (not a Windows DLL; did aweb.co return an error page?)"; return $false }
        if (-not $d.Is64) { Write-Err ("{0} (x86 or other architecture, machine 0x{1:X4})" -f $incompatible, $d.Machine); return $false }
        if ($d.ImportsTS) { Write-Err "$incompatible (thread-safe build: imports php$($phpMajor)ts.dll)"; return $false }
        if ($d.ImportsNTS) { Write-Ok "ionCube DLL is NTS x64 (imports php$phpMajor.dll)." }
        else { Write-Warn "The DLL imports neither php$phpMajor.dll nor php$($phpMajor)ts.dll; relying on the load test." }
        # 3. Load test from %TEMP% with no php.ini. PHP itself compares the
        #    loader's build ID with its own and prints the reason when it refuses.
        # The value is quoted: an unquoted 8.3 short path (ADMINI~1) is a syntax
        # error for PHP's ini parser, which reads "~" as bitwise NOT.
        $t = Invoke-Native $php @("-n", "-d", "zend_extension=`"$(ConvertTo-ApachePath $dll)`"", "-r", "exit(extension_loaded('ionCube Loader') ? 0 : 1);") -Step "ionCube load test" -AllowFailure
        if (-not $t.Ok) {
            Write-Err $incompatible
            if ($t.All) { @($t.All -split "\r?\n" | Where-Object { $_.Trim() }) | Select-Object -Last 15 | ForEach-Object { Write-Host "    PHP said: $_" } }
            if ($t.All -match 'whereas running engine is') {
                Write-Host "    The loader was built for a different PHP build ID. Use the Non-TS x64 loader made for PHP $PHPVersion ($($info.Build))."
            }
            return $false
        }
        Write-Ok "ionCube DLL accepted by PHP $PHPVersion ($($info.Build))."

        $target = Join-Path $PHPDir "ext\ioncube_loader_win_$PHPVersion.dll"
        if ((Test-Path $target) -and (Get-FileHash $target).Hash -eq (Get-FileHash $dll).Hash) {
            Write-Ok "ionCube loader is already up to date."
        } else {
            try { Copy-Item $dll $target -Force }
            catch {
                # php-cgi.exe processes started by Apache keep the loader open.
                $svc = Get-Service -Name $Config.ApacheService -ErrorAction SilentlyContinue
                $wasRunning = ($svc -and $svc.Status -eq "Running")
                Write-Warn "$target is in use; stopping Apache for a moment to replace it."
                Stop-Apache
                Get-Process -Name php-cgi -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -and $_.Path.StartsWith($PHPDir, [StringComparison]::OrdinalIgnoreCase) } |
                    Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $copyErr = $null
                try { Copy-Item $dll $target -Force } catch { $copyErr = $_.Exception.Message }
                if ($wasRunning) { Restart-Apache | Out-Null }
                if ($copyErr) { Write-Err "Cannot replace $target : $copyErr"; return $false }
            }
        }
    } finally { Remove-Item $dll -Force -ErrorAction SilentlyContinue }

    Write-PHPIni -Version $PHPVersion -PHPDir $PHPDir
    $r = Invoke-Native $php @("-c", (Join-Path $PHPDir "php.ini"), "-r", "exit(extension_loaded('ionCube Loader') ? 0 : 1);") -Step "ionCube check" -AllowFailure
    if (-not $r.Ok) { Write-Err "ionCube did not load from php.ini: $($r.All)"; return $false }
    Write-Ok "ionCube loaded for PHP $PHPVersion."
    return $true
}

# =============================================================================
# Apache + PHP (mod_fcgid), port and domain
# =============================================================================

function Remove-LegacyPHPTasks {
    # v1.0 started php-cgi.exe from scheduled tasks; remove them and their processes.
    foreach ($t in @("ParsVT-PHP74-FCGI", "ParsVT-PHP83-FCGI")) {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $t -Confirm:$false
            Write-Ok "Removed legacy task '$t'."
        }
    }
    Get-Process -Name php-cgi -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($Config.PHPBaseDir, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Get-ServerNameValue {
    $n = "localhost"
    if ($Config.Domain) { $n = $Config.Domain }
    if ([int]$Config.ApachePort -ne 80) { $n = "$($n):$($Config.ApachePort)" }
    return $n
}

# parsvt-domain.conf: name-based vhost for the domain (empty when no domain,
# so the Include line in httpd.conf always points to an existing file).
function Set-ApacheDomain {
    $f = Join-Path $Config.ApacheDir "conf\extra\parsvt-domain.conf"
    if ($Config.Domain) {
        $web = ConvertTo-ApachePath $Config.WebRoot
        Write-TextFile $f @"
# Managed by parsvt.ps1 - domain virtual host
<VirtualHost *:$($Config.ApachePort)>
    ServerName $($Config.Domain)
    DocumentRoot "$web"
</VirtualHost>
"@
    } else {
        Write-TextFile $f "# Managed by parsvt.ps1 - no domain configured`r`n"
    }
    Add-HttpdInclude "parsvt-domain.conf"
}

# php-cgi with cgi.fix_pathinfo=1 (needed by the rest of the CRM) picks the
# wrong script after an internal redirect to "<script>.php/<path>": Apache
# sets REDIRECT_URL and PATH_TRANSLATED, and php-cgi then opens
# PATH_TRANSLATED ("No input file specified", HTTP 404). With
# cgi.fix_pathinfo=0 and cgi.discard_path=1 it uses SCRIPT_FILENAME and
# PATH_INFO from Apache as they are; the only side effect is PHP_SELF without
# the script name, which parsvt-pathinfo.php puts back. A different command
# line is a separate mod_fcgid process class, so these settings apply only
# inside the PathInfoDirs folders.
function Get-PathInfoDirConfig {
    param([string]$PHPDir)
    $phpA = ConvertTo-ApachePath $PHPDir
    $prepend = Join-Path $PHPDir "parsvt-pathinfo.php"
    if ($phpA -match '\s') {
        Write-Warn "PHP directory $PHPDir contains a space; REST API pretty URLs (ws/api/...) will not work. Use ws/Api.php/... URLs."
        return ""
    }
    $code = @'
<?php
// Managed by parsvt.ps1 (rewritten on every install/repair). Loaded with
// auto_prepend_file only for the folders in PathInfoDirs, where php-cgi
// runs with cgi.fix_pathinfo=0 and sets PHP_SELF to PATH_INFO alone.
// Restores the value mod_php and php-cgi with cgi.fix_pathinfo=1 give.
if (isset($_SERVER['SCRIPT_NAME'], $_SERVER['PATH_INFO']) && $_SERVER['PATH_INFO'] !== '') {
    $_SERVER['PHP_SELF'] = $_SERVER['SCRIPT_NAME'] . $_SERVER['PATH_INFO'];
}
'@
    Write-TextFile $prepend $code
    $wrapper = "$phpA/php-cgi.exe -d cgi.fix_pathinfo=0 -d cgi.discard_path=1 -d auto_prepend_file=$phpA/parsvt-pathinfo.php"
    $out = ""
    foreach ($rel in @($Config.PathInfoDirs)) {
        if (-not $rel) { continue }
        $dir = ConvertTo-ApachePath (Join-Path $Config.WebRoot ($rel -replace '/', '\'))
        $out += @"

# REST API, Portal, SOAP and MCP URLs are rewritten to <script>.php/<path>.
<Directory "$dir">
    Options -MultiViews
    AcceptPathInfo On
    FcgidWrapper "$wrapper" .php
</Directory>
"@
    }
    return ($out + "`r`n")
}

function Set-ApachePHPConfig {
    param([string]$PHPVersion)
    $PHPDir = Get-PHPDir $PHPVersion
    Write-Step "Configuring Apache (port $($Config.ApachePort)) to use PHP $PHPVersion (mod_fcgid)..."
    if ($DryRun) { Write-Host "  [DRY] Write parsvt-base.conf / parsvt-php.conf / parsvt-domain.conf"; return $true }
    if (-not (Install-ModFcgid)) { return $false }
    Remove-LegacyPHPTasks

    $web     = ConvertTo-ApachePath $Config.WebRoot
    $phpA    = ConvertTo-ApachePath $PHPDir
    $sysRoot = ConvertTo-ApachePath $env:SystemRoot
    $tempA   = "$sysRoot/Temp"
    $port    = [int]$Config.ApachePort

    # Listen lives in parsvt-base.conf; the stock "Listen 80" is commented out.
    $mainConf = Join-Path $Config.ApacheDir "conf\httpd.conf"
    $c = Get-Content $mainConf -Raw
    $c = [regex]::Replace($c, '(?m)^([ \t]*)(Listen[ \t]+)', '$1#parsvt# $2')
    Write-TextFile $mainConf $c

    $base = @"
# Managed by parsvt.ps1 - rewritten on every install/repair.
<IfModule !rewrite_module>
    LoadModule rewrite_module modules/mod_rewrite.so
</IfModule>
<IfModule !headers_module>
    LoadModule headers_module modules/mod_headers.so
</IfModule>
<IfModule !access_compat_module>
    LoadModule access_compat_module modules/mod_access_compat.so
</IfModule>
Listen $port
ServerName $(Get-ServerNameValue)
ServerTokens Prod
ServerSignature Off
Timeout 660
DocumentRoot "$web"
DirectoryIndex index.php index.html

<Directory "$web">
    Options -Indexes +FollowSymLinks +ExecCGI
    AllowOverride All
    Require all granted
</Directory>
"@
    Write-TextFile (Join-Path $Config.ApacheDir "conf\extra\parsvt-base.conf") $base

    $php = @"
# ParsVT PHP $PHPVersion via mod_fcgid - managed by parsvt.ps1
<IfModule !fcgid_module>
    LoadModule fcgid_module modules/mod_fcgid.so
</IfModule>
FcgidInitialEnv PHPRC "$phpA"
FcgidInitialEnv PHP_FCGI_MAX_REQUESTS 1000
FcgidInitialEnv SystemRoot "$sysRoot"
FcgidInitialEnv SystemDrive "$($env:SystemDrive)"
FcgidInitialEnv windir "$sysRoot"
FcgidInitialEnv TEMP "$tempA"
FcgidInitialEnv TMP "$tempA"
FcgidInitialEnv PATH "$phpA;$sysRoot/system32;$sysRoot"
# Must stay below PHP_FCGI_MAX_REQUESTS so Apache recycles php-cgi first.
FcgidMaxRequestsPerProcess 900
FcgidMaxProcesses 24
FcgidMaxProcessesPerClass 16
FcgidMinProcessesPerClass 2
FcgidIdleTimeout 600
FcgidProcessLifeTime 3600
FcgidConnectTimeout 30
FcgidIOTimeout 660
FcgidBusyTimeout 900
# Default is 128 KB, which breaks uploads and imports; match post_max_size.
FcgidMaxRequestLen 134217728
FcgidOutputBufferSize 0
# REST / OData clients send Basic auth; php-cgi only sees it when passed through.
FcgidPassHeader Authorization

<Directory "$web">
    AddHandler fcgid-script .php
    FcgidWrapper "$phpA/php-cgi.exe" .php
</Directory>
"@
    $php += Get-PathInfoDirConfig -PHPDir $PHPDir
    Write-TextFile (Join-Path $Config.ApacheDir "conf\extra\parsvt-php.conf") $php

    Add-HttpdInclude "parsvt-base.conf"
    Add-HttpdInclude "parsvt-php.conf"
    Set-ApacheDomain
    if (-not (Test-ApacheConfig)) { return $false }
    Write-Ok "Apache configured: port $port, PHP $PHPVersion$(if ($Config.Domain) { ", domain $($Config.Domain)" })."
    return $true
}

# =============================================================================
# MariaDB
# =============================================================================

# Full path only: a mysql.exe found on the PATH may belong to another
# installation (XAMPP, MySQL) and talk to the wrong server.
function Get-MySqlClient {
    $m = Join-Path $Config.MariaDBDir "bin\mysql.exe"
    if (-not (Test-Path $m)) { throw "mysql.exe not found at $m (MariaDB folder: $($Config.MariaDBDir))" }
    return $m
}

# Option file with the DB credentials, readable by Administrators/SYSTEM only.
function New-MySqlDefaultsFile {
    param([string]$Path = "")
    if (-not $Path) { $Path = [IO.Path]::GetTempFileName() }
    if (-not (Test-Path $Path)) { New-Item -ItemType File -Path $Path -Force | Out-Null }
    Set-FileAcl-AdminsOnly $Path
    $pw = $Config.MySQLPassword -replace '\\', '\\' -replace '"', '\"'
    $port = ""
    if ($Config.DBPort) { $port = "port=$($Config.DBPort)`r`n" }
    Write-TextFile $Path "[client]`r`nuser=$($Config.DBUser)`r`npassword=`"$pw`"`r`nhost=$($Config.DBHost)`r`n$port"
    return $Path
}

# Runs a .sql file through mysql.exe stdin. Returns the Invoke-Native result.
function Invoke-MySqlFile {
    param([string]$SqlFile, [string]$Database = "", [string[]]$Extra = @(), [switch]$AllowFailure)
    $creds = New-MySqlDefaultsFile
    try {
        $a = @("--defaults-extra-file=$creds", "--default-character-set=utf8mb4") + $Extra
        if ($Database) { $a += $Database }
        return (Invoke-Native (Get-MySqlClient) $a -StdinFile $SqlFile -Step "mysql" -AllowFailure:$AllowFailure)
    } finally {
        Remove-Item $creds -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Sql {
    param([string]$Sql, [string]$Database = "", [switch]$Query, [switch]$AllowFailure)
    if ($DryRun) { Write-Host "  [DRY] SQL: $($Sql.Substring(0,[Math]::Min(60,$Sql.Length)))..." -ForegroundColor DarkGray; return [pscustomobject]@{ Ok = $true; Output = "" } }
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Set-FileAcl-AdminsOnly $tmp
        Write-TextFile $tmp $Sql
        $extra = @()
        if ($Query) { $extra = @("--batch", "--skip-column-names") }
        return (Invoke-MySqlFile -SqlFile $tmp -Database $Database -Extra $extra -AllowFailure:$AllowFailure)
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Wait-MariaDB {
    for ($i = 0; $i -lt 60; $i++) { if (Test-PortListening 3306) { return $true }; Start-Sleep -Seconds 1 }
    return $false
}

function Install-MariaDB {
    if (Get-Service -Name "MariaDB" -ErrorAction SilentlyContinue) {
        Write-Ok "MariaDB service already exists."
        if (-not $Config.MySQLPassword) { $Config.MySQLPassword = Read-SavedMySQLPassword }
        if (-not $Config.MySQLPassword -and -not $DryRun) {
            $sec = Read-Host "Enter the existing MariaDB password for '$($Config.DBUser)'" -AsSecureString
            $Config.MySQLPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        }
    } else {
        Write-Step "Installing MariaDB 10.11..."
        $msi = Join-Path $env:TEMP $Config.Downloads.MariaDB.File
        if (-not (Invoke-ConfiguredDownload "MariaDB" $msi)) { return $false }
        $Config.MySQLPassword = New-RandomPassword
        Save-CredentialsFile    # persist before anything can fail
        if ($DryRun) { return $true }
        $msiLog = Join-Path $Config.LogDir "mariadb-msi.log"
        # PASSWORD is visible in the process list while msiexec runs (MSI has no other channel).
        # Start-Process (not Invoke-Native): msiexec parses its own command line and the
        # property syntax PASSWORD=value must stay unquoted.
        $margs = "/i `"$msi`" /qn /norestart SERVICENAME=MariaDB PORT=3306 PASSWORD=$($Config.MySQLPassword)"
        $p = Start-Process (Join-Path $env:SystemRoot "System32\msiexec.exe") -ArgumentList $margs -Wait -PassThru
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        if (@(0, 3010) -notcontains $p.ExitCode) {
            Write-Err "MariaDB MSI failed with exit code $($p.ExitCode). For details re-run: msiexec /i <msi> /qn /l*v $msiLog"
            return $false
        }
    }
    if ($DryRun) { return $true }
    Set-Service -Name "MariaDB" -StartupType Automatic
    Start-Service MariaDB -ErrorAction SilentlyContinue
    if (-not (Wait-MariaDB)) { Write-Err "MariaDB is not listening on port 3306."; return $false }
    $r = Invoke-Sql "SELECT VERSION();" -Query -AllowFailure
    if (-not $r.Ok) { Write-Err "Cannot log in to MariaDB as '$($Config.DBUser)': $($r.Error)"; return $false }
    Save-CredentialsFile
    Write-Ok "MariaDB $("$($r.Output)".Trim()) running."
    return $true
}

# =============================================================================
# Vtiger
# =============================================================================

function Install-VtigerPackage {
    param([int]$Version)
    $Config.VtigerVersion = $Version
    $Config.PHPVersion    = $Config.VtigerToPHP[$Version]

    Write-Step "Downloading Vtiger $Version package..."
    $zip = Join-Path $env:TEMP "parsvt-vtiger$Version.zip"
    if (-not (Invoke-Download -Url "$($Config.DownloadEndpoint)?v=$Version" -OutFile $zip)) { return $false }
    if ($DryRun) { return $true }

    # Extract and verify in a staging folder; the web root is untouched until the package is known good.
    $stage = Join-Path $env:TEMP "parsvt-vtiger-stage"
    Write-Step "Extracting Vtiger $Version..."
    Expand-ZipFile $zip $stage
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $root = $stage
    if (-not (Test-Path (Join-Path $root "vtigerversion.php"))) {
        $sub = @(Get-ChildItem $stage -Directory)
        if ($sub.Count -eq 1 -and (Test-Path (Join-Path $sub[0].FullName "vtigerversion.php"))) { $root = $sub[0].FullName }
        else { Write-Err "vtigerversion.php not found in the package."; return $false }
    }
    $detected = Get-VtigerVersion $root
    if (-not $detected -or [int]($detected.Split(".")[0]) -ne $Version) {
        Write-Err "Server returned Vtiger '$detected' but $Version was expected. Aborted; nothing was changed."
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    if (-not (Test-Path (Join-Path $root "test\data\tmp\database.sql"))) { Write-Err "database.sql not found in package."; return $false }
    Write-Ok "Package is Vtiger $detected."

    # Existing web root content is moved aside, never deleted.
    $existing = @(Get-ChildItem $Config.WebRoot -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "index.html" })
    if ($existing.Count -gt 0) {
        if (Test-Path (Join-Path $Config.WebRoot "config.inc.php")) {
            if (-not $script:OverwriteConfirmed) {
                if (-not (Confirm-Typed "An existing CRM was found at $($Config.WebRoot). It will be moved aside and its database dumped and replaced." "OVERWRITE")) {
                    Stop-Install "Cancelled by operator; nothing was changed." 0
                }
                $script:OverwriteConfirmed = $true
            }
        }
        $aside = "$($Config.WebRoot).old-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Stop-Apache
        Move-Item $Config.WebRoot $aside
        Write-Warn "Previous web root moved to $aside (delete it when no longer needed)."
    } elseif (Test-Path $Config.WebRoot) {
        Remove-Item $Config.WebRoot -Recurse -Force
    }
    New-Dir $Config.WebRoot
    if (-not (Test-IsSubPath $Config.WebRoot $Config.ApacheDir)) { Set-DirAcl -Path $Config.WebRoot -UsersRead }
    Copy-Tree $root $Config.WebRoot
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Vtiger $detected placed in $($Config.WebRoot)."
    return $true
}

function Invoke-CRMInstall {
    $db = $Config.DBName
    if ($db -notmatch '^[A-Za-z0-9_]+$') { Write-Err "Invalid database name '$db'."; return $false }
    $dbSql = Join-Path $Config.WebRoot "test\data\tmp\database.sql"
    if ($DryRun) { Write-Host "  [DRY] Create database $db and import $dbSql"; return $true }

    # An existing non-empty database is dumped before it is replaced.
    $r = Invoke-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$db';" -Query
    if ([int]("$($r.Output)".Trim()) -gt 0) {
        if (-not $script:OverwriteConfirmed) {
            if (-not (Confirm-Typed "Database '$db' already contains tables. It will be dumped to $($Config.BackupDir) and then dropped." "OVERWRITE")) {
                Stop-Install "Cancelled by operator; database untouched." 0
            }
            $script:OverwriteConfirmed = $true
        }
        New-Dir $Config.BackupDir
        Set-DirAcl -Path $Config.BackupDir
        $dump = Join-Path $Config.BackupDir "parsvt-preinstall-$db-$(Get-Date -Format 'yyyyMMdd-HHmmss').sql"
        $creds = New-MySqlDefaultsFile
        try {
            $d = Invoke-Native (Join-Path $Config.MariaDBDir "bin\mysqldump.exe") @("--defaults-extra-file=$creds", "--single-transaction", "--routines", "--triggers", "--events", "--hex-blob", "--default-character-set=utf8mb4", "--result-file=$dump", $db) -Step "mysqldump (safety dump)" -AllowFailure
        } finally { Remove-Item $creds -Force -ErrorAction SilentlyContinue }
        if (-not $d.Ok) { Write-Err "Safety dump failed; database NOT dropped: $($d.All)"; return $false }
        Write-Ok "Safety dump: $dump"
        Invoke-Sql "DROP DATABASE ``$db``;" | Out-Null
    }

    Write-Step "Creating database '$db'..."
    Invoke-Sql "CREATE DATABASE IF NOT EXISTS ``$db`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | Out-Null

    Write-Step "Importing database schema..."
    Invoke-MySqlFile -SqlFile $dbSql -Database $db | Out-Null
    Write-Ok "Database imported."
    return $true
}

function Set-AdminPassword {
    $Config.AdminPassword = New-RandomPassword -Length 15
    if ($DryRun) { Write-Host "  [DRY] Set admin password"; return $true }

    # Same scheme as the Linux installer: DES crypt() with the first two letters
    # of the user name as salt and an empty crypt_type. The password is passed
    # through the environment, not the command line.
    $php = Join-Path (Get-PHPDir $Config.PHPVersion) "php.exe"
    $env:PARSVT_ADMIN_PW = $Config.AdminPassword
    try { $r = Invoke-Native $php @("-r", "echo crypt(getenv('PARSVT_ADMIN_PW'),'ad');") -Step "php crypt" }
    finally { Remove-Item Env:\PARSVT_ADMIN_PW -ErrorAction SilentlyContinue }
    $hash = "$($r.Output)".Trim()
    if ($hash -notmatch '^ad[./0-9A-Za-z]{11}$') { Write-Err "Could not hash the admin password (php said: $hash)."; return $false }

    $sql = @"
UPDATE vtiger_users SET user_password = '$hash', crypt_type = '' WHERE id = 1;
UPDATE vtiger_users SET accesskey = UPPER(SUBSTRING(MD5(RAND()) FROM 1 FOR 16)) WHERE id = 1;
TRUNCATE vtiger_crmsetup;
TRUNCATE vtiger_loginhistory;
"@
    Invoke-Sql $sql $Config.DBName | Out-Null
    Save-CredentialsFile
    Write-Ok "Admin password set."
    return $true
}

function Install-Extensions {
    Write-Step "Downloading extensions package..."
    $zip = Join-Path $env:TEMP "parsvt-extensions.zip"
    $url = $Config.ExtURL
    $ok = $false
    if ($url.StartsWith("http://")) {
        $ok = Invoke-Download -Url ("https://" + $url.Substring(7)) -OutFile $zip
        if (-not $ok) { Write-Warn "HTTPS not available for the extensions URL; falling back to HTTP." }
    }
    if (-not $ok) { $ok = Invoke-Download -Url $url -OutFile $zip }
    if (-not $ok) { return $false }
    if ($DryRun) { return $true }
    $stage = Join-Path $env:TEMP "parsvt-ext-stage"
    Expand-ZipFile $zip $stage
    Copy-Tree $stage $Config.WebRoot
    Remove-Item $zip, $stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Extensions extracted."
    return $true
}

# _install.php / _extensions.php are always deleted, even when a call fails.
function Invoke-Wizard {
    if ($DryRun) { Write-Host "  [DRY] Invoke _install.php and _extensions.php"; return $true }
    $crm = Get-CrmUrl
    $ok = $true
    try {
        Write-Step "Calling _install.php..."
        # NOTE: GET puts the DB password in Apache's access.log; switch to POST
        # once _install.php is confirmed to read $_REQUEST/$_POST.
        $q = "db_hostname=$([Uri]::EscapeDataString($Config.DBHost))&db_name=$([Uri]::EscapeDataString($Config.DBName))" +
             "&db_username=$([Uri]::EscapeDataString($Config.DBUser))&db_password=$([Uri]::EscapeDataString($Config.MySQLPassword))"
        try { Invoke-WebRequest -Uri "$($crm)_install.php?$q" -UseBasicParsing -TimeoutSec 600 | Out-Null }
        catch { Write-Err "_install.php failed: $($_.Exception.Message)"; $ok = $false }

        if ($ok) {
            Write-Step "Calling _extensions.php..."
            try { Invoke-WebRequest -Uri "$($crm)_extensions.php?token=$([Uri]::EscapeDataString($Config.ExtToken))" -UseBasicParsing -TimeoutSec 900 | Out-Null }
            catch { Write-Err "_extensions.php failed: $($_.Exception.Message)"; $ok = $false }
        }
    } finally {
        Get-ChildItem $Config.WebRoot -Filter "_install*"    -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem $Config.WebRoot -Filter "_extensions*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $access = Join-Path $Config.ApacheDir "logs\access.log"
        if (Test-Path $access) { Write-Warn "access.log contains the wizard URL with the DB password; it is only readable by Administrators." }
    }
    return $ok
}

# =============================================================================
# Firewall
# =============================================================================

function Open-FirewallPort {
    param([int]$Port)
    $name = "ParsVT HTTP $Port"
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    }
}

function Open-FirewallPorts {
    Write-Step "Opening firewall ports..."
    if ($DryRun) { Write-Host "  [DRY] Open ports $($Config.ApachePort), 443"; return }
    foreach ($p in @([int]$Config.ApachePort, 443)) { Open-FirewallPort $p }
    Write-Ok "Firewall ports $($Config.ApachePort) and 443 open."
}

# =============================================================================
# Backup and restore scripts
# =============================================================================

# Shared by backup.ps1 and restore.ps1 (inserted at @@HELPERS@@).
$script:TemplateHelpers = @'
function Log($m) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    Write-Host $line
    Add-Content -Path $LOG -Value $line
}

function ConvertTo-WinArgument([string]$Arg) {
    if ($Arg -eq "") { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"'); $bs = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs) { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * ($bs * 2)); [void]$sb.Append('"')
    return $sb.ToString()
}

# Runs a program, feeds $StdinFile to stdin, returns exit code and output;
# throws with the last 15 output lines when the exit code is not 0.
function Invoke-Tool([string]$Exe, [string[]]$Arguments, [string]$StdinFile = "", [switch]$AllowFailure) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (@($Arguments) | ForEach-Object { ConvertTo-WinArgument $_ }) -join " "
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = [bool]$StdinFile
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if ($StdinFile) {
            $fs = [IO.File]::OpenRead($StdinFile)
            try { $fs.CopyTo($p.StandardInput.BaseStream) } finally { $fs.Dispose(); $p.StandardInput.Close() }
        }
        $p.WaitForExit()
        $r = [pscustomobject]@{ ExitCode = $p.ExitCode; Output = $o.Result; Error = $e.Result }
    } finally { $p.Dispose() }
    if ($r.ExitCode -ne 0 -and -not $AllowFailure) {
        $src = $r.Error; if (-not "$src".Trim()) { $src = $r.Output }
        $tail = @("$src" -split "\r?\n" | Where-Object { $_.Trim() }) | Select-Object -Last 15
        throw "$(Split-Path $Exe -Leaf) exit code $($r.ExitCode): $($tail -join ' | ')"
    }
    return $r
}

function Compress-GzipFile([string]$Source, [string]$Dest) {
    $in = $null; $out = $null; $gz = $null
    try {
        $in = [IO.File]::OpenRead($Source)
        $out = [IO.File]::Create($Dest)
        $gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress)
        $in.CopyTo($gz)
    } finally {
        if ($gz) { $gz.Dispose() }
        if ($out) { $out.Dispose() }
        if ($in) { $in.Dispose() }
    }
}
'@

$script:BackupTemplate = @'
# Auto-generated by parsvt.ps1 v2.11. Run the installer's Repair option to regenerate.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$DB_NAME        = "@@DB_NAME@@"
$DEFAULTS_FILE  = "@@DEFAULTS_FILE@@"
$MARIADB_BIN    = "@@MARIADB_BIN@@"
$WEB_DIR        = "@@WEB_DIR@@"
$BACKUP_DIR     = "@@BACKUP_DIR@@"
$LOG            = "@@LOG_FILE@@"
$RETENTION_DAYS = 7
$EXCLUDE_TOP    = @("cache", "tmp")

@@HELPERS@@

# Zips $Src into $Dest. Files are opened with sharing, so files in use by
# Apache/PHP are still read; unreadable files are logged and skipped.
function New-FilesZip($Src, $Dest) {
    $srcFull = (Resolve-Path $Src).Path.TrimEnd('\') + '\'
    $skipped = 0
    $fs = [IO.File]::Open($Dest, [IO.FileMode]::Create)
    $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($srcFull, "*", [IO.SearchOption]::AllDirectories)) {
            $rel = $f.Substring($srcFull.Length)
            $parts = $rel.Split('\')
            if ($parts.Count -gt 1 -and $EXCLUDE_TOP -contains $parts[0]) { continue }
            $in = $null
            try { $in = New-Object IO.FileStream($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite) }
            catch { $skipped++; Log "Skipped (cannot open): $rel"; continue }
            try {
                $entry = $zip.CreateEntry($rel.Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [IO.File]::GetLastWriteTime($f)
                $es = $entry.Open()
                try { $in.CopyTo($es) } finally { $es.Dispose() }
            } finally { $in.Dispose() }
        }
    } finally { $zip.Dispose(); $fs.Dispose() }
    return $skipped
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stamp   = Get-Date -Format "yyyy-MM-dd"
$sqlFile = Join-Path $BACKUP_DIR "parsvt-db-$stamp.sql"
$gzFile  = "$sqlFile.gz"
$zipFile = Join-Path $BACKUP_DIR "parsvt-files-$stamp.zip"

try {
    if (-not (Test-Path $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null }
    Log "=== Backup started ==="

    Log "Dumping database: $DB_NAME"
    # --result-file writes mysqldump's bytes straight to disk: no PowerShell
    # decoding (which corrupts UTF-8 Persian text) and no full dump in memory.
    Invoke-Tool (Join-Path $MARIADB_BIN "mysqldump.exe") @("--defaults-extra-file=$DEFAULTS_FILE", "--single-transaction", "--quick",
        "--routines", "--triggers", "--events", "--default-character-set=utf8mb4", "--hex-blob", "--result-file=$sqlFile", $DB_NAME) | Out-Null
    Compress-GzipFile $sqlFile $gzFile
    Remove-Item $sqlFile -Force
    Log "Database dump saved: $gzFile ($([Math]::Round((Get-Item $gzFile).Length / 1MB, 1)) MB)"

    Log "Archiving web directory: $WEB_DIR"
    $skipped = New-FilesZip $WEB_DIR $zipFile
    Log "File archive saved: $zipFile ($([Math]::Round((Get-Item $zipFile).Length / 1MB, 1)) MB, $skipped skipped)"

    Log "Applying $RETENTION_DAYS-day retention"
    $limit = (Get-Date).AddDays(-$RETENTION_DAYS)
    Get-ChildItem $BACKUP_DIR -File | Where-Object {
        ($_.Name -like "parsvt-db-*.sql.gz" -or $_.Name -like "parsvt-files-*.zip") -and $_.LastWriteTime -lt $limit
    } | Remove-Item -Force

    Log "=== Backup completed successfully ==="
    exit 0
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
    Log "=== Backup FAILED ==="
    exit 1
}
'@

$script:RestoreTemplate = @'
# Auto-generated by parsvt.ps1 v2.11. Run the installer's Repair option to regenerate.
# Usage (elevated): powershell -NoProfile -ExecutionPolicy Bypass -File "<this file>"
# Exit codes: 0 restored, 2 cancelled by the operator, 5 preflight failure
# (not admin, missing tools, bad backup file), 6 another restore is running,
# 1 a restore step failed (the log names the safety copies to roll back with).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$DB_NAME        = "@@DB_NAME@@"
$DEFAULTS_FILE  = "@@DEFAULTS_FILE@@"
$MARIADB_BIN    = "@@MARIADB_BIN@@"
$WEB_DIR        = "@@WEB_DIR@@"
$BACKUP_DIR     = "@@BACKUP_DIR@@"
$LOG            = "@@LOG_FILE@@"
$LOCK_FILE      = "@@LOCK_FILE@@"
$APACHE_SERVICE = "@@APACHE_SERVICE@@"
$HTTPD_EXE      = "@@HTTPD_EXE@@"

@@HELPERS@@

function Stop-Preflight($m) { Log "PREFLIGHT FAILED: $m"; exit 5 }

function Get-DirSize($Path) {
    if (-not (Test-Path $Path)) { return 0 }
    $s = 0
    foreach ($f in [IO.Directory]::EnumerateFiles($Path, "*", [IO.SearchOption]::AllDirectories)) {
        try { $s += (New-Object IO.FileInfo($f)).Length } catch { }
    }
    return $s
}

function Format-Size($b) { return "{0:N1} MB" -f ($b / 1MB) }

function Set-WebAcl($Path) {
    $inh = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, "FullControl", $inh, $prop, "Allow")))
    }
    $users = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($users, "ReadAndExecute", $inh, $prop, "Allow")))
    (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
}

function Invoke-Sql([string]$Sql, [switch]$Query) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmp, $Sql, (New-Object Text.UTF8Encoding($false)))
        $a = @("--defaults-extra-file=$DEFAULTS_FILE", "--default-character-set=utf8mb4")
        if ($Query) { $a += @("--batch", "--skip-column-names") }
        return (Invoke-Tool $MYSQL $a $tmp)
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$MYSQL     = Join-Path $MARIADB_BIN "mysql.exe"
$MYSQLDUMP = Join-Path $MARIADB_BIN "mysqldump.exe"
$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"

# ---- Preflight (nothing is changed here) ------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this script from an elevated PowerShell (Run as administrator)." -ForegroundColor Red
    exit 5
}
foreach ($f in @($MYSQL, $MYSQLDUMP, $DEFAULTS_FILE, $HTTPD_EXE)) { if (-not (Test-Path $f)) { Stop-Preflight "missing $f" } }
if (-not (Test-Path $BACKUP_DIR)) { Stop-Preflight "backup directory $BACKUP_DIR does not exist" }
if ($DB_NAME -notmatch '^[A-Za-z0-9_]+$') { Stop-Preflight "invalid database name '$DB_NAME'" }

# ---- Lock --------------------------------------------------------------------
# An exclusive handle on the lock file; Windows releases it if this process dies.
$lock = $null
try {
    $lockDir = Split-Path $LOCK_FILE -Parent
    if (-not (Test-Path $lockDir)) { New-Item -ItemType Directory -Path $lockDir -Force | Out-Null }
    $lock = [IO.File]::Open($LOCK_FILE, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch {
    Write-Host "Another restore is running ($LOCK_FILE is locked)." -ForegroundColor Red
    Add-Content -Path $LOG -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Another restore is running; exiting." -ErrorAction SilentlyContinue
    exit 6
}

$tmpSql = Join-Path $BACKUP_DIR "parsvt-restore-$stamp.sql"
$asideDir = ""
$safetyDump = ""
$apacheStopped = $false
try {
    Log "=== Restore started by $($id.Name) ==="

    # ---- Pick a backup set -------------------------------------------------
    $sets = @(Get-ChildItem $BACKUP_DIR -File -Filter "parsvt-db-*.sql.gz" | Sort-Object LastWriteTime -Descending)
    if ($sets.Count -eq 0) { Stop-Preflight "no parsvt-db-*.sql.gz files in $BACKUP_DIR" }
    Write-Host ""
    Write-Host "Available backups in $($BACKUP_DIR):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $sets.Count; $i++) {
        $s = $sets[$i].Name -replace '^parsvt-db-', '' -replace '\.sql\.gz$', ''
        $z = Join-Path $BACKUP_DIR "parsvt-files-$s.zip"
        $files = "database only"
        if (Test-Path $z) { $files = "database + files" }
        if ($s -like "prerestore-*") { $files = "database only (safety copy taken before an earlier restore)" }
        Write-Host ("  [{0}] {1}  {2}  ({3}, {4})" -f ($i + 1), $s, $sets[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm"), (Format-Size $sets[$i].Length), $files)
    }
    $sel = Read-Host "Select a backup number (anything else cancels)"
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $sets.Count) { Log "Cancelled at backup selection."; exit 2 }
    $dbGz = $sets[[int]$sel - 1].FullName
    $setStamp = $sets[[int]$sel - 1].Name -replace '^parsvt-db-', '' -replace '\.sql\.gz$', ''
    $zipFile = Join-Path $BACKUP_DIR "parsvt-files-$setStamp.zip"
    $restoreFiles = Test-Path $zipFile
    Log "Selected set: $setStamp (files: $restoreFiles)"

    # ---- Validate the backup before touching anything -----------------------
    Log "Checking $dbGz"
    try {
        $in = [IO.File]::OpenRead($dbGz)
        $gz = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
        $out = [IO.File]::Create($tmpSql)
        try { $gz.CopyTo($out) } finally { $out.Dispose(); $gz.Dispose(); $in.Dispose() }
    } catch { Stop-Preflight "cannot decompress $dbGz : $($_.Exception.Message)" }
    $head = New-Object byte[] 4096
    $hs = [IO.File]::OpenRead($tmpSql); $n = $hs.Read($head, 0, 4096); $hs.Dispose()
    $headText = [Text.Encoding]::UTF8.GetString($head, 0, $n)
    if ($headText -notmatch '(MariaDB|MySQL) dump') { Stop-Preflight "$dbGz does not look like a mysqldump file" }
    if ($restoreFiles) {
        try {
            $za = [IO.Compression.ZipFile]::OpenRead($zipFile)
            try {
                $names = @($za.Entries | ForEach-Object { $_.FullName })
                if ($names.Count -eq 0 -or ($names -notcontains "config.inc.php" -and $names -notcontains "vtigerversion.php")) {
                    Stop-Preflight "$zipFile does not contain a Vtiger web root"
                }
            } finally { $za.Dispose() }
        } catch { Stop-Preflight "cannot read $zipFile : $($_.Exception.Message)" }
    }

    # ---- What will be replaced ----------------------------------------------
    $r = Invoke-Sql "SELECT COUNT(*), IFNULL(SUM(data_length + index_length), 0), IFNULL(SUM(table_rows), 0) FROM information_schema.tables WHERE table_schema = '$DB_NAME';" -Query
    $cols = "$($r.Output)".Trim() -split "\s+"
    $tables = [int64]$cols[0]; $dbBytes = [int64]$cols[1]; $rows = [int64]$cols[2]
    Write-Host ""
    Write-Host "This restore REPLACES the current data:" -ForegroundColor Red
    Write-Host ("  Database $($DB_NAME): {0} tables, about {1} rows, {2}" -f $tables, $rows, (Format-Size $dbBytes))
    if ($restoreFiles) { Write-Host ("  Web root $($WEB_DIR): {0} (moved aside, not deleted)" -f (Format-Size (Get-DirSize $WEB_DIR))) }
    else { Write-Host "  Web root: not changed (this set has no files archive)" }
    Write-Host "  Restoring from: $setStamp"
    $answer = Read-Host "Type the database name ($DB_NAME) to continue, anything else cancels"
    if ($answer -cne $DB_NAME) { Log "Cancelled at confirmation."; exit 2 }

    # ---- Safety dump ----------------------------------------------------------
    if ($tables -gt 0) {
        $safetySql = Join-Path $BACKUP_DIR "parsvt-db-prerestore-$stamp.sql"
        $safetyDump = "$safetySql.gz"
        Log "Safety dump of the current database: $safetyDump"
        Invoke-Tool $MYSQLDUMP @("--defaults-extra-file=$DEFAULTS_FILE", "--single-transaction", "--quick", "--routines", "--triggers",
            "--events", "--default-character-set=utf8mb4", "--hex-blob", "--result-file=$safetySql", $DB_NAME) | Out-Null
        Compress-GzipFile $safetySql $safetyDump
        Remove-Item $safetySql -Force
    }

    # ---- Restore ----------------------------------------------------------------
    Log "Stopping $APACHE_SERVICE"
    Stop-Service $APACHE_SERVICE -Force -ErrorAction SilentlyContinue
    $apacheStopped = $true

    Log "Recreating database $DB_NAME"
    Invoke-Sql "DROP DATABASE IF EXISTS ``$DB_NAME``; CREATE DATABASE ``$DB_NAME`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | Out-Null
    Log "Importing $dbGz"
    Invoke-Tool $MYSQL @("--defaults-extra-file=$DEFAULTS_FILE", "--default-character-set=utf8mb4", $DB_NAME) $tmpSql | Out-Null

    if ($restoreFiles) {
        $asideDir = "$WEB_DIR.prerestore-$stamp"
        Log "Moving current web root to $asideDir"
        if (Test-Path $WEB_DIR) { Move-Item $WEB_DIR $asideDir }
        try {
            New-Item -ItemType Directory -Path $WEB_DIR -Force | Out-Null
            Set-WebAcl $WEB_DIR
            Log "Extracting $zipFile"
            [IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $WEB_DIR)
            Set-WebAcl $WEB_DIR   # re-applied so every extracted file inherits it
        } catch {
            Log "File restore failed; putting the previous web root back."
            Remove-Item $WEB_DIR -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $asideDir) { Move-Item $asideDir $WEB_DIR; $asideDir = "" }
            throw
        }
    }

    Log "Testing Apache configuration and starting $APACHE_SERVICE"
    Invoke-Tool $HTTPD_EXE @("-t") | Out-Null
    Start-Service $APACHE_SERVICE
    $apacheStopped = $false

    Log "=== Restore completed successfully from $setStamp ==="
    if ($safetyDump) { Log "Previous database: $safetyDump" }
    if ($asideDir) { Log "Previous web root: $asideDir (delete it when no longer needed)" }
    exit 0
} catch {
    Log "ERROR: $($_.Exception.Message)"
    if ($safetyDump) { Log "To roll back the database, restore $safetyDump (it is listed by this script)." }
    if ($asideDir) { Log "The previous web root is at $asideDir." }
    if ($apacheStopped) { try { Start-Service $APACHE_SERVICE } catch { Log "Apache could not be started: $($_.Exception.Message)" } }
    Log "=== Restore FAILED ==="
    exit 1
} finally {
    Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
    if ($lock) { $lock.Dispose() }
}
'@

function Expand-ScriptTemplate {
    param([string]$Template, [hashtable]$Values)
    $t = $Template.Replace("@@HELPERS@@", $script:TemplateHelpers)
    foreach ($k in $Values.Keys) { $t = $t.Replace("@@$k@@", $Values[$k]) }
    if ($t -match '@@[A-Z_]+@@') { throw "Unfilled placeholder $($Matches[0]) in script template." }
    return $t
}

function Install-BackupScript {
    Write-Step "Installing backup and restore scripts..."
    if ($DryRun) { Write-Host "  [DRY] Write $($Config.BackupScriptDir)\backup.ps1 and restore.ps1"; return $true }

    New-Dir $Config.BackupDir;       Set-DirAcl -Path $Config.BackupDir
    New-Dir $Config.LogDir;          Set-DirAcl -Path $Config.LogDir
    New-Dir $Config.BackupScriptDir; Set-DirAcl -Path $Config.BackupScriptDir

    # Both scripts read the credentials from this option file (no copy of the
    # password inside the scripts).
    $cnf = Join-Path $Config.BackupScriptDir "backup.cnf"
    New-MySqlDefaultsFile -Path $cnf | Out-Null

    $values = @{
        DB_NAME        = $Config.DBName
        DEFAULTS_FILE  = $cnf
        MARIADB_BIN    = (Join-Path $Config.MariaDBDir "bin")
        WEB_DIR        = $Config.WebRoot
        BACKUP_DIR     = $Config.BackupDir
        APACHE_SERVICE = $Config.ApacheService
        HTTPD_EXE      = (Join-Path $Config.ApacheDir "bin\httpd.exe")
        LOCK_FILE      = (Join-Path $Config.LogDir "restore.lock")
    }
    $values.LOG_FILE = Join-Path $Config.LogDir "crm_backup.log"
    $backupPs1 = Join-Path $Config.BackupScriptDir "backup.ps1"
    Write-TextFile $backupPs1 (Expand-ScriptTemplate $script:BackupTemplate $values)
    Set-FileAcl-AdminsOnly $backupPs1

    $values.LOG_FILE = Join-Path $Config.LogDir "crm_restore.log"
    $restorePs1 = Join-Path $Config.BackupScriptDir "restore.ps1"
    Write-TextFile $restorePs1 (Expand-ScriptTemplate $script:RestoreTemplate $values)
    Set-FileAcl-AdminsOnly $restorePs1

    Write-Ok "Backup script:  $backupPs1"
    Write-Ok "Restore script: $restorePs1"
    return $true
}

function Install-ScheduledTasks {
    Write-Step "Registering scheduled tasks..."
    if ($DryRun) { Write-Host "  [DRY] Register ParsVT-Backup and ParsVT-VtigerCron"; return }
    $p = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    $t = "ParsVT-Backup"
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $t -Confirm:$false }
    $backupPs1 = Join-Path $Config.BackupScriptDir "backup.ps1"
    $a  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$backupPs1`""
    $tr = New-ScheduledTaskTrigger -Daily -At "22:00"
    $s  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $t -Action $a -Trigger $tr -Principal $p -Settings $s | Out-Null
    Write-Ok "Task '$t' registered (daily 22:00)."

    # vtigercron.php every 15 minutes. See Get-VtigerCronMode for curl.exe vs php.exe.
    $t2 = "ParsVT-VtigerCron"
    if (Get-ScheduledTask -TaskName $t2 -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $t2 -Confirm:$false }
    $mode = Get-VtigerCronMode
    if ($mode.Mode -eq "curl") {
        # The server IP chosen during install (the CRM URL), not 127.0.0.1:
        # ParsVT's vtigercron.php expects the request on that address. If the
        # IP changes, run Repair. -f makes HTTP errors (500, 404) a failed
        # task run; --max-time stays above PHP's 600 s and fcgid's 660 s limits.
        if ($Config.ServerIP -eq "127.0.0.1") { Write-Warn "No server IP is known (install state); the cron task uses 127.0.0.1." }
        $cronUrl = (Get-CrmUrl) + "vtigercron.php"
        $a2 = New-ScheduledTaskAction -Execute $mode.Exe -Argument "-fsS --max-time 900 -o NUL `"$cronUrl`""
        $how = "curl.exe $cronUrl"
    } else {
        $php = Join-Path (Get-PHPDir $Config.PHPVersion) "php.exe"
        $a2  = New-ScheduledTaskAction -Execute $php -Argument "-f vtigercron.php" -WorkingDirectory $Config.WebRoot
        $how = "php.exe -f vtigercron.php"
    }
    $tr2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
    $s2  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $t2 -Action $a2 -Trigger $tr2 -Principal $p -Settings $s2 | Out-Null
    Write-Ok "Task '$t2' registered (every 15 min, $how)."
    if ($mode.Why) { Write-Host "    Reason: $($mode.Why)" }
}

# Decides how the Vtiger cron task calls vtigercron.php.
#
# curl.exe over HTTP only works when vtigercron.php accepts web requests.
# Stock Vtiger 7/8 runs the jobs only for the command line or a logged-in
# admin session:
#     if (vtigercron_detect_run_in_cli() || (isset($_SESSION["authenticated_user_id"]) ...
# (older builds: if (PHP_SAPI === "cli" || ...) and answers everything else
# with "Access denied!" and HTTP 200. curl would then report success while no
# cron job ever runs. php.exe passes that check on every build, so it is the
# choice whenever the check is present or the file cannot be read.
function Get-VtigerCronMode {
    $curl = Join-Path $env:SystemRoot "System32\curl.exe"
    $hasCurl = Test-Path -LiteralPath $curl
    $forced = "$($Config.VtigerCronMode)".ToLowerInvariant()
    $file = Join-Path $Config.WebRoot "vtigercron.php"
    $gated = $true
    $why = ""
    if (Test-Path -LiteralPath $file) {
        $src = [IO.File]::ReadAllText($file)
        $gated = ($src -match '(?im)^\s*if\s*\(.*(vtigercron_detect_run_in_cli\s*\(|PHP_SAPI\s*={2,3}\s*[''"]cli[''"])')
    } else { $why = "vtigercron.php not found in $($Config.WebRoot)." }

    if ($forced -eq "php") { return [pscustomobject]@{ Mode = "php"; Exe = ""; Why = "VtigerCronMode = php in Config." } }
    if ($forced -eq "curl") {
        if (-not $hasCurl) { return [pscustomobject]@{ Mode = "php"; Exe = ""; Why = "VtigerCronMode = curl, but curl.exe is not in System32 (Windows Server 2016)." } }
        # The ParsVT vtigercron.php accepts this call even though it still has
        # the stock command-line check, so the check is not reported here.
        if ($why) { Write-Warn "VtigerCronMode = curl: $why The cron task fails until the file exists." }
        return [pscustomobject]@{ Mode = "curl"; Exe = $curl; Why = "" }
    }
    if (-not $hasCurl) { return [pscustomobject]@{ Mode = "php"; Exe = ""; Why = "curl.exe is not in System32 (Windows Server 2016)." } }
    if ($gated) {
        if ($why) { $why += " Using the command-line run." }
        else { $why = "vtigercron.php runs only from the command line or an admin session; over HTTP it would answer 'Access denied!'." }
        return [pscustomobject]@{ Mode = "php"; Exe = ""; Why = $why }
    }
    return [pscustomobject]@{ Mode = "curl"; Exe = $curl; Why = "vtigercron.php has no command-line-only check, so it runs over HTTP." }
}

# =============================================================================
# Shortcuts and system PATH
# =============================================================================

# WScript.Shell cannot set "Run as administrator"; it is the RunAsUser bit
# (0x2000) of the LinkFlags field at offset 0x14 of the .lnk file.
function Set-ShortcutRunAsAdmin {
    param([string]$LnkPath)
    $b = [IO.File]::ReadAllBytes($LnkPath)
    if ($b.Length -lt 0x18 -or $b[0] -ne 0x4C -or $b[4] -ne 0x01 -or $b[5] -ne 0x14 -or $b[6] -ne 0x02) {
        Write-Warn "$LnkPath is not a shell link; tick 'Run as administrator' in its properties by hand."
        return
    }
    $b[0x15] = $b[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($LnkPath, $b)
}

function Install-Shortcuts {
    Write-Step "Creating restart shortcuts..."
    if ($DryRun) { Write-Host "  [DRY] Write .cmd files to $($Config.ShortcutsDir) and .lnk files to the all-users Desktop and Start Menu"; return }
    New-Dir $Config.ShortcutsDir
    $httpd = Join-Path $Config.ApacheDir "bin\httpd.exe"

    # The web server script tests the configuration first, so a broken
    # httpd.conf never turns a restart into an outage.
    $webCmd = @"
@echo off
echo Testing Apache configuration...
"$httpd" -t
if errorlevel 1 (
    echo.
    echo Apache configuration has errors. Apache was NOT restarted.
    pause
    exit /b 1
)
net stop "$($Config.ApacheService)"
net start "$($Config.ApacheService)"
pause
"@
    $dbCmd = @"
@echo off
net stop "MariaDB"
net start "MariaDB"
pause
"@
    $items = @(
        @{ File = "Restart-ParsVT-Webserver.cmd"; Text = $webCmd; Name = "Restart ParsVT Webserver"; Desc = "Test the Apache configuration and restart Apache" },
        @{ File = "Restart-ParsVT-Database.cmd";  Text = $dbCmd;  Name = "Restart ParsVT Database";  Desc = "Restart the MariaDB service" }
    )
    # All-users folders: the admin who manages the server later is often not
    # the account that ran the installer.
    $folders = @()
    foreach ($f in @("CommonDesktopDirectory", "CommonPrograms")) {
        $p = [Environment]::GetFolderPath($f)
        if ($p -and (Test-Path $p)) { $folders += $p } else { Write-Warn "Folder '$f' is not available on this system (Server Core?); skipped." }
    }
    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($it in $items) {
            $cmdPath = Join-Path $Config.ShortcutsDir $it.File
            Write-TextFile $cmdPath (($it.Text -replace "`r?`n", "`r`n") + "`r`n")
            foreach ($folder in $folders) {
                $lnk = Join-Path $folder "$($it.Name).lnk"
                $sc = $shell.CreateShortcut($lnk)
                $sc.TargetPath = Join-Path $env:SystemRoot "System32\cmd.exe"
                $sc.Arguments = "/c `"$cmdPath`""
                $sc.WorkingDirectory = $Config.ShortcutsDir
                $sc.Description = $it.Desc
                $sc.IconLocation = "$(Join-Path $env:SystemRoot 'System32\shell32.dll'),238"
                $sc.Save()
                Set-ShortcutRunAsAdmin $lnk
            }
        }
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    Write-Ok "Shortcuts created in: $($folders -join ', ')"
}

$script:EnvRegPath = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"

# Raw machine Path, without expanding %SystemRoot% and friends.
function Get-MachinePathRaw {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:EnvRegPath, $false)
    try {
        $v = [string]$k.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        try { $kind = $k.GetValueKind("Path") } catch { }
        return [pscustomobject]@{ Value = $v; Kind = $kind }
    } finally { $k.Close() }
}

# Writes the machine Path keeping its registry type (REG_EXPAND_SZ normally).
# [Environment]::SetEnvironmentVariable(...,'Machine') is not used: it can
# rewrite the value as REG_SZ and break %SystemRoot% references.
function Set-MachinePathRaw {
    param([string]$Value, $Kind)
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:EnvRegPath, $true)
    try { $k.SetValue("Path", $Value, $Kind) } finally { $k.Close() }
}

function Send-EnvironmentChange {
    try {
        if (-not ("ParsVT.NativeMethods" -as [type])) {
            Add-Type -Namespace ParsVT -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $result = [UIntPtr]::Zero
        # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 s
        $rc = [ParsVT.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, "Environment", 0x2, 5000, [ref]$result)
        if ($rc -eq [IntPtr]::Zero) { Write-Warn "WM_SETTINGCHANGE broadcast timed out; new shells may need a logoff to see the PATH." }
        else { Write-Ok "Environment change broadcast to running programs." }
    } catch {
        Write-Warn "Could not broadcast the environment change ($($_.Exception.Message)); new shells may need a logoff to see the PATH."
    }
}

function ConvertTo-PathKey { param([string]$P) return ([Environment]::ExpandEnvironmentVariables($P)).Trim().TrimEnd('\').ToLowerInvariant() }

function Install-PathEnvironment {
    Write-Step "Adding PHP and MariaDB to the machine PATH..."
    $phpDir = Get-PHPDir $Config.PHPVersion
    $mariaBin = Join-Path $Config.MariaDBDir "bin"
    $wanted = @()
    foreach ($d in @($phpDir, $mariaBin)) {
        if (Test-Path -LiteralPath $d -PathType Container) { $wanted += $d }
        else { Write-Warn "$d does not exist; not added to the PATH." }
    }
    if ($DryRun) { Write-Host "  [DRY] Append to HKLM Path: $($wanted -join ';')"; return }
    if ($wanted.Count -eq 0) { return }

    $cur = Get-MachinePathRaw
    $old = $cur.Value
    $entries = @($old -split ';' | Where-Object { $_.Trim() -ne "" })
    $keys = @($entries | ForEach-Object { ConvertTo-PathKey $_ })
    $added = @($wanted | Where-Object { $keys -notcontains (ConvertTo-PathKey $_) })

    # Another php.exe / mysql.exe earlier on the PATH keeps winning.
    foreach ($pair in @(@{ Dir = $phpDir; Tool = "php.exe" }, @{ Dir = $mariaBin; Tool = "mysql.exe" })) {
        $ours = ConvertTo-PathKey $pair.Dir
        foreach ($e in $entries) {
            $x = [Environment]::ExpandEnvironmentVariables($e).Trim().Trim('"')
            if ((ConvertTo-PathKey $x) -eq $ours) { break }
            # Stale entries (unmapped drives, quotes, bad characters) must not stop the install.
            $found = $false
            try { $found = ($x -and (Test-Path -LiteralPath ([IO.Path]::Combine($x, $pair.Tool)) -ErrorAction SilentlyContinue)) } catch { }
            if ($found) {
                if ($pair.Tool -eq "php.exe") {
                    Write-Warn "An existing PHP installation was found on the PATH. The new entry was appended, but the pre-existing php will still be used by default. If you want the ParsVT PHP to take precedence, move it earlier in the PATH manually."
                } else {
                    Write-Warn "Another mysql.exe ($x) is earlier on the PATH and will be used by default."
                }
                break
            }
        }
    }

    Write-Host "  Machine PATH before: $old"
    if ($added.Count -gt 0) {
        # Appended to the raw string: existing entries, their order and any
        # %VARIABLES% are kept exactly as they were.
        $new = $old.TrimEnd(';') + ';' + ($added -join ';')
        if (-not $old.Trim()) { $new = $added -join ';' }
        if ($new.Length -gt 1900) {
            Write-Warn "The machine PATH is $($new.Length) characters long; some older tools read only the first 2048 characters and may not see the new entries."
        }
        Set-MachinePathRaw -Value $new -Kind $cur.Kind
        Write-Host "  Machine PATH after:  $new"
        Write-Ok "Added to the machine PATH: $($added -join '; ')"
        Send-EnvironmentChange
        Write-Warn "Running services (Apache, MariaDB) see the new PATH only after a reboot; ParsVT itself does not depend on it."
    } else {
        Write-Ok "PHP and MariaDB are already on the machine PATH."
    }

    $procKeys = @($env:PATH -split ';' | ForEach-Object { ConvertTo-PathKey $_ })
    foreach ($d in $wanted) { if ($procKeys -notcontains (ConvertTo-PathKey $d)) { $env:PATH = $env:PATH.TrimEnd(';') + ";$d" } }
}

# =============================================================================
# phpMyAdmin
# =============================================================================

# Installed outside the web root on purpose: the CRM's .htaccess rules do not
# apply to it, nightly backups and restores do not carry its ~15,000 files,
# and it is reachable only through the /phpmyadmin Alias and its Require rule.
function Get-PhpMyAdminDir { return (Join-Path $Config.ApacheDir "phpmyadmin") }

function Get-PhpMyAdminUrl {
    if ($Config.SslEnabled -and $Config.Domain) { return "https://$($Config.Domain)/phpmyadmin/" }
    return ((Get-CrmUrl) + "phpmyadmin/")
}

function Get-PhpMyAdminPolicy {
    if ($Quick) { $a = "y" }
    else { $a = (Read-Host "Restrict phpMyAdmin to localhost and private networks? (recommended, y/n, default y)").Trim() }
    $Config.PhpMyAdminRestricted = ($a -notmatch '^[nN]')
    if ($Config.PhpMyAdminRestricted) { Write-Ok "phpMyAdmin: localhost and private networks only." ; return }
    Write-Warn "phpMyAdmin will be accessible from the internet. Only valid MariaDB credentials can log in, but brute-force attacks are possible. Consider adding a firewall rule or basic auth."
    Write-Warn "Until SSL is installed, the MariaDB password typed into phpMyAdmin crosses the network in plain text."
}

# Apache snippet for phpMyAdmin. PHP must be enabled here explicitly: the
# folder is outside the web root, so the fcgid handler of parsvt-php.conf
# does not cover it (without it the PHP source would be served as text).
function Get-PhpMyAdminApacheConf {
    param([string]$PmaDir, [string]$PHPDir, [bool]$Restricted)
    $p = ConvertTo-ApachePath $PmaDir
    $php = ConvertTo-ApachePath $PHPDir
    $re = [regex]::Escape($p)
    $require = "Require all granted"
    $scope = "none (reachable from the internet)"
    if ($Restricted) {
        $require = "Require ip 127.0.0.1 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
        $scope = "localhost and private networks"
    }
    return @"
# Managed by parsvt.ps1 - phpMyAdmin. Access: $scope
Alias /phpmyadmin "$p"
<Directory "$p">
    Options -Indexes +ExecCGI
    AllowOverride All
    DirectoryIndex index.php
    AddHandler fcgid-script .php
    FcgidWrapper "$php/php-cgi.exe" .php
    $require
</Directory>
# Internal folders are never served directly.
<DirectoryMatch "(?i)^$re/(libraries|templates|tmp|vendor|sql)(/|`$)">
    Require all denied
</DirectoryMatch>
"@
}

# config.inc.php with cookie authentication: no MariaDB password is stored.
# An existing file is kept, so a re-run does not log everyone out.
function Write-PhpMyAdminConfig {
    param([string]$PmaDir)
    $f = Join-Path $PmaDir "config.inc.php"
    if (Test-Path $f) { Write-Ok "Keeping existing $f"; return }
    if ($Config.DBHost -notmatch '^[A-Za-z0-9.\-:\[\]]+$') { throw "unexpected database host '$($Config.DBHost)'" }
    $secret = New-RandomPassword -Length 32
    $tmp = ConvertTo-ApachePath (Join-Path $PmaDir "tmp")
    $port = ""
    if ($Config.DBPort) { $port = "`$cfg['Servers'][`$i]['port'] = '$($Config.DBPort)';`r`n" }
    $php = @"
<?php
/* Generated by parsvt.ps1. Cookie authentication: the MariaDB password is
   typed in the browser for each session and is not stored here. */
declare(strict_types=1);

`$cfg['blowfish_secret'] = '$secret';

`$i = 0;
`$i++;
`$cfg['Servers'][`$i]['auth_type'] = 'cookie';
`$cfg['Servers'][`$i]['host'] = '$($Config.DBHost)';
$port`$cfg['Servers'][`$i]['compress'] = false;
`$cfg['Servers'][`$i]['AllowNoPassword'] = false;

`$cfg['TempDir'] = '$tmp';
`$cfg['UploadDir'] = '';
`$cfg['SaveDir'] = '';
"@
    Write-TextFile $f (($php -replace "`r?`n", "`r`n") + "`r`n")
}

# Best effort: any failure is reported and the CRM install carries on.
function Install-PhpMyAdmin {
    Write-Step "Installing phpMyAdmin $($Config.PhpMyAdminVersion)..."
    if ($DryRun) { Write-Host "  [DRY] Download $($Config.PhpMyAdminURL), extract to $(Get-PhpMyAdminDir), write parsvt-phpmyadmin.conf"; return }
    $dir = Get-PhpMyAdminDir
    $confFile = Join-Path $Config.ApacheDir "conf\extra\parsvt-phpmyadmin.conf"
    try {
        if (Test-Path (Join-Path $dir "index.php")) {
            Write-Ok "phpMyAdmin already installed, skipping."
        } else {
            # The .sha256 file phpMyAdmin publishes next to every release.
            $sha = ""
            try {
                $c = (Invoke-WebRequest "$($Config.PhpMyAdminURL).sha256" -UseBasicParsing -TimeoutSec 30).Content
                if ($c -is [byte[]]) { $c = [Text.Encoding]::ASCII.GetString($c) }
                $sha = ("$c".Trim() -split '\s+')[0]
                if ($sha -notmatch '^[0-9A-Fa-f]{64}$') { $sha = "" }
            } catch { }
            if (-not $sha) { Write-Warn "Could not read the phpMyAdmin SHA256 file; the download is not verified." }
            $zip = Join-Path $env:TEMP "phpMyAdmin-$($Config.PhpMyAdminVersion)-all-languages.zip"
            if (-not (Invoke-Download -Url $Config.PhpMyAdminURL -OutFile $zip -Sha256 $sha)) {
                Write-Warn "phpMyAdmin download failed; skipped. The CRM is not affected."
                return
            }
            $stage = Join-Path $env:TEMP "parsvt-pma-stage"
            Expand-ZipFile $zip $stage
            $inner = Get-ChildItem $stage -Directory | Where-Object { Test-Path (Join-Path $_.FullName "index.php") } | Select-Object -First 1
            if (-not $inner) { throw "unexpected phpMyAdmin archive layout (no */index.php)" }
            if (Test-Path $dir) { Move-Item $dir "$dir.incomplete-$(Get-Date -Format 'yyyyMMddHHmmss')" }
            Move-Item $inner.FullName $dir
            Remove-Item $zip, $stage -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($d in @("setup", "config")) {
                $x = Join-Path $dir $d
                if (Test-Path $x) { Remove-Item $x -Recurse -Force }
            }
            New-Dir (Join-Path $dir "tmp")
            Write-Ok "phpMyAdmin extracted to $dir (setup/ and config/ removed)."
        }
        Write-PhpMyAdminConfig $dir

        Write-TextFile $confFile (Get-PhpMyAdminApacheConf -PmaDir $dir -PHPDir (Get-PHPDir $Config.PHPVersion) -Restricted ([bool]$Config.PhpMyAdminRestricted))
        Add-HttpdInclude "parsvt-phpmyadmin.conf"
        if (-not (Restart-Apache)) {
            # Keep the file (empty) instead of deleting it: httpd.conf may already
            # include it from an earlier run, and a missing Include target stops Apache.
            Write-Warn "Apache rejected the phpMyAdmin configuration; it was disabled so the CRM keeps working."
            Write-TextFile $confFile "# Managed by parsvt.ps1 - phpMyAdmin disabled: Apache rejected the generated configuration`r`n"
            Restart-Apache | Out-Null
            return
        }
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$($Config.ApachePort)/phpmyadmin/" -UseBasicParsing -TimeoutSec 60
            if ($r.StatusCode -eq 200) { Write-Ok "phpMyAdmin answers on /phpmyadmin/ (HTTP 200)." }
            else { Write-Warn "phpMyAdmin returned HTTP $($r.StatusCode)." }
        } catch {
            $code = "no response"
            if ($_.Exception.Response) { $code = "HTTP $([int]$_.Exception.Response.StatusCode)" }
            Write-Warn "phpMyAdmin check failed ($code). See $(Join-Path $Config.ApacheDir 'logs\error.log') and $(Join-Path $Config.LogDir "php-$($Config.PHPVersion)-error.log")."
        }
        Save-CredentialsFile
    } catch {
        Write-Warn "phpMyAdmin installation failed: $($_.Exception.Message). The CRM is not affected."
    }
}

# =============================================================================
# SSL (win-acme)
# =============================================================================

# HTTP-01 validation (first issue and every renewal) always comes in on port 80.
# When Apache serves the CRM on another port, a port-80 vhost answers only the
# /.well-known/acme-challenge/ path.
function Set-AcmePort80 {
    $f = Join-Path $Config.ApacheDir "conf\extra\parsvt-acme.conf"
    if ([int]$Config.ApachePort -eq 80) {
        Write-TextFile $f "# Managed by parsvt.ps1 - Apache already listens on port 80`r`n"
        Add-HttpdInclude "parsvt-acme.conf"
        return $true
    }
    $owner = Get-PortOwner 80
    if ($owner -and $owner -ne "httpd") {
        Write-Err "Let's Encrypt validates on port 80, which is used by $owner. Free port 80 (or forward it to this server's Apache), then run the SSL step again."
        return $false
    }
    $web = ConvertTo-ApachePath $Config.WebRoot
    Write-TextFile $f @"
# Managed by parsvt.ps1 - port 80 only for Let's Encrypt HTTP-01 validation
Listen 80
<VirtualHost *:80>
    ServerName $($Config.Domain)
    DocumentRoot "$web"
    <LocationMatch "^/(?!\.well-known/acme-challenge/)">
        Require all denied
    </LocationMatch>
</VirtualHost>
"@
    Add-HttpdInclude "parsvt-acme.conf"
    Open-FirewallPort 80
    Write-Warn "Apache now also listens on port 80, for Let's Encrypt validation only."
    return $true
}

function Install-SSL {
    if (-not $Config.Domain) {
        $d = (Read-Host "Please enter your domain name (example.com)").Trim().ToLowerInvariant()
        $Config.Domain = ($d -replace '^https?://', '').TrimEnd('/').TrimEnd('.')
    }
    if (-not (Test-DomainName $Config.Domain)) { Write-Err "Invalid domain name '$($Config.Domain)'."; return $false }
    if ($DryRun) { Write-Host "  [DRY] Install SSL for $($Config.Domain)"; return $true }
    $owner443 = Get-PortOwner 443
    if ($owner443 -and $owner443 -ne "httpd") { Write-Err "Port 443 is used by $owner443."; return $false }

    $mainConf = Join-Path $Config.ApacheDir "conf\httpd.conf"
    $mainBackup = "$mainConf.parsvt-bak"
    Copy-Item $mainConf $mainBackup -Force
    $sslConf  = Join-Path $Config.ApacheDir "conf\extra\parsvt-ssl.conf"
    $acmeConf = Join-Path $Config.ApacheDir "conf\extra\parsvt-acme.conf"
    # Revert empties the managed files instead of deleting them: an earlier
    # run may have left Include lines for them, and a missing Include target
    # stops Apache from starting.
    $revert = {
        Write-Warn "Reverting SSL configuration."
        Copy-Item $mainBackup $mainConf -Force
        foreach ($f in @($sslConf, $acmeConf)) {
            if (Test-Path $f) { Write-TextFile $f "# Managed by parsvt.ps1 - disabled after a failed SSL setup`r`n" }
        }
        Restart-Apache | Out-Null
    }

    # The domain vhost must exist before validation (it may have been entered just now).
    Set-ApacheDomain
    if (-not (Set-AcmePort80)) { & $revert; return $false }
    if (-not (Restart-Apache)) { & $revert; return $false }
    Save-InstallState

    Write-Step "Downloading win-acme..."
    $zip = Join-Path $env:TEMP $Config.Downloads.WinAcme.File
    if (-not (Invoke-ConfiguredDownload "WinAcme" $zip)) { return $false }
    Expand-ZipFile $zip $Config.WinAcmeDir
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Set-DirAcl -Path $Config.WinAcmeDir -UsersRead
    $wacs = Get-ChildItem $Config.WinAcmeDir -Filter "wacs.exe" -Recurse | Select-Object -First 1
    if (-not $wacs) { Write-Err "wacs.exe not found."; return $false }

    New-Dir $Config.CertsDir
    Set-DirAcl -Path $Config.CertsDir     # private key: Administrators/SYSTEM only
    New-Dir (Join-Path $Config.WebRoot ".well-known\acme-challenge")

    # Reload hook: win-acme runs it after the first issue and every renewal,
    # otherwise Apache keeps serving the old certificate until it expires.
    $hook = Join-Path $Config.BackupScriptDir "apache-reload.ps1"
    $httpdA = Join-Path $Config.ApacheDir "bin\httpd.exe"
    Write-TextFile $hook "`$ErrorActionPreference = 'Continue'`r`n& '$httpdA' -t 2>&1 | Out-Null`r`nif (`$LASTEXITCODE -eq 0) { Restart-Service '$($Config.ApacheService)' -Force }`r`n"
    Set-FileAcl-AdminsOnly $hook

    $email = (Read-Host "Email for Let's Encrypt notifications").Trim()
    $r = Invoke-Native $wacs.FullName @("--source", "manual", "--host", $Config.Domain, "--validation", "filesystem",
        "--webroot", $Config.WebRoot, "--store", "pemfiles", "--pemfilespath", $Config.CertsDir,
        "--installation", "script", "--script", $hook, "--accepttos", "--emailaddress", $email) -Step "win-acme" -AllowFailure
    if (-not $r.Ok) {
        Write-Err "win-acme failed (exit $($r.ExitCode)):"
        @($r.All -split "\r?\n" | Where-Object { $_.Trim() }) | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }
        & $revert
        return $false
    }

    $chain = Join-Path $Config.CertsDir "$($Config.Domain)-chain.pem"
    $crt   = Join-Path $Config.CertsDir "$($Config.Domain)-crt.pem"
    $key   = Join-Path $Config.CertsDir "$($Config.Domain)-key.pem"
    $certFile = $crt
    if (Test-Path $chain) { $certFile = $chain }   # leaf + intermediates; Apache 2.4.8+ reads the chain from here
    if (-not (Test-Path $certFile) -or -not (Test-Path $key)) { Write-Err "Certificate files not found in $($Config.CertsDir)."; & $revert; return $false }

    $web = ConvertTo-ApachePath $Config.WebRoot
    # httpd-ssl.conf is NOT included: it adds its own Listen 443 and a default
    # vhost pointing at conf/server.crt, which does not exist (Apache would not start).
    $vhost = @"
# Managed by parsvt.ps1
<IfModule !ssl_module>
    LoadModule ssl_module modules/mod_ssl.so
</IfModule>
<IfModule !socache_shmcb_module>
    LoadModule socache_shmcb_module modules/mod_socache_shmcb.so
</IfModule>
Listen 443
SSLSessionCache "shmcb:logs/ssl_scache(512000)"
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder off

<VirtualHost *:443>
    ServerName $($Config.Domain)
    DocumentRoot "$web"
    SSLEngine on
    SSLCertificateFile "$(ConvertTo-ApachePath $certFile)"
    SSLCertificateKeyFile "$(ConvertTo-ApachePath $key)"
    ErrorLog "logs/parsvt-ssl-error.log"
    CustomLog "logs/parsvt-ssl-access.log" combined
</VirtualHost>
"@
    Write-TextFile $sslConf $vhost
    Add-HttpdInclude "parsvt-ssl.conf"
    if (-not (Restart-Apache)) { & $revert; return $false }
    Open-FirewallPort 443
    $Config.SslEnabled = $true
    Save-InstallState
    Save-CredentialsFile
    Write-Ok "SSL installed for $($Config.Domain). win-acme registered its own renewal task."
    Write-Warn "Update `$site_URL in config.inc.php to https://$($Config.Domain)/ when you switch users to HTTPS."
    return $true
}

# =============================================================================
# Summary
# =============================================================================

function Write-Summary {
    Suspend-InstallLog   # the password must not end up in the install log
    Write-Host ""
    Write-Host "  ParsVT installation successfully completed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  CRM URL:        $(Get-CrmUrl)" -ForegroundColor Yellow
    if ($Config.Domain) {
        $du = "http://$($Config.Domain)/"
        if ([int]$Config.ApachePort -ne 80) { $du = "http://$($Config.Domain):$($Config.ApachePort)/" }
        Write-Host "  Domain URL:     $du (once DNS points to this server)" -ForegroundColor Yellow
    }
    Write-Host "  CRM Username:   admin" -ForegroundColor Yellow
    Write-Host "  CRM Password:   $($Config.AdminPassword)" -ForegroundColor Yellow
    Write-Host ""
    Resume-InstallLog
    Write-Host "  PHP version:    $($Config.PHPVersion) (mod_fcgid)"
    Write-Host "  Apache:         $($Config.ApacheDir) (port $($Config.ApachePort))"
    Write-Host "  Web root:       $($Config.WebRoot)"
    Write-Host "  MariaDB:        running on port 3306"
    Write-Host "  Backup script:  $($Config.BackupScriptDir)\backup.ps1 (daily 22:00, 7 days)"
    Write-Host "  Restore script: $($Config.BackupScriptDir)\restore.ps1 (run elevated)"
    Write-Host "  Backup dir:     $($Config.BackupDir)"
    if (Test-Path (Join-Path (Get-PhpMyAdminDir) "index.php")) {
        $scope = "localhost and private networks only"
        if (-not $Config.PhpMyAdminRestricted) { $scope = "NOT restricted" }
        Write-Host "  phpMyAdmin:     $(Get-PhpMyAdminUrl) ($scope; MariaDB user and password)" -ForegroundColor Yellow
    }
    Write-Host "  Credentials:    $($Config.CredentialsFile) (Administrators only)" -ForegroundColor Yellow
    Write-Host ""
    Save-CredentialsFile
}

# =============================================================================
# Main flows
# =============================================================================

# Runs preflight.ps1 in this PowerShell process, so its output appears live
# and is recorded in the install transcript (and so in the support report).
# preflight.ps1 is read-only; its "exit" ends only preflight.ps1 itself.
# A FAIL stops the install before anything has been changed; WARN does not.
# A missing preflight.ps1 is not an error: the install continues.
function Invoke-Preflight {
    $pf = Join-Path $PSScriptRoot "preflight.ps1"
    if (-not (Test-Path -LiteralPath $pf)) {
        Write-Warn "preflight.ps1 was not found next to parsvt.ps1; the pre-installation checks are skipped."
        return
    }
    Write-Step "Checking this server before installing (read-only, 1-3 minutes)..."
    $fails = New-Object System.Collections.Generic.List[string]
    $lines = New-Object System.Collections.Generic.List[string]
    $global:LASTEXITCODE = 0
    # The transcript records redirected Write-Host output and the re-printed
    # line, so it is paused here and the lines are appended to it once.
    $hadLog = $script:TranscriptOn
    Suspend-InstallLog
    try {
        # 6>&1 brings Write-Host lines into the pipeline so the FAIL lines can
        # be collected; they are printed again with the same colours.
        & $pf -Installer $PSCommandPath 6>&1 | ForEach-Object {
            $line = "$_"
            $lines.Add($line)
            $color = "Gray"
            if ($line -match '^\[PASS\]') { $color = "Green" }
            elseif ($line -match '^\[WARN\]') { $color = "Yellow" }
            elseif ($line -match '^\[FAIL\]') { $color = "Red"; $fails.Add($line.Trim()) }
            Write-Host $line -ForegroundColor $color
        }
        $rc = $LASTEXITCODE
    } catch {
        Write-Warn "preflight.ps1 did not finish ($($_.Exception.Message)); continuing without it."
        return
    } finally {
        if ($hadLog -and $script:InstallLog) {
            try { Add-Content -Path $script:InstallLog -Value $lines -Encoding UTF8 } catch { }
            Resume-InstallLog
        }
    }
    if ($rc -eq 1 -or $fails.Count -gt 0) {
        Stop-Install ("The pre-installation checks found problems that block the installation. Nothing was installed.`r`n" + ($fails -join "`r`n")) 5
    }
    Write-Ok "Pre-installation checks passed."
}

# Root .htaccess: the error-page targets must be /modules/ParsVT/errors/
# because the CRM is always served from the URL root. Two generators get it
# wrong:
#   - the 2018 file in the CRM package: "/test/DEV/modules/ParsVT/errors/"
#     (a developer machine), plus "Options +Indexes" under a comment that
#     says "Disallow", which turns directory listing on for the whole CRM;
#   - ParsVT's security generator (Security::getDefault) on Windows:
#     dirname("/index.php") is "\" there, so ErrorDocument becomes
#     "\/modules/ParsVT/errors/". Apache reads a value that does not start
#     with "/" as a text message and prints it instead of the error page.
#     Its 8G RewriteRules also carry a fixed "/test/DEV0/" prefix.
# Any prefix in front of /modules/ParsVT/errors/ (except an http(s) URL) is
# dropped in ErrorDocument and RewriteRule targets; "+Indexes" becomes
# "-Indexes". Nothing else is touched; the original is kept as a backup.
# The generator writes the same values again whenever the ParsVT security
# settings are saved, so Repair has to be run again until it is fixed.
function Repair-RootHtaccess {
    $f = Join-Path $Config.WebRoot ".htaccess"
    if ($DryRun) { Write-Host "  [DRY] Check $f (error page paths, Options +Indexes)"; return }
    if (-not (Test-Path $f)) { return }
    $reDoc  = '(?im)^([ \t]*ErrorDocument[ \t]+\d{3}[ \t]+)(?!https?:)[^\s"]+?(/modules/ParsVT/errors/)'
    $reRule = '(?im)^([ \t]*RewriteRule[ \t]+\S+[ \t]+)(?!https?:)[^\s"]+?(/modules/ParsVT/errors/)'
    $reIdx  = '(?im)^([ \t]*Options[ \t]+(?:[-+]\w+[ \t]+)*)\+Indexes\b'
    try {
        $old = [IO.File]::ReadAllText($f)
        $docs  = ([regex]::Matches($old, $reDoc)).Count
        $rules = ([regex]::Matches($old, $reRule)).Count
        $idx   = ([regex]::Matches($old, $reIdx)).Count
        if ($docs + $rules + $idx -eq 0) { return }
        $new = [regex]::Replace($old, $reDoc, '$1$2')
        $new = [regex]::Replace($new, $reRule, '$1$2')
        $new = [regex]::Replace($new, $reIdx, '$1-Indexes')
        $bak = "$f.parsvt-bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Copy-Item $f $bak -Force
        Write-TextFile $f $new
        Write-Ok ".htaccess fixed (backup: $bak):"
        if ($docs)  { Write-Host "    $docs ErrorDocument line(s) now point at /modules/ParsVT/errors/" }
        if ($rules) { Write-Host "    $rules RewriteRule target(s) now point at /modules/ParsVT/errors/" }
        if ($idx)   { Write-Host "    directory listing turned off (Options -Indexes)" }
    } catch {
        Write-Warn "Could not check $f : $($_.Exception.Message)"
    }
}

# Status code and body for any HTTP status (Invoke-WebRequest in PS 5.1
# throws on 4xx/5xx and hides the body).
function Get-LocalHttp {
    param([string]$Path)
    $res = $null
    try {
        $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$($Config.ApachePort)$Path")
        $req.Timeout = 60000; $req.AllowAutoRedirect = $false
        try { $res = $req.GetResponse() } catch [Net.WebException] { $res = $_.Exception.Response }
        if (-not $res) { return @{ Code = 0; Body = "" } }
        $sr = New-Object IO.StreamReader($res.GetResponseStream())
        try { $body = $sr.ReadToEnd() } finally { $sr.Dispose() }
        return @{ Code = [int]$res.StatusCode; Body = $body }
    } catch {
        return @{ Code = 0; Body = "" }
    } finally { if ($res) { $res.Close() } }
}

# Warn-only checks of the two things Repair-RootHtaccess and PathInfoDirs fix.
function Test-WebRouting {
    if ($DryRun) { return }
    $log = Join-Path $Config.ApacheDir "logs\error.log"
    if (Test-Path (Join-Path $Config.WebRoot "modules\ParsVT\ws\Api.php")) {
        $r = Get-LocalHttp "/modules/ParsVT/ws/api/V2/vtiger/default/ping"
        if ($r.Code -eq 0) { Write-Warn "REST API check: no response from Apache." }
        elseif ($r.Body -match 'No input file specified') { Write-Warn "REST API URLs (ws/api/...) answer 'No input file specified'. See $log." }
        elseif ($r.Code -eq 404 -or $r.Code -ge 500) { Write-Warn "REST API check: /modules/ParsVT/ws/api/... returned HTTP $($r.Code). See $log." }
        else { Write-Ok "REST API URLs reach Api.php (HTTP $($r.Code) without credentials)." }
    }
    $r = Get-LocalHttp ("/parsvt-check-" + [Guid]::NewGuid().ToString("N"))
    if ($r.Body -match 'while trying to use an ErrorDocument') {
        Write-Warn "Error pages: an ErrorDocument in $(Join-Path $Config.WebRoot '.htaccess') points at a missing page; visitors see Apache's bare error page."
    } elseif ($r.Code -eq 404) { Write-Ok "Error pages: a missing page returns HTTP 404 through the CRM error page." }
}

function Main-Install {
    param([int]$VtigerVersion)
    $phpVer = $Config.VtigerToPHP[$VtigerVersion]
    $Config.PHPVersion = $phpVer
    $Config.VtigerVersion = $VtigerVersion
    $phpDownload = "PHP" + ($phpVer -replace '\.', '')

    if ($Quick -and -not $SkipPreflight) { Invoke-Preflight }
    if (-not (Install-VCRedist))    { Stop-Install "Visual C++ runtime installation failed." }
    if (-not (Get-LicenseInfo))     { Stop-Install "" }
    Get-ServerIP
    if (-not (Invoke-LicenseCheck)) { Stop-Install "" }
    Get-DomainName
    Get-InstallPaths
    Get-ApachePort
    Save-InstallState
    Add-DefenderExclusions
    Get-PhpMyAdminPolicy
    Save-InstallState

    $v = Test-WindowsVersion
    if (-not $v.Supported) { Write-Warn "Windows build $($v.Build) is older than Server 2016. Proceeding at your own risk." }

    if (-not (Install-Apache))                                     { Stop-Install "Apache installation failed." }
    if (-not (Install-PHP -Version $phpVer -DownloadName $phpDownload)) { Stop-Install "PHP installation failed." }
    if (-not (Install-IonCube -PHPVersion $phpVer))                { Stop-Install "ionCube installation failed." }
    if (-not (Set-ApachePHPConfig -PHPVersion $phpVer))            { Stop-Install "Apache/PHP configuration failed." }
    if (-not (Install-MariaDB))                                    { Stop-Install "MariaDB installation failed." }

    if (-not (Install-VtigerPackage -Version $VtigerVersion))      { Stop-Install "" }
    if (-not (Restart-Apache))                                     { Stop-Install "" }
    if (-not (Invoke-CRMInstall))                                  { Stop-Install "" }
    if (-not (Set-AdminPassword))                                  { Stop-Install "" }
    if (-not (Install-Extensions))                                 { Stop-Install "" }
    if (-not (Invoke-Wizard))                                      { Stop-Install "The CRM web installer failed. Check $($Config.ApacheDir)\logs and $($Config.LogDir)." }
    Repair-RootHtaccess
    Test-WebRouting

    if (-not (Install-BackupScript)) { Write-Warn "Backup script installation failed." }
    Install-ScheduledTasks
    Open-FirewallPorts
    if (-not $DryRun) { Set-DirAcl -Path $Config.PHPBaseDir -UsersRead }
    Save-InstallState
    Install-PathEnvironment
    Install-Shortcuts
    Install-PhpMyAdmin
    Write-Summary

    $doSsl = "n"
    if (-not $Quick) { $doSsl = Read-Host "Install SSL certificate now? (y/n)" }
    else { Write-Host "  Quick mode: SSL skipped. Run parsvt.ps1 without -Quick later to add a domain and SSL." }
    if ($doSsl -match "^[yY]") {
        if (Install-SSL) {
            Write-Host "  CRM URL (SSL): https://$($Config.Domain)/" -ForegroundColor Yellow
            if (Test-Path (Join-Path (Get-PhpMyAdminDir) "index.php")) { Write-Host "  phpMyAdmin:    $(Get-PhpMyAdminUrl)" -ForegroundColor Yellow }
        }
        else { Write-Warn "SSL installation failed - CRM works on HTTP only." }
    }
}

# Reads $dbconfig from config.inc.php. Each value is base64-encoded by PHP so
# any character (newline, quote, non-ASCII) survives the trip.
function Read-CRMDBConfig {
    $php = Join-Path (Get-PHPDir $Config.PHPVersion) "php.exe"
    $tmp = Join-Path $env:TEMP ("parsvt-readcfg-{0}.php" -f [Guid]::NewGuid().ToString("N"))
    $code = '<?php error_reporting(0); chdir($argv[1]); include "config.inc.php";' +
            ' foreach (array("db_server","db_username","db_password","db_name") as $k) {' +
            ' echo isset($dbconfig[$k]) ? base64_encode($dbconfig[$k]) : "", "\n"; }' +
            ' echo isset($site_URL) ? base64_encode($site_URL) : "", "\n";'
    try {
        Write-TextFile $tmp $code
        Set-FileAcl-AdminsOnly $tmp
        $r = Invoke-Native $php @($tmp, $Config.WebRoot) -Step "read config.inc.php" -AllowFailure
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    $v = @("$($r.Output)" -split "\r?\n" | ForEach-Object { $_.Trim() })
    if ($v.Count -lt 4 -or -not $v[1] -or -not $v[3]) { return $false }
    $dec = { param($s) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }
    $Config.DBHost        = & $dec $v[0]
    $Config.DBUser        = & $dec $v[1]
    $Config.MySQLPassword = & $dec $v[2]
    $Config.DBName        = & $dec $v[3]
    if ($Config.DBHost -match '^(.+):(\d+)$') { $Config.DBHost = $Matches[1]; $Config.DBPort = $Matches[2] }
    $script:CRMSiteURL = ""
    if ($v.Count -ge 5 -and $v[4]) { $script:CRMSiteURL = & $dec $v[4] }
    return $true
}

function Main-Repair {
    Write-Step "Repair mode"
    Write-Host "  Apache: $($Config.ApacheDir)  Web root: $($Config.WebRoot)  Port: $($Config.ApachePort)$(if ($Config.Domain) { "  Domain: $($Config.Domain)" })"
    if (-not (Test-Path (Join-Path $Config.WebRoot "config.inc.php"))) { Stop-Install "ParsVT is not installed at $($Config.WebRoot)." }
    $ver = Get-VtigerVersion
    if (-not $ver) { Stop-Install "Cannot detect Vtiger version." }
    $major = [int]($ver.Split(".")[0])
    $Config.VtigerVersion = $major
    $Config.PHPVersion    = $Config.VtigerToPHP[$major]
    Write-Ok "Detected Vtiger $ver -> PHP $($Config.PHPVersion)"
    $php = Join-Path (Get-PHPDir $Config.PHPVersion) "php.exe"
    if (-not (Test-Path $php)) { Stop-Install "PHP $($Config.PHPVersion) is not installed at $(Get-PHPDir $Config.PHPVersion)." }

    if (-not (Read-CRMDBConfig)) { Stop-Install "Cannot read db_server, db_username, db_password and db_name from config.inc.php. Nothing was changed." }
    Write-Ok "DB config: host=$($Config.DBHost) user=$($Config.DBUser) db=$($Config.DBName)"
    # Older install states have no ServerIP; the cron task needs it.
    if ($Config.ServerIP -eq "127.0.0.1" -and $script:CRMSiteURL -match '^https?://(\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?(/|$)') {
        $Config.ServerIP = $Matches[1]
        Write-Ok "Server IP from `$site_URL: $($Config.ServerIP)"
    }

    if (-not (Install-VCRedist))                              { Stop-Install "" }
    Stop-Apache
    if (-not (Install-PHP -Version $Config.PHPVersion -DownloadName ("PHP" + ($Config.PHPVersion -replace '\.', '')))) { Stop-Install "" }
    if (-not (Install-IonCube -PHPVersion $Config.PHPVersion)) { Stop-Install "" }
    if (-not (Set-ApachePHPConfig -PHPVersion $Config.PHPVersion)) { Stop-Install "" }
    if (-not (Restart-Apache))                                 { Stop-Install "" }
    Repair-RootHtaccess
    Test-WebRouting
    if (-not (Install-BackupScript))                           { Stop-Install "" }
    Install-ScheduledTasks
    Open-FirewallPorts
    Set-DirAcl -Path $Config.ApacheDir -UsersRead
    Set-DirAcl -Path $Config.PHPBaseDir -UsersRead
    Save-InstallState
    Install-PathEnvironment
    Install-Shortcuts
    Install-PhpMyAdmin
    Write-Ok "Repair complete."
}

function Main-IonCubeOnly {
    Write-Step "Updating ionCube..."
    Stop-Apache   # php-cgi processes hold the loader DLL open
    $failed = $false
    foreach ($v in @("7.4", "8.3")) {
        if (Test-Path (Join-Path (Get-PHPDir $v) "php.exe")) {
            if (-not (Install-IonCube -PHPVersion $v)) { $failed = $true }
        }
    }
    if (-not (Restart-Apache)) { $failed = $true }
    if ($failed) { Stop-Install "ionCube update finished with errors." }
    Write-Ok "ionCube updated."
}

# =============================================================================
# Bootstrap
# =============================================================================

if (-not (Test-Admin)) { Write-Err "This script must run as Administrator."; exit 2 }

Write-Host "ParsVT CRM Installer for Windows" -ForegroundColor Yellow
Write-Host "Version 2.11 - native PowerShell (no Cygwin, no XAMPP)" -ForegroundColor Yellow
if ($DryRun) { Write-Host "DRY RUN MODE - no changes will be made" -ForegroundColor Magenta }
if ($Quick)  { Write-Host "QUICK MODE - only the license key is asked; defaults are used for everything else" -ForegroundColor Magenta }
Write-Host ""

# Everything below runs inside one try/catch: any unexpected error ends in
# Stop-Install, which writes the support report and shows the message box.
# ("exit" is not an exception, so normal exits pass through unchanged.)
try {
    Start-InstallLog
    Import-InstallState
    if (-not (Test-Internet)) { Stop-Install "Cannot reach https://$($Config.PrimarySite)/ (no Internet connection, DNS problem, or a firewall/proxy blocks HTTPS)." 5 }

    $info = Get-SystemInfo
    if ($info.Panel -ne "none") {
        Write-Err "$($info.Panel) is installed on this server."
        Write-Host "  ParsVT installer will not run on panel-managed servers." -ForegroundColor Red
        Write-Host "  Use the panel's own tools to install." -ForegroundColor Yellow
        Stop-Install "$($info.Panel) is installed on this server; the ParsVT installer does not run on panel-managed servers." 3
    }

    if ($Quick -and (Test-Path (Join-Path $Config.WebRoot "config.inc.php"))) {
        # A second double-click on the launcher must never start a reinstall
        # (which only stops at the typed OVERWRITE after changing PHP and
        # Apache). Reinstalling is menu option 1 without -Quick.
        $choice = "3"
        Write-Host "Quick mode: ParsVT CRM is already installed at $($Config.WebRoot); running Repair (keeps all data)." -ForegroundColor Cyan
        Write-Host "  To reinstall from scratch, run parsvt.ps1 without -Quick and choose 1." -ForegroundColor Cyan
    }
    elseif ($Quick) { $choice = "1"; Write-Host "Quick mode: installing ParsVT CRM - Vtiger 8 / PHP 8.3." -ForegroundColor Cyan }
    else { $choice = Show-Menu }
    switch ($choice) {
        "1" { Main-Install -VtigerVersion 8 }
        "2" { Main-Install -VtigerVersion 7 }
        "3" { Main-Repair }
        "4" { Main-IonCubeOnly }
        "0" { Write-Host "Cancelled."; Suspend-InstallLog; exit 0 }
        default { Stop-Install "Invalid selection." 2 }
    }
} catch {
    # Invoke-Native (and any unexpected error) aborts the current step here.
    $where = ""
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) { $where = " (parsvt.ps1 line $($_.InvocationInfo.ScriptLineNumber))" }
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    Stop-Install "Step failed: $($_.Exception.Message)$where" 1
}

Write-Host "`nDone." -ForegroundColor Green
Suspend-InstallLog
exit 0
