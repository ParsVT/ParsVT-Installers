# راهنمای تست نصب‌کنندهٔ ویندوزی ParsVT (نسخهٔ 2.11)

این راهنما برای اولین تست واقعی `parsvt.ps1` نسخهٔ 2.11 روی Windows Server 2016، 2019 و 2022 است. فازها را به ترتیب انجام دهید. هر فاز از یک snapshot مشخص شروع می‌شود تا خرابی یک فاز روی فاز بعدی اثر نگذارد.

فایل‌هایی که روی سرور تست لازم دارید:

| فایل | کاربرد |
|---|---|
| `preflight.ps1` | بررسی‌های فقط‌خواندنی؛ قبل از هر نصب اجرا شود |
| `parsvt.ps1` | نصب‌کننده (نسخهٔ 2.11) |
| `Install ParsVT.cmd` | لانچر نصب سریع برای کاربر عادی (فاز 1b) |

> **نکته:** همهٔ دستورها، خروجی‌های مورد انتظار، مسیرها و آدرس‌ها عیناً به انگلیسی آمده‌اند تا بتوانید مستقیم کپی کنید.

---

## پیش‌نیازها (Prerequisites)

### آماده‌سازی ماشین مجازی

| تنظیم | مقدار |
|---|---|
| Hypervisor | Hyper-V یا VirtualBox |
| سیستم‌عامل | Windows Server 2016 Standard (Desktop Experience)؛ نسخهٔ evaluation هم کافی است |
| CPU / RAM / دیسک | 2 vCPU، 4 GB RAM، 40 GB دیسک (فقط درایو C:) |
| شبکه | NAT یا bridged، با دسترسی به اینترنت |
| فقط برای فاز 6 | IP عمومی (یا port forwarding) برای پورت‌های 80 و 443، و یک دامنهٔ واقعی |

بعد از نصب سیستم‌عامل:

1. منطقهٔ زمانی را تنظیم کنید و مطمئن شوید ساعت درست است (با ساعت اشتباه، بررسی TLS شکست می‌خورد).
2. IIS، XAMPP یا هیچ وب‌سرور دیگری نصب **نکنید**.
3. Windows Defender و Windows Firewall را روی تنظیمات پیش‌فرض بگذارید.
4. شمارهٔ build را یادداشت کنید: `[Environment]::OSVersion.Version` -> `10.0.14393.x` برای 2016.

### سیاست snapshot

| Snapshot | زمان گرفتن | استفاده در |
|---|---|---|
| **S0-clean** | سیستم‌عامل نصب شده، فایل‌ها کپی شده، هیچ چیز دیگر | فازهای 0، 1، 4، 5، 6 |
| **S1-installed** | پایان فاز 1، همهٔ نقاط کنترل قبول شده | فازهای 2 و 3 |
| **S2-after-restore** | پایان فاز 2 | فقط برای عیب‌یابی |

قبل از هر فاز به snapshot ذکرشده برگردید. هیچ‌وقت وسط تست «دستی درست کنید و ادامه دهید»؛ برگردید، گزارش بدهید و دوباره تست کنید.

### کپی اسکریپت‌ها روی سرور

یکی از این روش‌ها:

- **Hyper-V Enhanced Session / پوشهٔ اشتراکی VirtualBox**: هر دو فایل را در `C:\ParsVT-test\` کپی کنید.
- **Paste در Notepad**: متن را بچسبانید و با *Save As* و encoding **ANSI** یا **UTF-8** ذخیره کنید. هر دو اسکریپت فقط ASCII هستند، پس هر دو کار می‌کند. از Word، Outlook یا چت‌های rich-text کپی **نکنید**: آن‌ها `"` را به گیومهٔ خمیده تبدیل می‌کنند و اسکریپت parse نمی‌شود.
- **دانلود از gist یا سرور خودتان** (PowerShell 5.1 روی Server 2016 به‌طور پیش‌فرض TLS 1.2 را فعال نمی‌کند):

  ```powershell
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory C:\ParsVT-test -Force | Out-Null
  Invoke-WebRequest "https://<your-url>/parsvt.ps1"   -OutFile C:\ParsVT-test\parsvt.ps1   -UseBasicParsing
  Invoke-WebRequest "https://<your-url>/preflight.ps1" -OutFile C:\ParsVT-test\preflight.ps1 -UseBasicParsing
  Unblock-File C:\ParsVT-test\*.ps1
  ```

سالم بودن کپی را بررسی کنید (با hash روی سیستم خودتان مقایسه کنید):

```powershell
Get-FileHash C:\ParsVT-test\*.ps1 -Algorithm SHA256
```

همهٔ دستورهای این راهنما در **PowerShell باز شده با «Run as administrator»** اجرا می‌شوند.

### محل لاگ‌ها

| لاگ | محل |
|---|---|
| Transcript نصب‌کننده | `C:\parsvt-logs\install-YYYYMMDD-HHMMSS.log` |
| خطاهای PHP | `C:\parsvt-logs\php-8.3-error.log` (یا `php-7.4-error.log`) |
| پشتیبان‌گیری / بازگردانی | `C:\parsvt-logs\crm_backup.log`، `C:\parsvt-logs\crm_restore.log` |
| Apache | `C:\Apache24\logs\error.log`، `access.log`، `parsvt-ssl-*.log` |
| MariaDB | `C:\Program Files\MariaDB 10.11\data\<COMPUTERNAME>.err` |
| MSI مربوط به MariaDB (فقط اگر MSI شکست خورده و با `/l*v` دوباره اجرا شده) | `C:\parsvt-logs\mariadb-msi.log` |
| win-acme | `C:\ProgramData\win-acme\` |
| اطلاعات ورود (هرگز به گزارش پیوست نکنید) | `C:\parsvt-credentials.txt` |

**نکتهٔ حریم خصوصی:** `access.log` رمز دیتابیس را در آدرس `_install.php` دارد. روی VM تست مشکلی نیست؛ روی سرور مشتری، `access.log` را از هر چیزی که می‌فرستید حذف کنید.

---

## مرحلهٔ پیش‌بررسی (Pre-flight)

به **S0-clean** برگردید، سپس:

```powershell
cd C:\ParsVT-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
$LASTEXITCODE
```

preflight آدرس‌های دانلود را از `parsvt.ps1` در همان پوشه می‌خواند، پس دو فایل باید کنار هم باشند.

نتیجهٔ خوب این شکلی است:

| # | بررسی | مورد انتظار روی VM تمیز 2016 |
|---|---|---|
| 1 | نسخهٔ ویندوز | PASS (قبول)، build 14393 (Server 2016) |
| 2 | دسترسی Administrator | PASS |
| 3 | اینترنت | PASS برای https؛ http ممکن است WARN (هشدار) باشد (استفاده نمی‌شود) |
| 4 | گواهی aweb.co | PASS، با نمایش صادرکننده و تاریخ انقضا |
| 5 | DLLهای ionCube | PASS `NTS x64 (OK)` برای 7.4 و 8.3 |
| 6 | منابع دانلود | PASS برای Apache zip (`.../bin/httpd.exe` پیدا شود)، ModFcgid zip (مسیر `mod_fcgid.so` نمایش داده شود)، PHP83، MariaDB، VCRedist؛ برای PHP74/WinAcme، WARN قابل قبول است |
| 6 | VCRedist version | PASS با نسخهٔ 14.51.36247 یا بالاتر. اگر FAIL شد، فایل `VC_redist.x64.exe` روی license.aweb.co قدیمی است: نسخهٔ جدید را از `https://aka.ms/vc14/vc_redist.x64.exe` دانلود و جایگزین کنید |
| 7 | پورت‌های 80/443 | PASS (آزاد) |
| 8 | فضای دیسک | PASS (10 GB یا بیشتر آزاد) |
| 9 | VC++ runtime | WARN روی VM تمیز 2016 عادی است (نصب‌کننده آن را نصب می‌کند). حداقل لازم: 14.51.36247 برای Apache از نوع VS18 |
| 10 | سرویس‌های موجود | PASS برای Apache2.4، MariaDB، W3SVC |
| 11 | LongPathsEnabled | WARN روی 2016 عادی است (فقط اطلاع‌رسانی) |
| 12 | سیاست فایروال | PASS (local policy) روی VM غیر domain |
| 13 | چرخهٔ پشتیبانی | PASS قبل از 2027-01-12، WARN بعد از آن |
| 14 | فایل نصب‌کننده | PASS (یا WARN «blocked»: `Unblock-File` را اجرا کنید) |

