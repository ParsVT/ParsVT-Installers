# نصب‌کننده‌های خودکار ParsVT CRM

[English](README.en.md) | **فارسی**

اسکریپت‌های رسمی نصب خودکار **ParsVT CRM** (نسخهٔ فارسی Vtiger CRM) روی سرورهای لینوکس و ویندوز.

این اسکریپت‌ها کل مجموعه را نصب و تنظیم می‌کنند: وب‌سرور، PHP، MariaDB، ionCube، خود CRM، کارهای زمان‌بندی‌شده و پشتیبان‌گیری. تا حد ممکن کم سؤال می‌پرسند تا تنظیم دستی و خطای انسانی به حداقل برسد.

| سیستم‌عامل | اسکریپت | راهنمای کامل |
|---|---|---|
| لینوکس | [`linux/parsvt.sh`](linux/parsvt.sh) | [`linux/README.md`](linux/README.md) |
| Windows Server | [`windows/parsvt.ps1`](windows/parsvt.ps1) | [`windows/README.md`](windows/README.md) |

---

## 🚀 نصب سریع

پیش‌نیازها:

- کلید لایسنس معتبر ParsVT
- سرور **بدون کنترل‌پنل** (cPanel، DirectAdmin، Plesk و مانند آن‌ها). روی سرور دارای کنترل‌پنل، هر دو نصب‌کننده بدون هیچ تغییری متوقف می‌شوند.

### 🐧 لینوکس

با کاربر **root** اجرا کنید:

```bash
curl -fsSLO https://raw.githubusercontent.com/ParsVT/ParsVT-Installers/main/linux/parsvt.sh && bash parsvt.sh
```

اگر با root وارد نشده‌اید، بخش دوم را با `sudo bash parsvt.sh` اجرا کنید.

> **از `bash <(curl ...)` استفاده نکنید.** اگر دانلود شکست بخورد، bash یک فایل خالی را اجرا می‌کند و با کد 0 خارج می‌شود، که دقیقاً شبیه موفقیت است. دستور بالا فقط وقتی دانلود کامل شده باشد اسکریپت را اجرا می‌کند. فایل `parsvt.sh` هم روی سرور می‌ماند، و بعداً برای تعمیر، به‌روزرسانی ionCube، ارتقای PHP و SSL به آن نیاز دارید.

### 🪟 Windows Server

**PowerShell را با Run as administrator** باز کنید و این دستورها را paste کنید:

```powershell
$ErrorActionPreference = "Stop"; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = "C:\ParsVT-Setup"; New-Item -ItemType Directory -Path $dir -Force | Out-Null
$url = "https://raw.githubusercontent.com/ParsVT/ParsVT-Installers/main/windows"
foreach ($f in "parsvt.ps1", "preflight.ps1", "Install ParsVT.cmd") { Invoke-WebRequest -Uri "$url/$([uri]::EscapeDataString($f))" -OutFile (Join-Path $dir $f) -UseBasicParsing }
Start-Process -FilePath (Join-Path $dir "Install ParsVT.cmd") -Verb RunAs
```

کار هر بخش:

- `Stop`: اگر یکی از دانلودها شکست بخورد، هیچ چیزی اجرا نمی‌شود.
- `Tls12`: PowerShell 5.1 روی Server 2016 به‌طور پیش‌فرض از TLS 1.2 استفاده نمی‌کند و GitHub بدون آن وصل نمی‌شود.
- `C:\ParsVT-Setup`: فایل‌ها برای اجرای بعدی تعمیر (Repair) در این پوشه می‌مانند. پوشهٔ `%TEMP%` ممکن است هر زمانی پاک شود.

لانچر اول سرور را بررسی می‌کند (`preflight.ps1`) و بعد **فقط کلید لایسنس** را می‌پرسد.

