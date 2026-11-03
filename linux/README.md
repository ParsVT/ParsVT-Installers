# راهنمای اسکریپت نصب ParsVT CRM (`parsvt.sh`)

این راهنما برای نسخهٔ یکپارچهٔ `parsvt.sh` است. این نسخه کار سه فایل قبلی را یک‌جا انجام می‌دهد:

- نصب ParsVT CRM روی Vtiger 8 / PHP 8.3 (پیشنهادی)
- نصب ParsVT CRM روی Vtiger 7 / PHP 7.4 (منسوخ)
- ارتقای PHP به 8.3، که مرحلهٔ ۳ مهاجرت Vtiger 7.x به 8.4.0 است و قبلاً فایل جدای `parsvt-php83-upgrade.txt` بود

به‌علاوه: نصب با اینترنت ملی، تعمیر سرور، ionCube، ClamAV، SSL و تبدیل CentOS 7/8 به AlmaLinux 8.

---

## ۱. پیش‌نیازها

- اجرا با کاربر **root** و از طریق SSH. اگر root نیستید، اول `sudo su` بزنید.
- سرور **بدون کنترل‌پنل**. اگر cPanel، DirectAdmin، Plesk، CyberPanel، Vesta/Hestia یا aaPanel نصب باشد، اسکریپت فقط دستورالعمل همان پنل را چاپ می‌کند و با کد ۳ خارج می‌شود. هیچ نصب یا تعمیری انجام نمی‌شود (بخش ۴).
- دسترسی اینترنت (به‌جز گزینهٔ ۳، اینترنت ملی).
- کلید لایسنس معتبر ParsVT برای نصب.

## ۲. سیستم‌عامل‌های پشتیبانی‌شده

```
RHEL family:
  RHEL / CentOS 7+, AlmaLinux / Rocky / Oracle Linux 8+, Fedora 39+

Debian family:
  Debian 11+, Ubuntu 20.04+, Linux Mint 21+, Pop!_OS 22.04+

Newer versions within the listed families are accepted but not tested.
```

- نسخه‌های جدیدتر از نسخه‌هایی که تست شده‌اند پذیرفته می‌شوند، ولی اسکریپت همان پیام «accepted but not tested» را هنگام اجرا نشان می‌دهد. نسخه‌های تست‌شده:
  - CentOS، RHEL، Rocky و Oracle Linux تا 9
  - AlmaLinux تا 10
  - Fedora تا 40
  - Debian تا 12
  - Ubuntu تا 24.x
  - Mint و Pop!_OS تا 22
- Fedora، Linux Mint و Pop!_OS «best effort» هستند.
- **SUSE/openSUSE پشتیبانی نمی‌شود.** توزیع‌های مشتق‌شده که در لیست نیستند (مثلاً Kali یا EuroLinux) هم پشتیبانی نمی‌شوند.
- روی سیستم‌عامل پشتیبانی‌نشده، اسکریپت بعد از چاپ «System information» پیام `Operating system is not supported!` و لیست بالا را نشان می‌دهد. سپس **با کد ۴ خارج می‌شود** و منو نمایش داده نمی‌شود.

### نکتهٔ EL7 (CentOS 7 / RHEL 7)
نصب Vtiger 8 روی EL7 مجاز است، ولی این هشدار نمایش داده می‌شود:

> PHP 8.3 on EL7 via remi is deprecated and may fail — verify after install

- **نصب‌کننده:** بعد از هشدار ۱۰ ثانیه فرصت دارید با `Ctrl+C` لغو کنید، وگرنه نصب ادامه می‌یابد.
- **آپدیتر:** همین هشدار را نشان می‌دهد. فقط در حالت `--upgrade` ده ثانیه صبر می‌کند. حالت‌های `--check` و `--dry-run` چیزی تغییر نمی‌دهند و صبر نمی‌کنند.

EL7 از ۲۰۲۴ پایان عمر رسیده است. برای سرورهای جدید AlmaLinux 9 پیشنهاد می‌شود. برای سرورهای CentOS موجود، گزینهٔ ۹ را ببینید.