کد خروج: `0` = ادامه دهید. `1` = **متوقف شوید**: موارد FAIL (رد) را درست کنید یا گزارش دهید (اگر بررسی 5 یا 6 رد شود، فایل‌های روی aweb.co یا منبع اصلی باید تغییر کنند، نه VM).

---

## فاز 0 (Phase 0) — اجرای آزمایشی (Dry run)

Snapshot: **S0-clean**.

```powershell
cd C:\ParsVT-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\parsvt.ps1 -DryRun
```

پاسخ‌ها: `1` (Vtiger 8)، یک کلید لایسنس با قالب درست (25 تا 26 کاراکتر، شروع با `ParsVT` یا `Cloud`؛ در dry run به سرور **ارسال نمی‌شود**)، Enter برای همهٔ پیش‌فرض‌ها، `n` برای Defender، `y` برای محدودیت phpMyAdmin، `n` برای SSL.

مورد انتظار:
- مراحل دانلود، نصب، SQL و فایل خطی با `[DRY] ...` چاپ می‌کنند. بعضی مراحل فقط عنوانشان را چاپ می‌کنند؛ اشکالی ندارد.
- هیچ خطایی (خط قرمز `[X]`) نباشد، به‌جز پیام اختیاری VC++.
- خلاصهٔ پایانی چاپ شود (با رمزهای خالی).

بررسی کنید که هیچ چیز تغییر نکرده:

```powershell
Get-ChildItem C:\ -Directory | Where-Object Name -in "Apache24","PHP","backup","parsvt-logs"   # nothing
Test-Path "C:\Program Files\ParsVT", C:\parsvt-credentials.txt                                    # False, False
Get-Service Apache2.4, MariaDB -ErrorAction SilentlyContinue                                     # nothing
Get-ScheduledTask -TaskName "ParsVT-*" -ErrorAction SilentlyContinue                             # nothing
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').Path      # unchanged
```

---

## فاز 1 (Phase 1) — نصب پیش‌فرض

Vtiger 8، پورت 80، مسیرهای پیش‌فرض، بدون دامنه، بدون SSL. Snapshot: **S0-clean**.

```powershell
cd C:\ParsVT-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\parsvt.ps1
```

پرسش‌ها به ترتیب:

| # | پرسش | پاسخ |
|---|---|---|
| 1 | `Please select an action (0-4)` | `1` |
| - | (Visual C++ runtime اینجا نصب می‌شود، بدون پرسش) | |
| 2 | `Please enter your ParsVT CRM license key` | لایسنس تست شما |
| 3 | `Please select an IP address` (فقط با 2 آدرس یا بیشتر) | IP شبکهٔ داخلی VM |
| 4 | `Please enter your domain name (leave blank to skip)` | Enter |
| 5 | `Apache base directory (default: C:\Apache24)` | Enter |
| 6 | `Web root directory (default: C:\Apache24\htdocs)` | Enter |
| 7 | `Please enter the web server port (default: 80)` | Enter |
| 8 | `Add these folders to Windows Defender exclusions?` | `y` |
| 9 | `Restrict phpMyAdmin to localhost and private networks? (recommended, y/n, default y)` | Enter (= `y`) |
| 10 | `Install SSL certificate now? (y/n)` | `n` |

رمز CRM را از خلاصهٔ پایانی یادداشت کنید (در `C:\parsvt-credentials.txt` هم هست).

### نقاط کنترل (Checkpoints)

| # | دستور | مورد انتظار |
|---|---|---|
| 1 | `Get-Service Apache2.4` | `Running` |
| 2 | `& C:\Apache24\bin\httpd.exe -t` | `Syntax OK` |
| 3 | `C:\PHP\8.3\php.exe -v` | `PHP 8.3.x (cli) ... NTS ...`، به‌اضافهٔ خطوط `with the ionCube PHP Loader` و `with Zend OPcache` |
| 4 | `C:\PHP\8.3\php.exe -m \| Select-String ionCube` | `the ionCube PHP Loader` |
| 5 | `Get-Service MariaDB` | `Running` |
| 5b | `Get-Service Apache2.4, MariaDB \| Select-Object Name, StartType`؛ `sc.exe qfailure Apache2.4`؛ `sc.exe qfailureflag Apache2.4` | هر دو `Automatic`؛ `RESET_PERIOD (in seconds) : 86400` و سه بار `RESTART -- Delay = 60000 milliseconds`؛ `FAILURE_ACTIONS_ON_NONCRASH_FAILURES: TRUE`. همین برای `MariaDB` |
| 5c | سرور را ری‌استارت کنید و **بدون ورود** CRM را از سیستم دیگری باز کنید | صفحهٔ ورود CRM باز می‌شود |
| 5d | `Stop-Process -Name httpd -Force` (شبیه‌سازی crash)، یک دقیقه صبر کنید، `Get-Service Apache2.4` | `Running` (ویندوز خودش دوباره اجرا کرده) |
| 6 | یک CMD **جدید** از منوی Start باز کنید (نه از همین پنجرهٔ PowerShell که PATH قدیمی را دارد): `mysql --version` | `mysql  Ver 15.1 Distrib 10.11.x-MariaDB, for Win64 (AMD64)` |
| 7 | مرورگر به `http://localhost/` (IE Enhanced Security روی Server صفحه‌ها را مسدود می‌کند؛ از سیستم دیگری `http://<VM-IP>/` را باز کنید، یا با `(Invoke-WebRequest http://localhost/ -UseBasicParsing).StatusCode` بررسی کنید) | صفحهٔ ورود Vtiger / `200` |
| 8 | ورود با `admin` و رمز موجود در `C:\parsvt-credentials.txt` | صفحهٔ اصلی CRM، با رابط فارسی اگر لایسنس شامل آن است |
| 9 | `Get-ScheduledTask -TaskName "ParsVT-*" \| Select-Object TaskName, State` | دقیقاً 2 مورد: `ParsVT-Backup` و `ParsVT-VtigerCron`، هر دو `Ready` (بدون `ParsVT-PHP*-FCGI`) |
| 10 | `Test-Path C:\backup` | `True` (تا اولین اجرای ساعت 22:00 خالی است) |
| 11 | `Get-ChildItem "C:\Users\Public\Desktop\Restart ParsVT*.lnk", "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Restart ParsVT*.lnk"` | 4 فایل (2 روی Desktop همهٔ کاربران، 2 در منوی Start) |
| 12 | در همان CMD **جدید** نقطهٔ کنترل 6: `echo %PATH%` و `where php` | PATH شامل `C:\PHP\8.3` و `C:\Program Files\MariaDB 10.11\bin` است؛ `where php` مقدار `C:\PHP\8.3\php.exe` را چاپ می‌کند |
| 13 | `Test-Path C:\Apache24\htdocs\.well-known\acme-challenge` | **`False`**. این پوشه فقط در مرحلهٔ SSL ساخته می‌شود و در فاز 6 مقدار `True` می‌گیرد |