**روش دستی:** سه فایل پوشهٔ [`windows`](windows) را در یک پوشهٔ محلی دانلود کنید، روی `Install ParsVT.cmd` راست‌کلیک کنید و **Run as administrator** را بزنید. اگر فایل‌ها را به‌صورت ZIP گرفته‌اید، اول کل ZIP را استخراج کنید.

---

## ✨ امکانات

- **بومی روی هر سیستم‌عامل:** Bash روی لینوکس؛ PowerShell 5.1 خود ویندوز، بدون XAMPP یا Cygwin.
- **مدیریت نسخهٔ PHP:** PHP 8.3 برای Vtiger 8 (پیشنهادی) یا PHP 7.4 برای Vtiger 7 (منسوخ). روی لینوکس، PHP یک سرور Vtiger 7 موجود را هم می‌توان ارتقا داد؛ این بخشی از مهاجرت به Vtiger 8 است.
- **امنیت در اولویت:**
  - رمزهای تصادفی قوی برای دیتابیس و کاربر `admin` در CRM.
  - فایل‌های حاوی رمز فقط برای root یا Administratorها قابل خواندن‌اند: روی لینوکس `/root/crm.txt` و `/root/mysql.txt`؛ روی ویندوز `C:\parsvt-credentials.txt` و `backup.cnf`.
  - سازگاری loader ionCube پیش از فعال شدن با PHP نصب‌شده بررسی می‌شود (روی ویندوز: NTS، x64 و build نسخهٔ PHP).
  - phpMyAdmin (ویندوز) به‌طور پیش‌فرض فقط از خود سرور و شبکه‌های داخلی در دسترس است و هیچ رمزی ذخیره نمی‌کند.
- **اجرای دوبارهٔ امن:** CRM موجود هیچ‌وقت بدون تأیید تایپی بازنویسی نمی‌شود. پوشهٔ قبلی کنار گذاشته می‌شود و پیش از جایگزینی از دیتابیس قبلی پشتیبان گرفته می‌شود. روی ویندوز، اگر CRM از قبل نصب باشد، حالت سریع به‌جای نصب، تعمیر انجام می‌دهد.
- **پشتیبان‌گیری خودکار:** پشتیبان روزانه از دیتابیس و فایل‌ها، همراه با اسکریپت بازگردانی.
  - لینوکس به تعدادی که هنگام نصب انتخاب می‌کنید نسخهٔ پشتیبان نگه می‌دارد.
  - ویندوز پشتیبان‌ها را 7 روز نگه می‌دارد.
- **عیب‌یابی داخلی (ویندوز):** اگر نصب شکست بخورد، یک فایل گزارش (zip) روی دسکتاپ ساخته می‌شود. رمزها از لاگ‌ها حذف می‌شوند و فایل‌های حاوی رمز هرگز داخل گزارش قرار نمی‌گیرند.
- **حالت سریع (ویندوز):** با `-Quick`، که `Install ParsVT.cmd` از آن استفاده می‌کند، فقط کلید لایسنس پرسیده می‌شود.

---

## 🖥️ سیستم‌عامل‌های پشتیبانی‌شده

### ویندوز

- Windows Server 2016، 2019 و 2022 (64 بیتی)
- اجزا: Apache 2.4 (Apache Lounge) با mod_fcgid، PHP نسخهٔ NTS، MariaDB 10.11، و در صورت نیاز phpMyAdmin و Let's Encrypt (win-acme)

### لینوکس

| خانواده | نسخه‌ها |
|---|---|
| RHEL | RHEL / CentOS 7 به بالا، AlmaLinux / Rocky / Oracle Linux 8 به بالا، Fedora 39 به بالا |
| Debian | Debian 11 به بالا، Ubuntu 20.04 به بالا، Linux Mint 21 به بالا، Pop!_OS 22.04 به بالا |