---

## ۳. اجرای سریع

```bash
curl -fsSL <آدرس parsvt.sh> -o /root/parsvt.sh
bash /root/parsvt.sh
```

> از شکل `bash <(curl ...)` استفاده نکنید. اگر دانلود شکست بخورد، bash یک فایل خالی اجرا می‌کند و با کد ۰ خارج می‌شود، که دقیقاً شبیه موفقیت است.

ترتیب خروجی در هر اجرا:

1. بنر ParsVT و لیست سیستم‌عامل‌های پشتیبانی‌شده
2. بلوک **System information**
3. اگر کنترل‌پنل باشد: دستورالعمل پنل و خروج با کد ۳
4. اگر سیستم‌عامل پشتیبانی نشود: پیام و خروج با کد ۴
5. در غیر این صورت: منو

نمونهٔ بلوک System information:

```
System information:
  Operating system    : AlmaLinux 9.4 (Seafoam Ocelot)
  OS family           : rhel
  OS major version    : 9
  Architecture        : x86_64 (kernel 5.14.0-...)
  Control panel       : none
  Package manager     : dnf
  Web server          : httpd
  PHP current         : 8.3 (SAPI: fpm)
  ionCube loader      : 14.4.0
  CRM at /var/www/html: Vtiger 8.4.0
```

نسخهٔ Vtiger به این ترتیب خوانده می‌شود:
1. `$vtiger_current_version` در `config.inc.php`
2. `define('VTIGER_VERSION', ...)` در `vtigerversion.php`
3. `$vtiger_current_version` در `vtigerversion.php`، که روش استاندارد Vtiger است

اگر هیچ‌کدام پیدا نشود، `unknown` نمایش داده می‌شود. اگر `config.inc.php` وجود نداشته باشد، `none`.

---

## ۴. سرور دارای کنترل‌پنل

اگر پنل تشخیص داده شود، **هیچ عملیاتی اجرا نمی‌شود**: نه نصب، نه Repair، نه ارتقای PHP و نه تبدیل سیستم‌عامل. دلیلش این است که پنل خودش Apache و PHP را مدیریت می‌کند و تغییر مستقیم، پیکربندی پنل را خراب می‌کند. اسکریپت راه‌حل همان پنل را چاپ می‌کند:

| پنل | راه تنظیم PHP 8.3 و ionCube |
|---|---|
| cPanel / WHM | WHM > Software > MultiPHP Manager، سپس EasyApache 4 برای extensionها و Module Installers برای ionCube |
| DirectAdmin | `custombuild`: `./build set php1_release 8.3` ← `./build php n` ← `./build ioncube` |
| Plesk | `plesk installer --select-release-current --install-component php83` |
| CyberPanel | CyberPanel > PHP > Install Extensions |
| Vesta / HestiaCP | `v-add-web-php 8.3` |
| aaPanel | App Store ← نصب PHP-8.3، سپس PHP-8.3 ← Setting ← Install extensions برای ionCube و imap؛ تنظیم نسخهٔ PHP سایت روی 83 |

هیچ گزینه‌ای برای دور زدن این محدودیت وجود ندارد.

---

## ۵. گزینه‌های منو

| گزینه | کار |
|---|---|
| **1** | نصب ParsVT CRM روی Vtiger 8 / PHP 8.3 (پیشنهادی) |
| **2** | نصب ParsVT CRM روی Vtiger 7 / PHP 7.4 (**منسوخ**، PHP 7.4 از ۲۰۲۲ وصلهٔ امنیتی ندارد) |
| **3** | نصب با اینترنت ملی، فقط روی AlmaLinux 9. روی سرورهای دیگر غیرفعال نمایش داده می‌شود |
| **4** | تعمیر تنظیمات سرور (Repair) |
| **5** | نصب یا به‌روزرسانی ionCube loader |
| **6** | ارتقای PHP به 8.3 (زیرمنو: Check / Dry-run / Upgrade) |
| **7** | نصب ClamAV (برای سرورهای ضعیف توصیه نمی‌شود) |
| **8** | نصب گواهی SSL |
| **9** | تبدیل CentOS 7/8 به AlmaLinux 8. **فقط روی CentOS 7/8 بدون پنل نمایش داده می‌شود** |
| **0** | لغو |