بررسی‌های تکمیلی (5 دقیقه؛ محتمل‌ترین مشکلات دنیای واقعی را پیدا می‌کنند):

| بررسی | دستور / کار | مورد انتظار |
|---|---|---|
| پرچم Run as administrator | `([IO.File]::ReadAllBytes("C:\Users\Public\Desktop\Restart ParsVT Webserver.lnk")[0x15] -band 0x20) -ne 0` | `True`؛ دابل‌کلیک روی میانبر پنجرهٔ UAC را نشان می‌دهد |
| PHP همزمان | `Get-Process php-cgi \| Measure-Object` هنگام بارگذاری CRM | 2 پروسه یا بیشتر |
| Cron | `cd C:\Apache24\htdocs; C:\PHP\8.3\php.exe -f vtigercron.php` | خطوطی که با `[CRON]` شروع می‌شوند، نه `Access denied!` |
| تسک Cron | 15 دقیقه صبر کنید، `Get-ScheduledTaskInfo ParsVT-VtigerCron` | `LastTaskResult` = `0` |
| روش اجرای Cron | `(Get-ScheduledTask ParsVT-VtigerCron).Actions \| Format-List Execute, Arguments` | Server 2019/2022: `C:\Windows\System32\curl.exe` با `-fsS --max-time 900 -o NUL "http://<SERVER-IP>/vtigercron.php"` (IP انتخاب‌شده هنگام نصب؛ روی پورت غیر 80 با `:<port>`؛ **نه** `127.0.0.1`). Server 2016: `C:\PHP\8.3\php.exe` با `-f vtigercron.php` (curl.exe ندارد) |
| Cron از طریق HTTP واقعاً اجرا می‌شود | `& "$env:SystemRoot\System32\curl.exe" -sS http://<SERVER-IP>/vtigercron.php` | خطوطی که با `[CRON]` شروع می‌شوند. اگر فقط `Access denied!` چاپ شد، `vtigercron.php` نسخهٔ ParsVT نیست و هیچ job اجرا نمی‌شود (پایین، «الگوهای خطا») |
| آپلود | یک فایل 5 تا 10 مگابایتی به یک رکورد پیوست کنید | ذخیره می‌شود (`FcgidMaxRequestLen` را تست می‌کند) |
| متن فارسی | یک Contact با نام فارسی بسازید و صفحه را دوباره بارگذاری کنید | نام درست نمایش داده می‌شود |
| ماژول‌های اضافی PHP (مثل لینوکس) | `C:\PHP\8.3\php.exe -m \| Select-String "^(ldap\|odbc\|PDO_ODBC\|sockets)$"` | `ldap`، `odbc`، `PDO_ODBC`، `sockets` (در 7.4 به‌اضافهٔ `xmlrpc`) |
| ACLها | `icacls C:\backup` | فقط `BUILTIN\Administrators` و `NT AUTHORITY\SYSTEM` |
| Defender | `(Get-MpPreference).ExclusionPath` | `C:\Apache24\bin`، `C:\Apache24\modules`، `C:\PHP`، `C:\backup`، پوشهٔ `data` در MariaDB؛ **نه** `C:\Apache24` یا `htdocs` |
| فایل اطلاعات ورود | `icacls C:\parsvt-credentials.txt` | فقط Administrators و SYSTEM |
| phpMyAdmin | `(Invoke-WebRequest http://localhost/phpmyadmin/ -UseBasicParsing).StatusCode` | `200` |
| phpMyAdmin، ورود | مرورگر به `http://localhost/phpmyadmin/`، کاربر `root`، رمز `MariaDB password` از `C:\parsvt-credentials.txt` | فهرست دیتابیس‌ها، شامل `parsvt` |
| phpMyAdmin، رمز خالی | ورود با `root` و رمز خالی | رد می‌شود: `Login without a password is forbidden by configuration (see AllowNoPassword)` |
| phpMyAdmin، پوشه‌های داخلی | `(Invoke-WebRequest http://localhost/phpmyadmin/libraries/ -UseBasicParsing -ErrorAction SilentlyContinue).StatusCode` یا مرورگر | `403 Forbidden` |
| phpMyAdmin، محل نصب | `Test-Path C:\Apache24\phpmyadmin\index.php, C:\Apache24\phpmyadmin\setup, C:\Apache24\htdocs\phpmyadmin` | `True`، `False`، `False` |
| REST API (آدرس کوتاه) | `curl.exe -s -i http://127.0.0.1/modules/ParsVT/ws/api/V2/vtiger/default/ping` (Server 2016 curl.exe ندارد: از سیستم دیگری یا مرورگر) | پاسخ JSON از Api.php (بدون نام کاربری معمولاً 401). **نباید** `No input file specified` باشد |
| REST API (آدرس مستقیم) | `curl.exe -s -i http://127.0.0.1/modules/ParsVT/ws/Api.php/V2/vtiger/default/ping` | همان پاسخ آدرس کوتاه |
| REST API با احراز هویت | `curl.exe -s -u admin:<ACCESS_KEY> http://127.0.0.1/modules/ParsVT/ws/api/V2/vtiger/default/ping` (Access Key از صفحهٔ My Preferences کاربر admin) | پاسخ موفق ping؛ هدر Authorization به PHP رسیده است |
| پروسه‌های php-cgi | بعد از دو بررسی بالا: `Get-CimInstance Win32_Process -Filter "Name='php-cgi.exe'" \| Select-Object -ExpandProperty CommandLine \| Sort-Object -Unique` | دو نوع: `php-cgi.exe` تنها، و `php-cgi.exe -d cgi.fix_pathinfo=0 -d cgi.discard_path=1 -d auto_prepend_file=...` |
| صفحهٔ خطا | `curl.exe -s -i http://127.0.0.1/parsvt-not-found` | `404` با صفحهٔ خطای ParsVT؛ **نه** متن `while trying to use an ErrorDocument` و **نه** متن خالی `/modules/ParsVT/errors/` |
| فهرست پوشه | `curl.exe -s -i http://127.0.0.1/modules/` (یا هر پوشه‌ای بدون index) | `403` یا صفحهٔ خطای ParsVT؛ **نه** `Index of /...` |
| .htaccess ریشه | `Select-String C:\Apache24\htdocs\.htaccess -Pattern "ErrorDocument\|Indexes"` و `Get-ChildItem C:\Apache24\htdocs\.htaccess.parsvt-bak-*` | همهٔ ErrorDocumentها `/modules/ParsVT/errors/` بدون پیشوند؛ `Options -Indexes`؛ یک فایل backup از نسخهٔ اصلی. خروجی نصب: `REST API URLs reach Api.php` و `Error pages: a missing page returns HTTP 404` |
| phpMyAdmin، رمز ذخیره‌نشده | `Select-String C:\Apache24\phpmyadmin\config.inc.php -Pattern "password"` | هیچ خطی (فقط auth_type = cookie) |