- اجزا: Apache (httpd یا apache2)، MariaDB، PHP (mod_php یا PHP-FPM).
- پشتیبانی از Fedora، Linux Mint و Pop!_OS در حد «best effort» است.
- EL7 به پایان عمر رسیده است؛ برای سرورهای جدید AlmaLinux 9 را انتخاب کنید.
- SUSE و openSUSE پشتیبانی **نمی‌شوند**.
- نسخه‌های جدیدتر از نسخه‌های تست‌شده با یک هشدار پذیرفته می‌شوند.
- فهرست دقیق نسخه‌های تست‌شده در [`linux/README.md`](linux/README.md) آمده است.

---

## 🛠️ استفادهٔ پیشرفته

### لینوکس

`parsvt.sh` یک منو با این گزینه‌ها نشان می‌دهد:

- نصب Vtiger 8 / PHP 8.3
- نصب Vtiger 7 / PHP 7.4
- نصب با اینترنت ملی (فقط AlmaLinux 9)
- تعمیر (Repair)
- به‌روزرسانی ionCube
- ارتقای PHP به 8.3
- نصب ClamAV
- نصب SSL
- تبدیل CentOS 7/8 به AlmaLinux 8

ارتقای PHP بدون منو هم اجرا می‌شود:

```bash
bash parsvt.sh --php-upgrade --dry-run    # show the plan, change nothing
bash parsvt.sh --php-upgrade --upgrade    # do it
```

### ویندوز

از یک PowerShell با دسترسی Administrator، داخل پوشهٔ `C:\ParsVT-Setup` اجرا کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parsvt.ps1 [-Quick] [-SkipPreflight] [-DryRun]
```

| پارامتر | کار |
|---|---|
| (بدون پارامتر) | منو: نصب Vtiger 8 یا 7، تعمیر، به‌روزرسانی ionCube. پورت، مسیرها، دامنه و SSL پرسیده می‌شوند |
| `-Quick` | فقط کلید لایسنس پرسیده می‌شود؛ بقیه پیش‌فرض است (پورت 80، `C:\Apache24`، بدون دامنه و SSL). اگر CRM از قبل نصب باشد تعمیر اجرا می‌شود |
| `-SkipPreflight` | همراه `-Quick`: بررسی پیش از نصب انجام نمی‌شود |
| `-DryRun` | کارهایی را که انجام می‌شود نشان می‌دهد، بدون هیچ تغییری |

بررسی پیش از نصب را می‌توانید خودتان هم اجرا کنید. این بررسی فقط می‌خواند و چیزی را تغییر نمی‌دهد، و پیش از نصب پیشرفته توصیه می‌شود:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
```

---

## 🆘 عیب‌یابی و پشتیبانی

### ویندوز

اگر نصب شکست بخورد، فایل `ParsVT-Report-<تاریخ>.zip` روی دسکتاپ ساخته می‌شود. آن را برای پشتیبانی ParsVT بفرستید.

لاگ‌ها:

- `C:\parsvt-logs` (نصب، PHP، پشتیبان‌گیری و بازگردانی)
- `C:\Apache24\logs\error.log`

### لینوکس

نصب‌کننده مراحل را در ترمینال نمایش می‌دهد. برای نگه داشتن یک نسخه از خروجی برای پشتیبانی، آن را با `script` اجرا کنید:

```bash
script -q -c "bash parsvt.sh" /root/parsvt-install.log
```

لاگ‌های دیگر:

- پشتیبان‌گیری و بازگردانی: `/var/log/crm_backup.log` و `/var/log/crm_restore.log`، و `/var/log/crm_backup.status` (نتیجهٔ آخرین پشتیبان‌گیری)
- Apache: `/var/log/httpd` یا `/var/log/apache2`

### راهنماهای کامل

راهنمای کامل نصب، نگهداری و عیب‌یابی هر سیستم‌عامل:

- [`linux/README.md`](linux/README.md)
- [`windows/README.md`](windows/README.md)

---

## 📄 مجوز

این پروژه نرم‌افزار انحصاری و متعلق به ParsVT است. هرگونه توزیع یا تغییر بدون مجوز ممنوع است.
وب‌سایت: [parsvt.com](https://www.parsvt.com)