### ۵.۱ نصب (گزینه‌های ۱، ۲ و ۳)

مراحل به ترتیب:

1. اگر CRM از قبل در `/var/www/html` باشد، اسکریپت هشدار می‌دهد و ۱۰ ثانیه برای `Ctrl+C` صبر می‌کند. **اگر ادامه دهید، داده‌های قبلی از بین می‌رود.**
2. بررسی اینترنت (ping و در صورت بسته بودن ICMP، اتصال TCP) و بررسی سیستم‌عامل و هشدارهای مربوط به آن.
3. انتخاب IP (اگر سرور چند IP داشته باشد).
4. وارد کردن کلید لایسنس: ۲۵ یا ۲۶ کاراکتر که با `ParsVT` یا `Cloud` شروع شود، حداکثر ۴ بار تلاش.
5. پرسش تعداد backupهایی که روی سرور نگه داشته شود (۱ تا ۳۶۵، پیش‌فرض ۷). فضای آزاد `/home` کنار پرسش نمایش داده می‌شود. پس از آن، پرسش استفاده از DNS شکن در طول نصب (در گزینهٔ ۳ پرسیده نمی‌شود).
6. غیرفعال‌سازی SELinux (فقط RHEL). روی Debian/Ubuntu، AppArmor دست نمی‌خورد.
7. به‌روزرسانی سیستم، نصب ابزارها و مخزن PHP:
   - **RHEL:** remi
   - **Ubuntu و مشتقات:** ondrej PPA
   - **Debian:** packages.sury.org
   - اگر خود توزیع آن نسخهٔ PHP را داشته باشد، مخزن جانبی اضافه نمی‌شود.
8. نصب Apache و PHP و ionCube، سپس timezonedb و تنظیمات php.ini (memory_limit=512M، max_execution_time=600، منطقهٔ زمانی Asia/Tehran و …).
9. نصب MariaDB. اگر MySQL از قبل نصب باشد، اطلاعات اتصال پرسیده می‌شود.
10. دانلود بستهٔ CRM:
    - Vtiger 7: `download.php?v=7`
    - Vtiger 8: `download.php?v=8`
    - بعد از unzip، نسخهٔ بسته بررسی می‌شود. اگر سرور نسخهٔ اشتباه برگرداند، نصب **قبل از هر تغییری در دیتابیس** متوقف می‌شود.
11. نصب Java، اسکریپت backup، Webmin (پورت 10000)، باز کردن پورت‌های فایروال و cron. اگر Java یا Webmin نصب نشوند فقط هشدار داده می‌شود، چون CRM در این مرحله نصب شده و اطلاعات ورود نباید از دست برود.

پس از نصب، این فایل‌ها ساخته می‌شوند (فقط root می‌تواند آن‌ها را بخواند):

| فایل | محتوا |
|---|---|
| `/root/crm.txt` | آدرس CRM، نام کاربری `admin` و رمز تصادفی |
| `/root/mysql.txt` | نام کاربری و رمز root دیتابیس |
| `/usr/local/bin/parsvt-backup.sh` | backup روزانهٔ دیتابیس و فایل‌ها، ساعت ۲۲:۰۰، در `/home/backup`. تعداد نگهداری هنگام نصب پرسیده می‌شود (لاگ: `/var/log/crm_backup.log`، نتیجهٔ آخرین اجرا: `/var/log/crm_backup.status`) |
| `/usr/local/bin/parsvt-restore.sh` | بازگردانی تعاملی (لاگ: `/var/log/crm_restore.log`)، بخش ۵.۶ |