اگر همه قبول شد، VM را خاموش کنید و **S1-installed** را بگیرید.

### جمع‌آوری لاگ در صورت رد شدن یک نقطهٔ کنترل

Apache و MariaDB لاگ‌هایشان را باز نگه می‌دارند و `Compress-Archive` فایل‌های باز را قبول نمی‌کند؛ پس اول با robocopy (که فایل‌های اشتراکی را می‌خواند) کپی کنید و کپی را zip کنید:

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tmp   = "C:\test-report-$stamp"
$out   = "C:\test-report-$stamp.zip"
robocopy C:\parsvt-logs "$tmp\parsvt-logs" /E /R:1 /W:1 | Out-Null
robocopy C:\Apache24\logs "$tmp\apache-logs" /E /R:1 /W:1 | Out-Null
robocopy C:\Apache24\conf "$tmp\apache-conf" /E /R:1 /W:1 | Out-Null
robocopy "C:\Program Files\MariaDB 10.11\data" "$tmp\mariadb" *.err /R:1 /W:1 | Out-Null
Copy-Item C:\PHP\8.3\php.ini "$tmp\" -ErrorAction SilentlyContinue
Copy-Item "C:\Program Files\ParsVT\install-state.json" "$tmp\" -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskName "ParsVT-*" | Select-Object TaskName, State | Out-File "$tmp\tasks.txt"
Get-Service Apache2.4, MariaDB -ErrorAction SilentlyContinue | Out-File "$tmp\services.txt"
[Environment]::OSVersion.Version | Out-File "$tmp\os.txt"
Compress-Archive -Path "$tmp\*" -DestinationPath $out
Remove-Item $tmp -Recurse -Force
"Report: $out"
```

روی سرور مشتری، قبل از zip کردن `$tmp\apache-logs\access.log` را حذف کنید (رمز دیتابیس را در آدرس wizard دارد). فایل `config.inc.php` در phpMyAdmin هیچ رمزی ندارد و جمع‌آوری هم نمی‌شود.

---

## فاز 1b (Phase 1b) — نصب سریع با لانچر (کاربر عادی)

Snapshot: **S0-clean**. هدف این فاز: کسی که اطلاعات فنی ندارد، فقط با دابل‌کلیک نصب کند.

1. هر سه فایل `Install ParsVT.cmd`، `parsvt.ps1` و `preflight.ps1` را در یک پوشهٔ محلی بگذارید، مثلاً `C:\ParsVT-Setup`. (اگر از داخل ZIP اجرا شود، پیام می‌دهد که اول ZIP را extract کنید.)
2. روی `Install ParsVT.cmd` دابل‌کلیک کنید. ممکن است ویندوز هشدار «Open File - Security Warning» بدهد: **Run** را بزنید. در پنجرهٔ UAC، **Yes** را بزنید.
3. اول بررسی‌های preflight به‌طور خودکار اجرا می‌شوند (1 تا 3 دقیقه، فقط‌خواندنی). اگر یکی از بررسی‌ها FAIL باشد، **هیچ چیزی نصب نمی‌شود**، گزارش روی دسکتاپ ساخته می‌شود و پیام فارسی نمایش داده می‌شود (کد خروج 5). WARN نصب را متوقف نمی‌کند. اگر `preflight.ps1` کنار فایل‌ها نباشد، فقط یک هشدار چاپ می‌شود و نصب ادامه پیدا می‌کند.
4. سپس فقط کلید لایسنس پرسیده می‌شود. همهٔ موارد دیگر پیش‌فرض هستند: Vtiger 8، پورت 80، `C:\Apache24`، بدون دامنه، بدون SSL، phpMyAdmin محدود، و استثناهای Defender.
5. اگر CRM از قبل نصب باشد، باز هم باید `OVERWRITE` را تایپ کنید (این حفاظت حذف نشده است).
6. در پایان پنجره باز می‌ماند (`Press any key to continue`) تا خلاصهٔ انگلیسی را ببینید.

| بررسی | مورد انتظار |
|---|---|
| ترتیب | اول `Checking this server before installing ...` و خطوط `[PASS]`/`[WARN]`، سپس `Pre-installation checks passed.` |
| تعداد پرسش‌ها | فقط `Please enter your ParsVT CRM license key` |
| خروجی | خط `QUICK MODE - only the license key is asked ...` در ابتدا، و `Quick mode: SSL skipped ...` در انتها |
| بقیه | مانند نقاط کنترل 1 تا 13 فاز 1 |

برای تکرار سریع تست (وقتی preflight را قبلاً اجرا کرده‌اید)، می‌توانید آن را رد کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parsvt.ps1 -Quick -SkipPreflight
```

در حالت عادی (بدون `-Quick`)، preflight به‌طور خودکار اجرا نمی‌شود. تستر آن را جداگانه اجرا می‌کند (مرحلهٔ پیش‌بررسی).

### تست خطا و گزارش (حتماً انجام شود)

برای اینکه مسیر خطا را ببینید، عمداً یک خطا بسازید. پورت 80 را با یک listener موقت اشغال کنید و لانچر را اجرا کنید:

```powershell
$l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, 80); $l.Start()
# now double-click "Install ParsVT.cmd", enter the license key, wait for the error
$l.Stop()
```

| بررسی | مورد انتظار |
|---|---|
| پیام | پنجرهٔ فارسی راست‌به‌چپ با عنوان «خطا در نصب»، مسیر فایل گزارش، و جزئیات انگلیسی خطا (`Port 80 is used by ...`) |
| فایل | `ParsVT-Report-yyyyMMdd-HHmmss.zip` روی دسکتاپ؛ Explorer باز می‌شود و فایل انتخاب‌شده است |
| پنجرهٔ CMD | `The installer stopped with exit code 4.` |
| محتوای zip | `system-info.txt`، `parsvt-logs\`، و در صورت وجود `apache-logs\`، `apache-conf\`، `mariadb\`، `install-state.json` |
| بدون رمز | `parsvt-credentials.txt`، `backup.cnf` و هیچ `config.inc.php` در zip نیست |
| خطای preflight | با یک FAIL عمدی (مثلاً قطع اینترنت قبل از اجرا): پیام فارسی، کد خروج `5`، خطوط `[FAIL]` در بخش «جزئیات خطا»، و `Test-Path C:\Apache24` برابر `False` (هیچ چیز نصب نشده) |

بررسی رمزها در گزارش (بعد از یک نصب کامل، یک خطای عمدی بسازید تا لاگ‌ها رمز داشته باشند):

```powershell
$zip = Get-ChildItem "$env:USERPROFILE\Desktop\ParsVT-Report-*.zip" | Sort-Object LastWriteTime | Select-Object -Last 1
Expand-Archive $zip.FullName -DestinationPath C:\report-check -Force
$pw = (Select-String C:\parsvt-credentials.txt -Pattern '^MariaDB password:\s*(.+)$').Matches[0].Groups[1].Value
Get-ChildItem C:\report-check -Recurse -File | Select-String -SimpleMatch $pw     # no output
Get-ChildItem C:\report-check -Recurse -File | Select-String "db_password="       # only db_password=***REDACTED***
Remove-Item C:\report-check -Recurse -Force
```

> **نکته:** فایل zip رمزگذاری نشده است. PowerShell 5.1 ابزاری برای zip با رمز ندارد. به‌جای آن، رمزها قبل از ساخت zip از لاگ‌ها پاک می‌شوند و فایل‌های رمزدار اصلاً در zip قرار نمی‌گیرند. فایل روی دسکتاپ همان کاربر ساخته می‌شود.

---

## فاز 2 (Phase 2) — پشتیبان‌گیری و بازگردانی

Snapshot: **S1-installed**.

1. در CRM یک Contact با نام **before-backup** بسازید.
2. پشتیبان‌گیری را اجرا کنید (فایل `backup.cnf` را می‌خواند که فقط Administrators به آن دسترسی دارند، پس پنجره باید elevated باشد):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\ParsVT\backup.ps1"
   $LASTEXITCODE                       # 0
   Get-ChildItem C:\backup             # parsvt-db-YYYY-MM-DD.sql.gz and parsvt-files-YYYY-MM-DD.zip
   Get-Content C:\parsvt-logs\crm_backup.log -Tail 8
   ```