cron مربوط به `vtigercron.php` هر ۱۵ دقیقه اجرا می‌شود.

**روی Debian/Ubuntu:**
- PHP به‌صورت `mod_php` نصب می‌شود.
- php.ini در مسیر `/etc/php/<ver>/apache2/php.ini` و `/etc/php/<ver>/cli/php.ini` است.
- فایل تنظیمات Apache در `/etc/apache2/conf-available/parsvt.conf` نوشته می‌شود.
- phpMyAdmin نصب نمی‌شود، چون نسخهٔ دوم PHP را هم نصب می‌کرد. برای مدیریت دیتابیس از Webmin استفاده کنید.

### ۵.۲ Repair (گزینهٔ ۴)

فقط وقتی کار می‌کند که `/var/www/html/config.inc.php` وجود داشته باشد. اول اطلاعات دیتابیس (`db_server`، `db_username`، `db_password` و `db_name`) را از `$dbconfig` همین فایل می‌خواند. اگر یکی از آن‌ها نباشد، Repair متوقف می‌شود. سپس اسکریپت‌های backup و restore را دوباره با دسترسی 700 نصب می‌کند و cron را اصلاح می‌کند: خط قدیمی `/home/backup-*.sh` حذف و خط جدید یک بار اضافه می‌شود. فایل قدیمی `/home/backup-<db>.sh` دست نمی‌خورد و پاک کردنش لازم نیست. بعد این موارد را بررسی و اصلاح می‌کند:

- مخزن remi (روی RHEL)
- نسخهٔ PHP و ionCube
- Apache
- timezonedb
- تنظیمات php.ini و Apache
- وجود MySQL
- Java
- مالکیت و دسترسی فایل‌های `/var/www/html`
- پورت‌های فایروال

اجرای دوباره‌اش مشکلی ایجاد نمی‌کند.

### ۵.۳ ionCube (گزینهٔ ۵)

نسخهٔ loader را بررسی می‌کند و در صورت نیاز آن را نصب یا به‌روز می‌کند. **همهٔ ماژول‌های ParsVT با ionCube رمزگذاری شده‌اند.** بدون loader مخصوص همان نسخهٔ PHP، CRM اصلاً بالا نمی‌آید.

### ۵.۴ ClamAV (گزینهٔ ۷)

ClamAV را نصب می‌کند و اسکن روزانه را ساعت ۰۲:۰۰ با `/usr/local/bin/daily_clamscan.sh` تنظیم می‌کند. لاگ در `/var/log/clamav/daily_scan.log` ذخیره می‌شود. اگر به‌روزرسانی امضاها از ایران مسدود باشد، نصب متوقف نمی‌شود و freshclam روزانه دوباره تلاش می‌کند.

### ۵.۵ SSL (گزینهٔ ۸)

فقط وقتی کار می‌کند که CRM نصب باشد.

1. نام دامنه را وارد می‌کنید.
2. تأیید می‌کنید که رکورد A دامنه به IP سرور اشاره می‌کند.
3. certbot گواهی را می‌گیرد.

تمدید خودکار گواهی:
- **Debian/Ubuntu:** `certbot.timer`
- **RHEL:** cron

### ۵.۶ بازگردانی از backup

```bash
/usr/local/bin/parsvt-restore.sh
```

1. فهرست مجموعه‌های backup موجود در `/home/backup` را نشان می‌دهد و شمارهٔ یکی را می‌پرسد.
2. سالم بودن هر دو فایل را پیش از هر تغییری بررسی می‌کند (`gzip -t` و `tar -tzf`).
3. آنچه از دست می‌رود را نشان می‌دهد: تعداد جدول‌ها و ردیف‌های تخمینی دیتابیس فعلی و حجم `/var/www/html`. برای ادامه باید **نام دیتابیس را دقیقاً تایپ کنید**.
4. نسخهٔ ایمنی از وضع فعلی می‌سازد: `parsvt-db-prerestore-<زمان>.sql.gz` و `parsvt-files-prerestore-<زمان>.tar.gz` در `/home/backup`. این دو در فهرست دفعهٔ بعد ظاهر می‌شوند، پس با همین ابزار می‌توانید بازگردانی را برگردانید.
5. دیتابیس را کامل پاک و دوباره ساخته می‌کند (`DROP` و سپس `CREATE` با utf8mb4)، dump را وارد می‌کند، فایل‌ها را استخراج می‌کند و مالکیت و دسترسی‌ها را مثل نصب‌کننده تنظیم می‌کند.
6. وب‌سرور را ری‌استارت می‌کند و آدرس CRM را نشان می‌دهد.

اجرای هم‌زمان دو restore ممکن نیست (کد خروج ۶). backupهای قدیمی پاک نمی‌شوند؛ حذف قدیمی‌ها کار اسکریپت backup است.

### ۵.۷ رفتار backup هنگام خطا یا پر شدن دیسک

- **backup سالم قبلی هرگز با یک backup ناقص جایگزین یا حذف نمی‌شود.** فایل‌های جدید اول با پسوند `.partial` نوشته می‌شوند و آزمایش می‌شوند: `gzip -t` و وجود خط پایانی `Dump completed` در dump. فقط بعد از موفقیت با نام اصلی جایگزین می‌شوند. اگر کار وسط راه شکست بخورد، فایل‌های `.partial` همان اجرا پاک می‌شوند و backupهای قبلی دست نمی‌خورند.
- **پیش از شروع، فضای دیسک تخمین زده می‌شود:** حجم خام دیتابیس، به‌علاوهٔ حجم `/var/www/html`، به‌علاوهٔ ۱ GB ذخیره. اگر کافی نباشد، backup اصلاً شروع نمی‌شود (کد ۵) تا پر شدن دیسک MariaDB و CRM را از کار نیندازد.
- **حذف backupهای قدیمی فقط بعد از یک backup موفق و آزمایش‌شده انجام می‌شود** و فقط جدیدترین N مجموعه می‌ماند. نسخه‌های ایمنی restore (`prerestore`) جداگانه با همان سقف شمرده می‌شوند.
- **اگر فایلی هنگام آرشیو تغییر کند** (روی CRM در حال کار عادی است)، فقط هشدار ثبت می‌شود و backup معتبر است.
- **اجرای هم‌زمان دو backup ممکن نیست** (کد خروج ۶).
- **پوشه‌های `cache`، `tmp`، `logs` و `test/templates_c` در آرشیو نیستند.** Vtiger این‌ها را خودش دوباره می‌سازد.
- **دسترسی فایل‌ها:** فایل‌های backup فقط برای root قابل خواندن‌اند (600).

**وضعیت آخرین اجرا** در `/var/log/crm_backup.status` است. این فایل برای همه قابل خواندن است و رمزی ندارد، پس CRM هم می‌تواند آن را بخواند:

```
status=failed
time=2026-11-02 22:00:04
last_success=2026-11-01 22:00:12
message=Not enough disk space in /home/backup: about 5120 MB needed, 900 MB free
```

**اگر backup شکست خورد:**

```bash
cat /var/log/crm_backup.status          # نتیجه و علت
tail -30 /var/log/crm_backup.log        # جزئیات، شامل خطای خود mysqldump یا tar
df -h /home /                           # فضای دیسک
/usr/local/bin/parsvt-backup.sh         # اجرای دستی پس از رفع مشکل
```

| کد خروج backup | معنی |
|---|---|
| 0 | موفق |
| 5 | پیش‌نیازها برقرار نیست: فضای کافی نیست، ابزار پیدا نشد، یا پوشه قابل نوشتن نیست |
| 6 | backup دیگری در حال اجراست |
| سایر | خطای یکی از مراحل؛ جزئیاتش در لاگ است |

> backup روی همان دیسک سرور، در برابر خرابی دیسک یا هک شدن سرور محافظت نمی‌کند. یک نسخه را به‌طور منظم به خارج از سرور منتقل کنید.