3. یک Contact با نام **after-backup** بسازید.
4. بازگردانی را اجرا کنید:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\ParsVT\restore.ps1"
   ```

   - جدیدترین پشتیبان (`[1]`) را انتخاب کنید.
   - بررسی کنید که خلاصه، تعداد جدول‌ها، تعداد ردیف‌ها، حجم دیتابیس و حجم web root فعلی را نشان می‌دهد.
   - `parsvt` را تایپ کنید (دقیقاً، با حروف کوچک).

5. بررسی:

   | بررسی | مورد انتظار |
   |---|---|
   | `$LASTEXITCODE` | `0` |
   | ورود به CRM (اگر نشست قبلی رد شد، دوباره وارد شوید) | **before-backup** وجود دارد، **after-backup** وجود ندارد |
   | `Get-ChildItem C:\backup\parsvt-db-prerestore-*.sql.gz` | یک فایل |
   | `Get-ChildItem C:\Apache24 -Directory -Filter "htdocs.prerestore-*"` | یک پوشه (web root قبلی) |
   | `Get-Service Apache2.4` | `Running` |
   | `Get-Content C:\parsvt-logs\crm_restore.log -Tail 12` | با `=== Restore completed successfully ...` تمام می‌شود |
   | `(Invoke-WebRequest http://localhost/phpmyadmin/ -UseBasicParsing).StatusCode` | `200` (phpMyAdmin بیرون از web root است و بازگردانی روی آن اثری ندارد) |

6. تست‌های منفی (هر کدام باید داده‌ها را دست‌نخورده بگذارد):

   | تست | روش | کد خروج مورد انتظار |
   |---|---|---|
   | تأیید اشتباه | `Parsvt` یا `yes` تایپ کنید | `2` |
   | لغو هنگام انتخاب | `x` تایپ کنید | `2` |
   | بازگردانی همزمان | یک بازگردانی را شروع کنید و در مرحلهٔ تأیید نگه دارید، دومی را در پنجرهٔ elevated دیگری اجرا کنید | دومی: `6` |
   | بدون elevated | از یک PowerShell غیر elevated اجرا کنید | `5` |

**S2-after-restore** را بگیرید.

---

## فاز 3 (Phase 3) — تعمیر (Repair)

Snapshot: **S1-installed**.

وضعیت فعلی را ثبت کنید:

```powershell
Get-ScheduledTask -TaskName "ParsVT-*" | Select-Object TaskName, @{n="Exec";e={$_.Actions.Execute}}, @{n="Args";e={$_.Actions.Arguments}} | Format-List
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').Path
Get-FileHash C:\Apache24\phpmyadmin\config.inc.php
```

`parsvt.ps1` را اجرا و `3` را انتخاب کنید. هیچ پرسشی ندارد.

بررسی:

| بررسی | مورد انتظار |
|---|---|
| ورود به CRM | کار می‌کند، داده‌ها تغییری نکرده‌اند |
| `C:\PHP\8.3\php.exe -m \| Select-String ionCube` | `the ionCube PHP Loader` |
| تسک‌های زمان‌بندی‌شده (همان دستور بالا) | همانند قبل |
| PATH ماشین (همان دستور بالا) | همانند قبل، **بدون ورودی تکراری** |
| `Get-ChildItem "C:\Users\Public\Desktop\Restart ParsVT*.lnk"` | همچنان 2 (بازنویسی شده، نه تکراری) |
| `& C:\Apache24\bin\httpd.exe -t` | `Syntax OK` |
| `Get-Content "C:\Program Files\ParsVT\install-state.json"` | `"Version": "2.11"`، همان مسیرها و پورت، `"PhpMyAdminRestricted": true` |
| خروجی Repair | `phpMyAdmin already installed, skipping.` و `phpMyAdmin answers on /phpmyadmin/ (HTTP 200).` |
| `Get-FileHash C:\Apache24\phpmyadmin\config.inc.php` | همانند قبل (blowfish_secret عوض نشده، پس کاربران خارج نمی‌شوند) |
| `.htaccess` ریشه | Repair دوباره فایل backup جدید **نمی‌سازد** (فایل قبلاً اصلاح شده) |
| روی سروری که با 2.10 نصب شده: Repair | خروجی: `.htaccess: 7 ErrorDocument line(s) now point at ...`، `directory listing turned off`، `REST API URLs reach Api.php`؛ بعد بررسی‌های REST API و صفحهٔ خطا در فاز 1 |

---

## فاز 4 (Phase 4) — پورت و مسیرهای سفارشی

Snapshot: **S0-clean**. اول preflight را اجرا کنید.

با منوی `1` و این پاسخ‌ها نصب کنید:

| پرسش | پاسخ |
|---|---|
| Apache base directory | `C:\Web\Apache24` |
| Web root directory | `C:\Web\Apache24\htdocs` |
| Web server port | `8080` |

بررسی:

| بررسی | مورد انتظار |
|---|---|
| `(Invoke-WebRequest http://localhost:8080/ -UseBasicParsing).StatusCode` | `200` |
| `http://<VM-IP>:8080/` از سیستم دیگر | صفحهٔ ورود (قانون فایروال کار می‌کند) |
| `Get-NetFirewallRule -DisplayName "ParsVT HTTP 8080"` | وجود دارد، `Enabled True` |
| `Select-String -Path C:\Web\Apache24\conf\extra\parsvt-base.conf -Pattern "^Listen\|^DocumentRoot"` | `Listen 8080`، `DocumentRoot "C:/Web/Apache24/htdocs"` |
| `Select-String -Path C:\Web\Apache24\conf\httpd.conf -Pattern "Listen"` | فقط `#parsvt# Listen 80` کامنت‌شده |
| `Test-Path C:\Apache24` | `False` |
| `Get-Content "C:\Program Files\ParsVT\install-state.json"` | مسیرهای سفارشی و پورت 8080 |
| `(Invoke-WebRequest http://localhost:8080/phpmyadmin/ -UseBasicParsing).StatusCode` | `200`؛ phpMyAdmin در `C:\Web\Apache24\phpmyadmin` |
| اجرای Repair (منوی `3`) | بدون پرسش دربارهٔ مسیر؛ با مسیرهای سفارشی کار می‌کند |
| میانبر «Restart ParsVT Webserver» | `C:\Web\Apache24\bin\httpd.exe -t` را اجرا و Apache را راه‌اندازی مجدد می‌کند |

---

## فاز 5 (Phase 5) — Vtiger 7

Snapshot: **S0-clean**. با منوی `2` نصب کنید، بقیه پیش‌فرض.

| بررسی | مورد انتظار |
|---|---|
| `http://localhost/` | صفحهٔ ورود Vtiger 7 |
| `C:\PHP\7.4\php.exe -v` | `PHP 7.4.33 ... NTS`، با ionCube loader |
| `C:\PHP\7.4\php.exe -m \| Select-String ionCube` | `the ionCube PHP Loader` |
| `C:\PHP\7.4\php.exe -m \| Select-String "^gd$"` | `gd` (در 7.4 به‌صورت `php_gd2.dll` ارائه می‌شود) |
| `Test-Path C:\PHP\8.3` | `False` (فقط نسخهٔ فعال PHP نصب می‌شود) |
| `where php` در CMD جدید | `C:\PHP\7.4\php.exe` |
| `http://localhost/phpmyadmin/` | صفحهٔ ورود phpMyAdmin (phpMyAdmin 5.2 با PHP 7.4 کار می‌کند) |
| ورود و بررسی‌های تکمیلی فاز 1 | مانند فاز 1 |

---

## فاز 6 (Phase 6) — دامنه و SSL

Snapshot: **S0-clean**. نیازمندی‌ها:

- یک دامنهٔ واقعی، مثلاً `test.example.com`، با **رکورد A** که به IP عمومی سرور اشاره کند.
- پورت‌های **80 و 443** از اینترنت قابل دسترسی باشند (اگر VM پشت NAT است، port forwarding).

قبل از شروع DNS را بررسی کنید:

```powershell
nslookup test.example.com 8.8.8.8      # must return the server's public IP
```

Let's Encrypt برای هر دامنه فقط 5 گواهی یکسان در هفته صادر می‌کند. اگر این فاز را زیاد تکرار می‌کنید، هر بار از subdomain متفاوتی استفاده کنید.

### 6a - پورت 80

با منوی `1`، دامنهٔ `test.example.com`، پورت Enter (80)، و پاسخ `y` به `Install SSL certificate now?` نصب کنید؛ یک آدرس ایمیل وارد کنید.

| بررسی | مورد انتظار |
|---|---|
| `https://test.example.com/` از مرورگری بیرون از شبکه | صفحهٔ ورود، گواهی معتبر، بدون هشدار |
| زنجیرهٔ گواهی (نمایشگر گواهی مرورگر، یا ssllabs.com) | leaf + intermediate مربوط به Let's Encrypt؛ «chain complete»، بدون «extra download» |
| `Get-ScheduledTask -TaskName "win-acme*"` | یک تسک، `win-acme renew (acme-v02.api.letsencrypt.org)` |
| `Test-Path C:\Apache24\htdocs\.well-known\acme-challenge` | `True` |
| `Select-String C:\Apache24\conf\extra\parsvt-domain.conf -Pattern ServerName` | `ServerName test.example.com` |
| hook تمدید | `$t = (Get-Process httpd)[0].StartTime; & "C:\Program Files\win-acme\wacs.exe" --renew --force; (Get-Process httpd)[0].StartTime -gt $t` -> `True` (Apache راه‌اندازی مجدد شده) |
| `icacls "C:\Program Files\ParsVT\certs"` | فقط Administrators و SYSTEM |
| خلاصه و `C:\parsvt-credentials.txt` | `phpMyAdmin: https://test.example.com/phpmyadmin/` |
| `https://test.example.com/phpmyadmin/` از بیرون شبکه | `403 Forbidden` (محدود به localhost و شبکهٔ خصوصی؛ رفتار درست) |

### 6b - پورت 8080 با SSL (اختیاری)

Snapshot **S0-clean**، پورت `8080`، همان دامنه (یا subdomain دیگر).

| بررسی | مورد انتظار |
|---|---|
| خروجی نصب‌کننده | هشدار اینکه Apache برای اعتبارسنجی Let's Encrypt روی پورت 80 هم گوش می‌دهد |
| `http://test.example.com/` | 403 (روی پورت 80 فقط `/.well-known/acme-challenge/` سرو می‌شود) |
| `http://test.example.com:8080/` و `https://test.example.com/` | صفحهٔ ورود |

---

## فاز 7 (Phase 7) — Windows Server 2019

یک VM جدید با Server 2019 (build 17763) و همان مشخصات. preflight را اجرا کنید، سپس نصب پیش‌فرض فاز 1 و نقاط کنترل 1 تا 13 به‌همراه بررسی‌های تکمیلی. تفاوت‌ها با 2016 را در جدول نتایج یادداشت کنید.

## فاز 8 (Phase 8) — Windows Server 2022

یک VM جدید با Server 2022 (build 20348). مانند فاز 7.

### جدول نتایج (پر کنید)

| فاز | 2016 | 2019 | 2022 | یادداشت |
|---|---|---|---|---|
| پیش‌بررسی | | | | |
| 0 اجرای آزمایشی | | n/a | n/a | |
| 1 نصب پیش‌فرض | | | | |
| 1b نصب سریع + گزارش خطا | | | | |
| 2 پشتیبان‌گیری/بازگردانی | | n/a | n/a | |
| 3 تعمیر | | n/a | n/a | |
| 4 پورت/مسیر سفارشی | | n/a | n/a | |
| 5 Vtiger 7 | | n/a | n/a | |
| 6 دامنه + SSL | | n/a | n/a | |

---

## جمع‌آوری لاگ (برای هر خطا)

از نسخهٔ 2.4، هر اجرای ناموفق به‌طور خودکار `ParsVT-Report-....zip` را روی دسکتاپ می‌سازد. اول همان فایل را بفرستید. اسکریپت زیر فقط برای وقتی است که گزارش خودکار ساخته نشده یا اطلاعات بیشتری لازم است.

از اسکریپت فاز 1 («جمع‌آوری لاگ در صورت رد شدن یک نقطهٔ کنترل») استفاده کنید. برای نصب با مسیر سفارشی (فاز 4)، `C:\Apache24` را با `C:\Web\Apache24` جایگزین کنید.

این‌ها را بفرستید:

1. `C:\test-report-<stamp>.zip`
2. خروجی کامل کنسول (همه را در پنجرهٔ PowerShell انتخاب و کپی کنید و در یک فایل متنی بچسبانید)
3. تصویر مرحلهٔ خطادار، اگر خروجی کنسول آن را نشان نمی‌دهد
4. گزارش خطا با قالب زیر

هرگز `C:\parsvt-credentials.txt` یا `C:\Program Files\ParsVT\backup.cnf` را نفرستید.

---

## قالب گزارش خطا (Bug report template)

برچسب‌ها فارسی‌اند؛ مقدارها را به **انگلیسی** بنویسید تا مستقیم قابل استفاده باشند.

```
فاز (Phase): Phase 1, checkpoint 7
سیستم‌عامل (OS): Windows Server 2016 build 14393.xxxx   ([Environment]::OSVersion.Version)
PowerShell: 5.1.14393.xxxx                              ($PSVersionTable.PSVersion)
نصب‌کننده (Installer): parsvt.ps1 v2.11, SHA256: ...
مورد انتظار (Expected): ...
نتیجهٔ واقعی (Actual): ...
متن دقیق خطا (Exact error text): ...
مراحل بازتولید (Steps to reproduce): ...
نتیجهٔ preflight.ps1: exit code X, FAIL/WARN lines: ...
لاگ‌های پیوست (Attached logs): test-report-XXXX.zip
شمارهٔ snapshot: S0 / S1 / S2
```

---

## الگوهای خطای شناخته‌شده

| نشانه | علت محتمل | بررسی |
|---|---|---|
| `httpd -t` بعد از نصب شکست می‌خورد | `mod_fcgid.so` وجود ندارد یا مسیر `FcgidWrapper` اشتباه است | `Test-Path C:\Apache24\modules\mod_fcgid.so`؛ `Select-String C:\Apache24\conf\extra\parsvt-php.conf -Pattern FcgidWrapper` باید به یک `php-cgi.exe` موجود اشاره کند |
| سرویس Apache اجرا نمی‌شود، خطای `VCRUNTIME140_1.dll` یا «side-by-side» | Visual C++ runtime قدیمی است | `(Get-Item C:\Windows\System32\vcruntime140.dll).VersionInfo.FileVersion` باید 14.51.36247 یا بالاتر باشد (Apache از نوع VS18) |
| Apache اجرا نمی‌شود، `AH00072: make_sock: could not bind` | پورت قبلاً اشغال شده (IIS، Skype، Apache دیگر) | `Get-NetTCPConnection -LocalPort 80 -State Listen` و `Get-Process -Id <OwningProcess>` |
| ionCube بارگذاری نمی‌شود | loader از نوع TS روی PHP از نوع NTS، loader ساخته‌شده برای build ID دیگری از PHP، یا loader اولین `zend_extension` نیست | `C:\PHP\8.3\php.exe -v` خطای PHP را نشان می‌دهد؛ بررسی 5 در preflight؛ `Select-String C:\PHP\8.3\php.ini -Pattern zend_extension` (ionCube باید قبل از opcache باشد)؛ بخش «ionCube و نسخهٔ VC» در پایین |
| خطای 500، و `End of script output before headers` / `FastCGI process exited unexpectedly` در `error.log` | PHP crash کرده یا یک DLL لازم وجود ندارد | `C:\PHP\8.3\php.exe -m` نباید هیچ هشداری چاپ کند؛ `C:\parsvt-logs\php-8.3-error.log` |
| آپلود یا import با 500 شکست می‌خورد | درخواست بزرگ‌تر از `FcgidMaxRequestLen` یا `post_max_size` است | `Select-String C:\Apache24\conf\extra\parsvt-php.conf -Pattern FcgidMaxRequestLen` -> `134217728` |
| گزارش طولانی بعد از حدود 11 دقیقه با 500 تمام می‌شود | به `FcgidIOTimeout 660` رسیده | محدودیت مورد انتظار است؛ `max_execution_time` خود PHP (600 ثانیه) باید زودتر متوقفش کند |
| اتصال MySQL رد می‌شود | سرویس MariaDB متوقف است یا رمز اشتباه است | `Get-Service MariaDB`؛ `& "C:\Program Files\MariaDB 10.11\bin\mysql.exe" --defaults-extra-file="C:\Program Files\ParsVT\backup.cnf" -e "SELECT 1"` |
| متن فارسی به‌صورت `???` یا کاراکترهای خراب نمایش داده می‌شود | charset دیتابیس یا جدول utf8/utf8mb4 نیست، یا charset اتصال | `mysql ... -e "SELECT table_name, table_collation FROM information_schema.tables WHERE table_schema='parsvt' LIMIT 20"`؛ `C:\PHP\8.3\php.exe -m \| Select-String mbstring` |
| تسک زمان‌بندی‌شده ساخته شده ولی هرگز اجرا نمی‌شود | تسک غیرفعال است، حساب اشتباه است، یا یک اجرا هنوز ادامه دارد | `Get-ScheduledTaskInfo ParsVT-VtigerCron` (`LastRunTime`، `LastTaskResult`)؛ Task Scheduler > History (اول «All Tasks History» را فعال کنید) |
| تسک cron «موفق» است ولی هیچ job اجرا نمی‌شود | `vtigercron.php` نسخهٔ استاندارد Vtiger است (نه نسخهٔ ParsVT) و به درخواست HTTP با `Access denied!` و کد 200 جواب می‌دهد؛ curl این را موفق حساب می‌کند | دستور «Cron از طریق HTTP» در فاز 1 را اجرا کنید. اگر `Access denied!` بود، یا `vtigercron.php` نسخهٔ ParsVT را بگذارید، یا در `parsvt.ps1` مقدار `VtigerCronMode` را در `$script:Config` روی `"php"` بگذارید و Repair (منوی `3`) را اجرا کنید |
| REST API با `No input file specified` (HTTP 404) | php-cgi بعد از rewrite در `.htaccess` (به `Api.php/<path>`) فایل اشتباه را باز می‌کند؛ نصب‌شده با 2.10 یا قبل‌تر، یا پوشهٔ `ws` در `PathInfoDirs` نیست | `Select-String C:\Apache24\conf\extra\parsvt-php.conf -Pattern "fix_pathinfo=0"` باید بلوک `<Directory ".../modules/ParsVT/ws">` را نشان دهد؛ `Test-Path C:\PHP\8.3\parsvt-pathinfo.php`؛ در غیر این صورت Repair (منوی `3`). موقتاً: آدرس مستقیم `ws/Api.php/V2/...` |
| همان خطا برای ماژول دیگری (غیر از `ws`) | آن ماژول هم آدرس‌ها را به `<script>.php/<path>` rewrite می‌کند | پوشه را (نسبت به web root، با `/`) به `PathInfoDirs` در `$script:Config` اضافه کنید و Repair را اجرا کنید |
| به‌جای صفحهٔ خطا فقط متن `/modules/ParsVT/errors/` نمایش داده می‌شود | `.htaccess` ریشه را تنظیمات امنیتی ParsVT روی Windows ساخته: `dirname()` در Windows برای ریشه `\` برمی‌گرداند و خط `ErrorDocument 404 \/modules/ParsVT/errors/` می‌شود؛ Apache مقداری را که با `/` شروع نشود متن پیام حساب می‌کند | `Select-String C:\Apache24\htdocs\.htaccess -Pattern 'ErrorDocument\|errors/\?log'`؛ Repair اصلاحش می‌کند. هر بار که تنظیمات امنیتی ParsVT ذخیره شود دوباره خراب می‌شود تا وقتی `modules/ParsVT/models/Security.php` اصلاح شود |
| Cron اجرا نمی‌شود بعد از تغییر IP سرور | تسک cron به IP زمان نصب درخواست می‌دهد | Repair (منوی `3`) را اجرا کنید؛ IP از `install-state.json` (یا `$site_URL` در `config.inc.php`) خوانده می‌شود |
| صفحهٔ خطای ساده Apache با `Additionally, a 404 Not Found error was encountered while trying to use an ErrorDocument` | `ErrorDocument` در `.htaccess` ریشه به مسیر سرور دیگری اشاره می‌کند (`/test/VT7/...` در بستهٔ فعلی) | `Select-String C:\Apache24\htdocs\.htaccess -Pattern ErrorDocument`؛ Repair آن را اصلاح می‌کند |
| `Cannot replace C:\PHP\8.3\ext\ioncube_loader_win_8.3.dll ... being used by another process` (نسخهٔ 2.10 و قبل) | php-cgi زیر Apache فایل loader را باز نگه داشته | در 2.11 اگر loader عوض نشده باشد کپی نمی‌شود، و اگر عوض شده باشد Apache چند ثانیه متوقف و دوباره اجرا می‌شود |
| دابل‌کلیک دوباره روی `Install ParsVT.cmd` روی سرور نصب‌شده | 2.11 به‌جای نصب جدید Repair اجرا می‌کند (داده‌ها حفظ می‌شوند) | خروجی: `Quick mode: ParsVT CRM is already installed ...; running Repair`. برای نصب از صفر: `parsvt.ps1` بدون `-Quick` و گزینهٔ `1` |
| `[SplitSQL] statement failed: -- ====... توابع تبدیل ...` در `php-8.3-error.log` | خط `DELIMITER ;;` در SQL توابع شمسی به‌عنوان query فرستاده می‌شود؛ بی‌خطر است و هر 17 تابع ساخته می‌شوند | `mysql ... -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='parsvt'"`؛ رفع در `modules/ParsVT/helpers/ParsDB.php` (SplitSQL) |
| `running scripts is disabled on this system` | Execution policy | از `powershell -ExecutionPolicy Bypass -File ...` استفاده کنید |
| اسکریپت با خطاهای عجیب مربوط به گیومه parse نمی‌شود | فایل از یک ویرایشگر rich-text ذخیره شده (گیومهٔ خمیده) | `Get-FileHash` را با فایل اصلی مقایسه کنید |
| backup.ps1 با access denied شکست می‌خورد | elevated اجرا نشده (`backup.cnf` فقط برای Administrators است) | از پنجرهٔ elevated اجرا کنید؛ تسک زمان‌بندی‌شده با SYSTEM اجرا می‌شود |
| قانون فایروال وجود دارد ولی CRM از شبکه در دسترس نیست | Group Policy قوانین محلی را نادیده می‌گیرد | بررسی 12 در preflight؛ `Get-NetFirewallProfile -PolicyStore ActiveStore` |
| `mysql` / `php` در پنجرهٔ جدید پیدا نمی‌شود | پنجره از نشست قدیمی باز شده، یا قبل از تغییر | CMD را از منوی Start باز کنید؛ PATH ماشین را در رجیستری بررسی کنید (دستور فاز 3) |
| phpMyAdmin در خلاصهٔ نصب نیست، با هشدار `phpMyAdmin installation failed` یا `download failed` | دانلود از files.phpmyadmin.net شکست خورده (CRM سالم است) | `Invoke-WebRequest https://files.phpmyadmin.net/phpMyAdmin/5.2.3/phpMyAdmin-5.2.3-all-languages.zip.sha256 -UseBasicParsing`؛ بعد از رفع، Repair (منوی `3`) آن را نصب می‌کند |
| phpMyAdmin با `phpMyAdmin disabled: Apache rejected the generated configuration` | Apache پیکربندی phpMyAdmin را نپذیرفته و غیرفعالش کرده (CRM سالم است) | `Get-Content C:\Apache24\conf\extra\parsvt-phpmyadmin.conf`؛ `& C:\Apache24\bin\httpd.exe -t`؛ بعد از رفع، Repair |

---

## ionCube و نسخهٔ VC

اگر فایل DLL از سایت رسمی ionCube دانلود شده باشد، ممکن است نسخه VC17 باشد. این کاملاً طبیعی است و با PHP 8.3 (که VC16 است) کار می‌کند، چون مایکروسافت Runtime مشترک دارد. اسکریپت فقط NTS و x64 بودن را چک می‌کند.

- قبل از کپی، اسکریپت سه چیز را بررسی می‌کند: معماری x64، اینکه DLL در import table خود `php8.dll` (برای 8.3) یا `php7.dll` (برای 7.4) دارد و نه `php8ts.dll` / `php7ts.dll`، و در پایان یک load test با خود PHP.
- تصمیم نهایی با PHP است: PHP شناسهٔ build خودش (مثلاً `API420230831,NTS,VS16`) را با شناسهٔ ثبت‌شده در loader مقایسه می‌کند. اگر PHP آن را نپذیرد، پیام خودش عیناً نمایش داده می‌شود، مثلاً:

  ```
  PHP said: Cannot load the ionCube PHP Loader - it was built with configuration API420230831,NTS,VS17, whereas running engine is API420230831,NTS,VS16
  ```

  در این حالت نصب متوقف می‌شود و فایل قبلی ionCube دست نمی‌خورد. loader مخصوص PHP 8.3 را از بستهٔ Non-TS x64 روی aweb.co بگذارید و گزینهٔ `4` (Update ionCube loader only) را اجرا کنید.
- برای دیدن اینکه کدام فایل نصب شد، خط `Downloaded ioncube_loader_win_8.3.dll: ... KB, SHA256 ...` را در خروجی یا `C:\parsvt-logs\install-*.log` ببینید.

---

## phpMyAdmin

- **آدرس:** `http://<IP>:<port>/phpmyadmin` (با پورت 80: `http://<IP>/phpmyadmin`؛ بعد از SSL: `https://<domain>/phpmyadmin`)
- **محل نصب:** `C:\Apache24\phpmyadmin` (بیرون از web root؛ فقط از طریق Alias با نام `/phpmyadmin` در دسترس است، در پشتیبان‌گیری شبانه نیست و بازگردانی روی آن اثری ندارد)
- **ورود:** نام کاربری دیتابیس (`root` یا کاربر دیگری از MariaDB)، رمز از `C:\parsvt-credentials.txt` (خط `MariaDB password`). phpMyAdmin رمز را ذخیره نمی‌کند (`auth_type = cookie`)؛ در هر نشست در مرورگر وارد می‌شود.
- **اگر `403 Forbidden`:** خط `Require ip` آدرس IP کلاینت شما را مسدود کرده. فایل `C:\Apache24\conf\extra\parsvt-phpmyadmin.conf` را ویرایش کنید و IP عمومی خود را به خط `Require ip` اضافه کنید، یا `Require ip ...` را با `Require all granted` جایگزین کنید، سپس Apache را راه‌اندازی مجدد کنید:

  ```powershell
  & C:\Apache24\bin\httpd.exe -t
  Restart-Service Apache2.4
  ```

  توجه: Repair این فایل را دوباره می‌سازد. برای تغییر دائمی، مقدار `PhpMyAdminRestricted` را در `C:\Program Files\ParsVT\install-state.json` به `false` تغییر دهید و Repair را اجرا کنید.
- **اگر خطای 500:** `C:\Apache24\logs\error.log` را بررسی کنید (و `C:\parsvt-logs\php-8.3-error.log`).
- **هشدار امنیتی:**
  - با `Require all granted` و بدون SSL، رمز MariaDB (معمولاً root) به‌صورت متن ساده از اینترنت عبور می‌کند. فقط بعد از نصب SSL، یا با محدودیت فایروال، باز کنید.
  - محدودیت `Require ip` فقط وقتی کار می‌کند که IP واقعی کلاینت به Apache برسد. پشت reverse proxy، CDN، یا NATی که آدرس مبدأ را عوض می‌کند، درخواست‌های اینترنت با IP خصوصی می‌رسند و این محدودیت عملاً بی‌اثر است.