---

## ۶. ارتقای PHP به 8.3 (گزینهٔ ۶ یا `--php-upgrade`)

این ابزار مرحلهٔ ۳ مهاجرت Vtiger 7.x به 8.4.0 است. **از داخل CRM اجرا نمی‌شود**، به این دلایل:

- ری‌استارت httpd/php-fpm درخواست جاری را قطع می‌کند.
- نیاز به دسترسی root دارد.
- اگر شکست بخورد، سایت پایین می‌آید.
- مهم‌تر از همه: با عوض شدن نسخهٔ PHP، همهٔ فایل‌های ionCube از کار می‌افتند تا loader جدید نصب شود، از جمله خود ماژول مهاجرت.

**پس آن را با SSH، با کاربر root و در حالی که CRM بسته است اجرا کنید.**

```bash
bash parsvt.sh --php-upgrade                   # فقط گزارش؛ چیزی تغییر نمی‌کند
bash parsvt.sh --php-upgrade --dry-run         # نمایش همهٔ دستورها بدون اجرا
bash parsvt.sh --php-upgrade --upgrade         # اجرای واقعی (باید کلمهٔ upgrade را تایپ کنید)
bash parsvt.sh --php-upgrade --check --json    # گزارش ماشینی برای ویزارد مهاجرت
```

| سوییچ | کار |
|---|---|
| `--target=8.3` | نسخهٔ PHP مقصد (پیش‌فرض 8.3) |
| `--root=PATH` | مسیر CRM (پیش‌فرض `/var/www/html`) |
| `--yes` | بدون پرسش تأیید |
| `--no-ioncube` | رد کردن مرحلهٔ ionCube، **فقط اگر خودتان آن را نصب می‌کنید** |
| `--json` | خروجی JSON (حالت `--check` را هم فعال می‌کند) |

**قبل از `--upgrade` حتماً backup بگیرید:**

```bash
php /var/www/html/modules/ParsVT/migration_cli.php backup --what=all
```

مراحل `--upgrade`:

1. ذخیرهٔ php.ini و پیکربندی فعلی در `/root/parsvt-php-upgrade-<زمان>`، به‌همراه لیست پکیج‌های نصب‌شده
2. فعال‌سازی مخزن:
   - **RHEL 8+:** remi و `dnf module enable php:remi-8.3`
   - **EL7:** `--enablerepo=remi,remi-php83`، چون EL7 module stream ندارد
   - **Debian/Ubuntu:** ondrej PPA یا sury.org. PHP قبلی کنار نسخهٔ جدید نصب می‌ماند و Apache با `a2dismod`/`a2enmod` (یا `a2disconf`/`a2enconf` برای FPM) جابه‌جا می‌شود.
3. نصب PHP 8.3 و extensionها
4. **نصب ionCube loader برای 8.3**، مرحله‌ای که تعیین می‌کند CRM دوباره بالا بیاید یا نه
5. ساخت دوبارهٔ timezonedb برای PHP جدید (اگر ساخت شکست بخورد، خاموش می‌شود)
6. اعمال دوبارهٔ تنظیمات php.ini و CA bundle (برای جلوگیری از خطای cURL 60)
7. ری‌استارت وب‌سرور و بررسی نسخه، extensionها و ionCube

اگر هر مرحله شکست بخورد، **دستورهای بازگشت (rollback)** در پایان چاپ می‌شوند.

پس از موفقیت، به ویزارد مهاجرت در CRM برگردید و این مرحله را تأیید کنید. سپس گزینهٔ ۴ (Repair) را هم اجرا کنید.

### کدهای خروج آپدیتر

| کد | معنی |
|---|---|
| 0 | موفق، یا گزارش بدون مشکل |
| 1 | ارتقا شکست خورد (rollback چاپ می‌شود) |
| 2 | آرگومان نادرست، یا کاربر root نیست |
| 3 | کنترل‌پنل PHP را مدیریت می‌کند |
| 4 | سیستم‌عامل پشتیبانی نمی‌شود (مثلاً EL6 یا قدیمی‌تر) |
| 5 | پیش‌نیازها برقرار نیست (مثلاً ionCube وجود ندارد یا شبکه قطع است) |

> **لینک قدیمی:** CRMهای نصب‌شده هنوز آدرس `parsvt-php83-upgrade.txt` را نمایش می‌دهند. آن فایل باید یک shim کوتاه باشد که `parsvt.sh` را دانلود کند و با `--php-upgrade "$@"` اجرا کند.

---

## ۷. تبدیل CentOS 7/8 به AlmaLinux 8 (گزینهٔ ۹ یا `--convert-to-alma`)

```bash
bash parsvt.sh --convert-to-alma
```

- فقط روی **CentOS 7، CentOS 8 و CentOS Stream 8** و فقط روی سرور **بدون کنترل‌پنل** کار می‌کند.
- مقصد AlmaLinux 8 است. برای رسیدن به AlmaLinux 9 باید بعداً یک اجرای جداگانهٔ ELevate انجام دهید، که خارج از این اسکریپت است.
- **این عمل کل سیستم‌عامل را مهاجرت می‌دهد و برگشت‌پذیر نیست.**

### بررسی‌های پیش از تبدیل (به ترتیب)

1. **تأیید backup:** اسکریپت این دستورها را نشان می‌دهد. باید آن‌ها را از قبل اجرا کرده و فایل‌ها را خارج از سرور ذخیره کرده باشید. سپس کلمهٔ `convert` را تایپ کنید.
   ```bash
   tar -czf /root/backup-etc.tar.gz /etc
   tar -czf /root/backup-www.tar.gz /var/www
   mysqldump --all-databases --single-transaction | gzip > /root/backup-mysql.sql.gz
   ```
2. **فضای `/`:** حداقل ۵ GB آزاد.
3. **`/boot`، فقط CentOS 7:**
   - اگر کل پارتیشن کمتر از ۵۱۲ MB باشد، هشدار داده می‌شود و ۱۰ ثانیه برای لغو صبر می‌کند، ولی کار ادامه پیدا می‌کند.
   - اگر فضای آزاد کمتر از ۲۰۰ MB باشد، کار متوقف می‌شود.
   - یک `/boot` پیش‌فرض ۱ GiB با حدود ۸۰۰ MB فضای آزاد بدون مشکل رد می‌شود.
   - روی CentOS 8 این بررسی انجام نمی‌شود، چون almalinux-deploy کرنل جدید نصب نمی‌کند.
4. **بررسی اینترنت**
5. **اگر CRM نصب باشد:** هشدار داده می‌شود که PHP، Apache و MariaDB با پکیج‌های AlmaLinux 8 جایگزین می‌شوند. برای ادامه باید `yes` تایپ کنید.
6. **بررسی دوبارهٔ کنترل‌پنل**، درست پیش از شروع تبدیل

### مسیر CentOS 8 / Stream 8

1. دانلود رسمی `almalinux-deploy.sh` از GitHub مربوط به AlmaLinux و بررسی محتوای آن
2. اجرای اسکریپت. روی CentOS Stream 8 فلگ `-d` (downgrade) خودکار اضافه می‌شود.

> نسخه‌های قبلی نصب‌کنندهٔ ParsVT، CentOS 8 را به Stream تبدیل می‌کردند. پس بسیاری از سرورهای قدیمی‌تر روی Stream هستند و به همین فلگ نیاز دارند. نسخهٔ فعلی دیگر این تبدیل را انجام نمی‌دهد، چون Stream 8 هم پایان عمر رسیده و مخازنش در دسترس نیست. روی CentOS 7/8 پیشنهاد می‌کند اول با گزینهٔ ۹ به AlmaLinux 8 مهاجرت کنید.

3. ری‌استارت خودکار پس از ۱۰ ثانیه. با `Ctrl+C` می‌توانید ری‌استارت را خودتان بعداً انجام دهید.

### مسیر CentOS 7 (ELevate)

1. فایل `CentOS-Base.repo` به `el7.repo.almalinux.org` تغییر می‌کند، چون مخازن CentOS 7 خاموش شده‌اند. نسخهٔ قبلی فایل در `/root/CentOS-Base.repo.parsvt` نگه داشته می‌شود.
2. اجرای `yum update -y`. **اگر کرنل جدید نصب شود، اسکریپت متوقف می‌شود.** سرور را ری‌استارت کنید و دوباره `bash parsvt.sh --convert-to-alma` را اجرا کنید.
3. نصب `elevate-release`، `leapp-upgrade` و `leapp-data-almalinux`.
4. اجرای `leapp preupgrade` و **نمایش کامل گزارش** `/var/log/leapp/leapp-report.txt`.
5. **اگر گزارش inhibitor داشته باشد، کار متوقف می‌شود** (کد ۵). inhibitorها را رفع کنید و دوباره اجرا کنید. inhibitorهای رایج CentOS 7 طبق راهنمای AlmaLinux:
   ```bash
   rmmod pata_acpi
   echo PermitRootLogin yes | tee -a /etc/ssh/sshd_config
   leapp answer --section remove_pam_pkcs11_module_check.confirm=True
   ```
6. اجرای `leapp upgrade`، سپس ری‌استارت.

### بعد از ری‌استارت

اسکریپت به‌طور خودکار ادامه نمی‌دهد. دوباره `bash parsvt.sh` را اجرا کنید:

- سیستم‌عامل حالا AlmaLinux 8 گزارش می‌شود و گزینهٔ ۹ دیگر نمایش داده نمی‌شود.
- گزینهٔ نصب یا Repair را انتخاب کنید.

### کدهای خروج تبدیل

| کد | معنی |
|---|---|
| 0 | تمام شد و سرور ری‌استارت شد، یا لغو شد، یا برای کرنل جدید باید ری‌استارت کنید |
| 1 | یکی از مراحل شکست خورد (دانلود، yum یا leapp) |
| 3 | کنترل‌پنل وجود دارد |
| 4 | سرور CentOS 7/8 نیست |
| 5 | یکی از بررسی‌های پیش از تبدیل رد شد (فضای دیسک، `/boot` یا inhibitor) |

---

## ۸. خلاصهٔ کدهای خروج منوی اصلی

| کد | معنی |
|---|---|
| 0 | اجرای عادی یا لغو |
| 1 | خطا و توقف عملیات |
| 2 | آرگومان ناشناخته |
| 3 | سرور کنترل‌پنل دارد (پیش از نمایش منو) |
| 4 | سیستم‌عامل پشتیبانی نمی‌شود (پیش از نمایش منو) |

---

## ۹. عیب‌یابی

| مشکل | بررسی |
|---|---|
| صفحهٔ سفید پس از نصب یا ارتقا | `php -m \| grep -i ioncube` (روی Debian: `php8.3 -m`). اگر loader وجود ندارد، گزینهٔ ۵ را اجرا کنید |
| `Internet connection is DOWN` | DNS و دسترسی به `aweb.co` را بررسی کنید. در نصب، DNS شکن را انتخاب کنید |
| `The server returned Vtiger X, but Vtiger Y was expected` | سرور دانلود نسخهٔ اشتباه برگرداند. دیتابیس دست نخورده است. با پشتیبانی تماس بگیرید |
| شکست ارتقای PHP | دستورهای rollback در انتهای خروجی چاپ می‌شوند. پیکربندی قبلی در `/root/parsvt-php-upgrade-<زمان>` است |
| شکست ELevate | `/var/log/leapp/leapp-report.txt` و `/var/log/leapp/leapp-upgrade.log` |
| شکست almalinux-deploy | `/var/log/almalinux-deploy.log` |
| راهنمای کامل سوییچ‌ها | `bash parsvt.sh --help` |

---

**www.parsvt.com**
