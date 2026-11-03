#!/bin/bash
# #########################################
# Program: ParsVT CRM Installation Script
# Developer: Hamid Rabiei, Mohammad Hadadpour
# Release: 1397-12-10
# Update: 1405-08-10
# #########################################
# Unified installer: Vtiger 8 / PHP 8.3, Vtiger 7 / PHP 7.4 (deprecated),
# national internet (AlmaLinux 9), repair, ionCube, ClamAV, SSL, the PHP 8.3
# upgrader (--php-upgrade) and CentOS 7/8 to AlmaLinux 8 (--convert-to-alma).
#   RHEL family:   RHEL / CentOS 7+, AlmaLinux / Rocky / Oracle Linux 8+, Fedora 39+
#   Debian family: Debian 11+, Ubuntu 20.04+, Linux Mint 21+, Pop!_OS 22.04+
# bash parsvt.sh --help lists the command line options.
#
# Downloads from third-party sites fall back to a copy on our own server
# (mirrorURL); files we host fall back to the official upstream where one exists.
#
# Backup and restore:
# Backups run daily at 22:00 via /usr/local/bin/parsvt-backup.sh,
# keeping the newest N sets (asked during installation, default 7) in /home/backup.
# A failed or incomplete backup never replaces or removes an existing one.
# Restore with /usr/local/bin/parsvt-restore.sh, which lists available
# dated sets, dumps the current database and files to safety copies
# first, then restores.
# #########################################
set -e
shecanDNS1="178.22.122.100"
shecanDNS2="185.51.200.2"
Color_Off="\e[0m"
Red="\e[0;31m"
Green="\e[0;32m"
Yellow="\e[0;33m"
Cyan="\e[0;36m"
primarySite="aweb.co"
ETH_DEV="127.0.0.1"
INSTALLTYPE="Fresh"
DBHOST="localhost"
DBUSER="root"
DBNAME="parsvt"
SETUPDIR="/var/www/html/"
SETUPDIR2="/var/www/html"
backupdirectory="/home/backup"
counter=0
LICENSEKEY=""
app_dir=""
adminPWD="123456789"
mysqlPWD="123456789"
installationType="Install"
JavaVersion="461"
WEBMIN_VERSION="2.670"
VTIGER_VERSION="8"
PHP_TARGET="8.3"
PACKAGE_URL="http://$primarySite/modules/addons/easyservice/Installer/download.php"
PARSVT_PORTS="80 443 143 993 110 995 22 25 2525 587 465 3306 5038 9999 7777 2222 8080 8081 8443 10000"
PHP_UPGRADE_CLI="no"
CONVERT_CLI="no"
BACKUP_KEEP="7"
OS_FAMILY="unknown" OS_ID="unknown" OS_ID_LIKE="" OS_NAME="unknown"
OS_VERSION_ID="0" OS_MAJOR="0" OS_CODENAME="" RHEL_MAJOR=""
PANEL="none" PANEL_NAME="" PKG_MGR="none" REMI="no" DNF_SKIP="--skip-broken"
major="" fullname=""
ARCH=$(uname -m)

# #############################################################################
# OS, package, service and path abstraction
# #############################################################################
isRHEL() { [ "$OS_FAMILY" = "rhel" ]; }
isDebianFamily() { [ "$OS_FAMILY" = "debian" ]; }
isFedora() { [ "$OS_ID" = "fedora" ]; }
isUbuntu() {
	case "$OS_ID" in ubuntu | linuxmint | pop) return 0 ;; esac
	case " $OS_ID_LIKE " in *" ubuntu "*) return 0 ;; esac
	return 1
}
usingSystemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

detectOS() {
	OS_ID="unknown" OS_ID_LIKE="" OS_NAME="unknown" OS_VERSION_ID="0"
	OS_MAJOR="0" OS_CODENAME="" OS_FAMILY="unknown" RHEL_MAJOR=""
	if [ -r /etc/os-release ]; then
		# subshells: sourcing os-release here would overwrite NAME, ID, VERSION...
		OS_ID=$(. /etc/os-release && echo "${ID:-unknown}")
		OS_ID_LIKE=$(. /etc/os-release && echo "${ID_LIKE:-}")
		OS_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-unknown}}")
		OS_VERSION_ID=$(. /etc/os-release && echo "${VERSION_ID:-0}")
		# Mint/Pop!_OS: PPAs are published for the Ubuntu base codename
		OS_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
	elif [ -r /etc/redhat-release ]; then
		OS_NAME=$(cat /etc/redhat-release)
		OS_VERSION_ID=$(tr -dc '0-9.' </etc/redhat-release | cut -d. -f1)
		OS_ID="rhel"
		if grep -qi "centos" /etc/redhat-release; then
			OS_ID="centos"
		fi
	fi
	OS_MAJOR=$(echo "$OS_VERSION_ID" | cut -d. -f1)
	if [ -z "$OS_MAJOR" ]; then
		OS_MAJOR="0"
	fi
	case "$OS_ID" in
	centos | almalinux | rocky | rhel | ol | fedora) OS_FAMILY="rhel" ;;
	debian | ubuntu | linuxmint | pop) OS_FAMILY="debian" ;;
	*)
		# ID_LIKE catches the derivatives that do not name themselves
		case " $OS_ID_LIKE " in
		*rhel* | *fedora* | *centos*) OS_FAMILY="rhel" ;;
		*debian* | *ubuntu*) OS_FAMILY="debian" ;;
		esac
		;;
	esac
	if [ "$OS_FAMILY" = "rhel" ]; then
		RHEL_MAJOR="$OS_MAJOR"
		if [ -r /etc/redhat-release ] && [ "$OS_ID" != "fedora" ]; then
			RHEL_MAJOR=$(tr -dc '0-9.' </etc/redhat-release | cut -d. -f1)
		fi
		# Fedora has no EL version; dnf/systemd/remi streams behave as on EL9
		if [ "$OS_ID" = "fedora" ] || [ -z "$RHEL_MAJOR" ]; then
			RHEL_MAJOR="9"
		fi
	fi
	return 0
}

detectPanel() {
	PANEL="none"
	PANEL_NAME=""
	if [ -x /usr/local/cpanel/cpanel ] || [ -d /usr/local/cpanel ]; then
		PANEL="cpanel"
		PANEL_NAME="cPanel / WHM"
	elif [ -x /usr/local/directadmin/directadmin ] || [ -d /usr/local/directadmin ]; then
		PANEL="directadmin"
		PANEL_NAME="DirectAdmin"
	elif [ -f /usr/local/psa/version ] || [ -d /opt/psa ]; then
		PANEL="plesk"
		PANEL_NAME="Plesk"
	elif [ -d /usr/local/CyberCP ] || [ -f /usr/local/lsws/bin/lswsctrl ]; then
		PANEL="cyberpanel"
		PANEL_NAME="CyberPanel / OpenLiteSpeed"
	elif [ -d /usr/local/vesta ] || [ -d /usr/local/hestia ]; then
		PANEL="hestia"
		PANEL_NAME="Vesta / HestiaCP"
	elif [ -d /www/server/panel ] || [ -f /etc/init.d/bt ]; then
		PANEL="aapanel"
		PANEL_NAME="aaPanel"
	fi
	return 0
}

detectPackageManager() {
	PKG_MGR="none"
	REMI="no"
	DNF_SKIP="--skip-broken"
	if [ "$OS_FAMILY" = "debian" ] && command -v apt-get >/dev/null 2>&1; then
		PKG_MGR="apt"
	elif command -v dnf >/dev/null 2>&1; then
		PKG_MGR="dnf"
	elif command -v yum >/dev/null 2>&1; then
		PKG_MGR="yum"
	fi
	if ls /etc/yum.repos.d/remi*.repo >/dev/null 2>&1; then
		REMI="yes"
	fi
	# dnf5 (Fedora 41+) split missing packages out of --skip-broken
	if [ "$PKG_MGR" = "dnf" ] && dnf --version 2>/dev/null | grep -qi "dnf5"; then
		DNF_SKIP="--skip-broken --skip-unavailable"
	fi
	return 0
}

detectWebServer() {
	WEBSERVER="unknown"
	if [ -d /etc/httpd ]; then
		WEBSERVER="httpd"
	elif [ -d /etc/apache2 ]; then
		WEBSERVER="apache2"
	elif [ -d /etc/nginx ]; then
		WEBSERVER="nginx"
	fi
	return 0
}

# The PHP version Apache runs; on Debian the enabled Apache module/conf decides, not the CLI default.
getActivePHPVersion() {
	local v="" f
	if isDebianFamily; then
		for f in /etc/apache2/mods-enabled/php*.load /etc/apache2/conf-enabled/php*-fpm.conf; do
			if [ -e "$f" ]; then
				v=$(basename "$f")
				v="${v%.load}"
				v="${v%-fpm.conf}"
				v="${v#php}"
				break
			fi
		done
	fi
	if [ -z "$v" ] && command -v php >/dev/null 2>&1; then
		v=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)
	fi
	echo "$v"
}

getDebianApachePHPMode() {
	if ls /etc/apache2/mods-enabled/php*.load >/dev/null 2>&1; then
		echo "modphp"
	elif ls /etc/apache2/conf-enabled/php*-fpm.conf >/dev/null 2>&1; then
		echo "fpm"
	elif [ ! -d /etc/apache2 ] && ls -d /etc/php/*/fpm >/dev/null 2>&1; then
		echo "fpm"
	else
		echo "modphp"
	fi
}

phpBin() {
	local ver="${1:-}"
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	if isDebianFamily && [ -n "$ver" ] && command -v "php$ver" >/dev/null 2>&1; then
		echo "php$ver"
	else
		echo "php"
	fi
}

detectPHP() {
	local ver
	PHP_BIN="" PHP_CUR="none" PHP_INI="none" PHP_EXT_DIR="none" PHP_SAPI_FPM="no"
	ver=$(getActivePHPVersion)
	if [ -n "$ver" ]; then
		PHP_BIN="$(command -v "$(phpBin "$ver")" 2>/dev/null || true)"
	fi
	if [ -n "$PHP_BIN" ]; then
		PHP_CUR="$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo unknown)"
		PHP_EXT_DIR="$("$PHP_BIN" -r 'echo ini_get("extension_dir");' 2>/dev/null || echo none)"
		if isRHEL; then
			PHP_INI="$("$PHP_BIN" -r 'echo php_ini_loaded_file() ?: "none";' 2>/dev/null || echo none)"
		else
			# the CLI reports its own php.ini, not the web server's
			PHP_INI="$(getPHPIniPath apache2 "$PHP_CUR")"
			if isDebianFamily && [ "$(getDebianApachePHPMode)" = "fpm" ]; then
				PHP_INI="$(getPHPIniPath fpm "$PHP_CUR")"
			fi
			if [ ! -f "$PHP_INI" ]; then
				PHP_INI="none"
			fi
		fi
	fi
	if isDebianFamily; then
		if [ "$PHP_CUR" != "none" ] && [ "$(getDebianApachePHPMode)" = "fpm" ]; then
			PHP_SAPI_FPM="yes"
		fi
	elif [ -f /etc/php-fpm.conf ] || [ -d /etc/php-fpm.d ]; then
		PHP_SAPI_FPM="yes"
	fi
	return 0
}

# ---- paths ------------------------------------------------------------------
getApacheConfigFile() {
	if isDebianFamily; then echo "/etc/apache2/apache2.conf"; else echo "/etc/httpd/conf/httpd.conf"; fi
}
getApacheSiteConfig() {
	if isDebianFamily; then echo "/etc/apache2/sites-available/$1.conf"; else echo "/etc/httpd/conf.d/$1.conf"; fi
}
getApacheLogDir() {
	if isDebianFamily; then echo "/var/log/apache2"; else echo "/var/log/httpd"; fi
}

# php.ini of one SAPI; `php --ini` answers for the CLI only
getPHPIniPath() {
	local sapi="${1:-apache2}" ver="${2:-}"
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	if isDebianFamily; then
		echo "/etc/php/$ver/$sapi/php.ini"
	elif [ -f /etc/php.ini ]; then
		echo "/etc/php.ini"
	else
		php -r 'print php_ini_loaded_file();' 2>/dev/null || true
	fi
}

getPHPExtConfDir() {
	local ver="${1:-}"
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	if isDebianFamily; then echo "/etc/php/$ver/mods-available"; else echo "/etc/php.d"; fi
}

# every SAPI of one PHP version shares extension_dir, so its CLI answers correctly
getPHPExtDir() { "$(phpBin "${1:-}")" -r 'echo ini_get("extension_dir");' 2>/dev/null || true; }

getPHPServiceName() {
	local ver="${1:-}"
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	if isDebianFamily; then echo "php${ver}-fpm"; else echo "php-fpm"; fi
}

getPHPPackageName() {
	if isDebianFamily; then echo "php$1"; else echo "php"; fi
}

# Debian package set for one PHP version (RHEL keeps its literal lists); mode: modphp (default) or fpm
getPHPPackages() {
	local v="$1" mode="${2:-modphp}" p list
	p=$(getPHPPackageName "$v")
	list="$p $p-cli $p-common $p-mysql $p-curl $p-xml $p-mbstring $p-zip $p-gd $p-intl $p-soap"
	list="$list $p-bcmath $p-imap $p-ldap $p-opcache $p-odbc $p-readline $p-dev"
	if [ "${v%%.*}" = "7" ]; then
		list="$list $p-json $p-xmlrpc"
	fi
	if [ "$mode" = "fpm" ]; then list="$list $p-fpm"; else list="$list libapache2-mod-$p"; fi
	echo "$list"
}

getWebUser() {
	if isDebianFamily; then echo "www-data:www-data"; else echo "apache:apache"; fi
}
getMySQLConfDir() {
	if isDebianFamily && [ -d /etc/mysql/mariadb.conf.d ]; then
		echo "/etc/mysql/mariadb.conf.d"
	elif isDebianFamily; then
		echo "/etc/mysql/conf.d"
	else
		echo "/etc/my.cnf.d"
	fi
}
getCABundle() {
	if isDebianFamily; then echo "/etc/ssl/certs/ca-certificates.crt"; else echo "/etc/pki/tls/certs/ca-bundle.crt"; fi
}

# phpWriteExtIni <name> <ini line> <priority> [version] - writes and enables it for every SAPI
phpWriteExtIni() {
	local name="$1" content="$2" prio="$3" ver="${4:-}" dir s
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	dir=$(getPHPExtConfDir "$ver")
	mkdir -p "$dir"
	if ! isDebianFamily; then
		echo "$content" >"$dir/$prio-$name.ini"
		return
	fi
	printf '; priority=%s\n%s\n' "$prio" "$content" >"$dir/$name.ini"
	if command -v phpenmod >/dev/null 2>&1; then
		phpenmod -v "$ver" -s ALL "$name"
	else
		for s in apache2 fpm cli; do
			if [ -d "/etc/php/$ver/$s/conf.d" ]; then
				ln -sf "$dir/$name.ini" "/etc/php/$ver/$s/conf.d/$prio-$name.ini"
			fi
		done
	fi
}

# ---- services ---------------------------------------------------------------
svcName() {
	case "$1" in
	httpd) if isRHEL; then echo "httpd"; else echo "apache2"; fi ;;
	php-fpm) getPHPServiceName ;;
	crond) if isRHEL; then echo "crond"; else echo "cron"; fi ;;
	*) echo "$1" ;;
	esac
}
svcExists() {
	local unit
	unit=$(svcName "$1")
	if usingSystemd; then
		case "$unit" in *.*) ;; *) unit="$unit.service" ;; esac
		systemctl list-unit-files "$unit" 2>/dev/null | grep -q "^$unit"
	else
		[ -x "/etc/init.d/$unit" ]
	fi
}
svcRestart() {
	local unit
	unit=$(svcName "$1")
	if usingSystemd; then systemctl restart "$unit"; else service "$unit" restart; fi
}
svcRestartIfPresent() {
	if svcExists "$1"; then
		svcRestart "$1" || true
	fi
}
svcEnable() {
	local unit
	unit=$(svcName "$1")
	if usingSystemd; then
		systemctl enable "$unit"
	elif command -v chkconfig >/dev/null 2>&1; then
		chkconfig "$unit" on
	else
		update-rc.d "$unit" defaults
	fi
}
svcEnableNow() {
	local unit
	unit=$(svcName "$1")
	if usingSystemd; then
		systemctl enable --now "$unit"
	else
		svcEnable "$1"
		svcRestart "$1"
	fi
}
svcActive() {
	local unit
	unit=$(svcName "$1")
	if usingSystemd; then systemctl is-active --quiet "$unit"; else service "$unit" status >/dev/null 2>&1; fi
}
hasApache() {
	command -v httpd >/dev/null 2>&1 || command -v apache2 >/dev/null 2>&1 ||
		[ -x /usr/sbin/apache2 ] || [ -x /usr/sbin/httpd ] || command -v apache2ctl >/dev/null 2>&1
}

# ---- packages ---------------------------------------------------------------
# dnf where present; a fresh CentOS 7 only has yum until updatePackage installs dnf
rhelPM() { if command -v dnf >/dev/null 2>&1; then echo "dnf"; else echo "yum"; fi; }

# --enablerepo=remi only when remi is configured; dnf rejects an unknown repo id
remiOpt() { if [ -f /etc/yum.repos.d/remi.repo ]; then echo "--enablerepo=remi"; fi; }

# DPkg::Lock::Timeout: a fresh Ubuntu VM is still running unattended-upgrades
aptGet() {
	DEBIAN_FRONTEND=noninteractive apt-get -y -q -o DPkg::Lock::Timeout=600 \
		-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# best effort like `dnf --skip-broken`: apt rejects the whole list for one unknown name
pkgInstall() {
	local p
	case "$PKG_MGR" in
	dnf | yum)
		# shellcheck disable=SC2086
		"$PKG_MGR" install $DNF_SKIP -y "$@"
		;;
	apt)
		if ! aptGet install "$@"; then
			for p in "$@"; do
				aptGet install "$p" >/dev/null 2>&1 || output "${Yellow}  package not available, skipped: $p${Color_Off}"
			done
		fi
		;;
	*)
		output "${Red}No supported package manager found.${Color_Off}"
		return 1
		;;
	esac
}
pkgUpdate() {
	case "$PKG_MGR" in
	apt) aptGet update && aptGet upgrade ;;
	dnf | yum)
		# shellcheck disable=SC2086
		"$PKG_MGR" update $DNF_SKIP -y
		;;
	*) return 1 ;;
	esac
}
pkgRemove() {
	case "$PKG_MGR" in
	apt) aptGet remove "$@" ;;
	dnf | yum) "$PKG_MGR" remove -y "$@" ;;
	*) return 1 ;;
	esac
}
# dnf module streams exist on EL8+ and Fedora only; elsewhere a no-op
pkgModule() {
	case "$PKG_MGR" in
	dnf | yum) "$PKG_MGR" module "$1" -y "${@:2}" ;;
	*) return 0 ;;
	esac
}
# pkgRepoAdd <alias> <url or apt source line>
pkgRepoAdd() {
	case "$PKG_MGR" in
	apt) echo "$2" >"/etc/apt/sources.list.d/$1.list" ;;
	dnf | yum) "$PKG_MGR" config-manager --add-repo "$2" ;;
	*) return 1 ;;
	esac
}

# CRB/PowerTools has a different id on RHEL and Oracle Linux; every attempt may fail
rhelEnableCRB() {
	if isFedora; then
		return 0
	fi
	case "$OS_ID" in
	rhel) subscription-manager repos --enable "codeready-builder-for-rhel-${major}-$(uname -m)-rpms" >/dev/null 2>&1 || true ;;
	ol) dnf config-manager --set-enabled "ol${major}_codeready_builder" >/dev/null 2>&1 || true ;;
	*)
		if [ "$major" = "8" ]; then
			dnf config-manager --set-enabled powertools >/dev/null 2>&1 || dnf config-manager --set-enabled PowerTools >/dev/null 2>&1 || true
		else
			dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
		fi
		;;
	esac
	return 0
}

# national-internet (Install2) mirrors for EPEL and remi
fixNationalMirrors() {
	if [ -f "/etc/yum.repos.d/epel.repo" ]; then
		sed -i 's/download.example\/pub/mirror.mobinhost.com/g' /etc/yum.repos.d/epel*.repo
		sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/epel*.repo
		sed -i 's/^metalink=http/#metalink=http/g' /etc/yum.repos.d/epel*.repo
	fi
	if [ -f "/etc/yum.repos.d/remi.repo" ]; then
		sed -i 's/rpms.remirepo.net/mirror.aweb.co\/remi/g' /etc/yum.repos.d/remi*.repo
		sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/remi*.repo
		sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/remi*.repo
		sed -i 's/baseurl=https/baseurl=http/g' /etc/yum.repos.d/remi*.repo
	fi
}

# PHP <version> on Debian/Ubuntu: the distribution if it ships it, else ondrej PPA (Ubuntu) / sury.org (Debian)
debianAddPHPRepo() {
	local ver="${1:-$PHP_TARGET}"
	aptGet update >/dev/null 2>&1 || true
	if grep -rqsE "ondrej/php|packages.sury.org/php" /etc/apt/sources.list /etc/apt/sources.list.d/; then
		output "${Green}PHP repository is already configured!${Color_Off}"
		return 0
	fi
	if apt-cache show "php$ver" >/dev/null 2>&1 && apt-cache show "libapache2-mod-php$ver" >/dev/null 2>&1; then
		output "${Green}PHP $ver is provided by $OS_NAME itself, no extra repository needed.${Color_Off}"
		return 0
	fi
	aptGet install ca-certificates curl gnupg lsb-release
	if isUbuntu; then
		aptGet install software-properties-common >/dev/null 2>&1 || true
		if ! LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php; then
			# Launchpad API blocked, or Mint's own add-apt-repository: write the source by hand
			local key="/tmp/ondrej-php.asc" fpr="14AA40EC0831756756D7F66C4F4EA0AAE5267A6C"
			if ! fetchFile "$key" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fpr" "$(mirrorURL ondrej-php.asc)" ||
				! gpg --batch --show-keys --with-colons "$key" 2>/dev/null | grep -q "$fpr"; then
				rm -f "$key"
				output "${Red}The signing key of the ondrej PHP repository could not be obtained or verified.${Color_Off}"
				abortOperation
			fi
			mkdir -p /etc/apt/keyrings
			gpg --batch --yes --dearmor -o /etc/apt/keyrings/ondrej-php.gpg "$key"
			rm -f "$key"
			pkgRepoAdd ondrej-php "deb [signed-by=/etc/apt/keyrings/ondrej-php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu $OS_CODENAME main"
		fi
	else
		if ! fetchFile /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb "$(mirrorURL debsuryorg-archive-keyring.deb)"; then
			output "${Red}The packages.sury.org keyring could not be downloaded.${Color_Off}"
			abortOperation
		fi
		dpkg -i /tmp/debsuryorg-archive-keyring.deb
		rm -f /tmp/debsuryorg-archive-keyring.deb
		pkgRepoAdd php "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $OS_CODENAME main"
	fi
	if ! aptGet update; then
		output "${Red}The PHP repository was added but cannot be reached from this server.${Color_Off}"
		abortOperation
	fi
}

# Switch Apache and the CLI default to one PHP version; older versions stay installed (trivial rollback)
debianSwitchApachePHP() {
	local ver="$1" mode="${2:-modphp}" f m b
	if [ -d /etc/apache2 ]; then
		for f in /etc/apache2/mods-enabled/php*.load; do
			[ -e "$f" ] || continue
			m=$(basename "$f" .load)
			if [ "$m" != "php$ver" ] || [ "$mode" = "fpm" ]; then
				a2dismod -q "$m" >/dev/null 2>&1 || true
			fi
		done
		for f in /etc/apache2/conf-enabled/php*-fpm.conf; do
			[ -e "$f" ] || continue
			m=$(basename "$f" .conf)
			if [ "$m" != "php$ver-fpm" ] || [ "$mode" = "modphp" ]; then
				a2disconf -q "$m" >/dev/null 2>&1 || true
			fi
		done
		if [ "$mode" = "fpm" ]; then
			a2enmod -q proxy_fcgi setenvif >/dev/null 2>&1 || true
			a2enconf -q "php$ver-fpm"
			svcEnableNow "php$ver-fpm" >/dev/null 2>&1 || true
		else
			a2dismod -q mpm_event mpm_worker >/dev/null 2>&1 || true
			a2enmod -q mpm_prefork >/dev/null 2>&1 || true
			a2enmod -q "php$ver"
		fi
	fi
	for b in php phar phar.phar phpize php-config; do
		if [ -e "/usr/bin/$b$ver" ]; then
			update-alternatives --set "$b" "/usr/bin/$b$ver" >/dev/null 2>&1 || true
		fi
	done
	return 0
}

parsvtApacheConf() {
	cat <<'EOF'
# Written by the ParsVT installer (parsvt.sh); rewritten by every Repair run.
Timeout 600
ServerTokens Prod
ServerSignature Off
<Directory /var/www/html>
	Options -Indexes +FollowSymLinks
	AllowOverride All
	Require all granted
</Directory>
<IfModule dir_module>
	DirectoryIndex index.php index.html
</IfModule>
EOF
}

# The RHEL path edits httpd.conf with sed; Debian gets a file of its own instead.
configureApacheParsVT() {
	if isDebianFamily; then
		parsvtApacheConf >/etc/apache2/conf-available/parsvt.conf
		a2enconf -q parsvt >/dev/null 2>&1 || true
		a2enmod -q rewrite headers >/dev/null 2>&1 || true
		if [ -f /var/www/html/index.html ] && grep -q "Default Page" /var/www/html/index.html; then
			rm -f /var/www/html/index.html
		fi
	fi
	return 0
}

writeApacheVhost() {
	local domain="$1" logdir
	logdir=$(getApacheLogDir)
	cat >"$(getApacheSiteConfig "$domain")" <<EOF
# Written by the ParsVT installer (parsvt.sh)
<VirtualHost *:80>
	ServerName $domain
	DocumentRoot /var/www/html
	<Directory /var/www/html>
		Options -Indexes +FollowSymLinks
		AllowOverride All
		Require all granted
	</Directory>
	ErrorLog $logdir/$domain-error.log
	CustomLog $logdir/$domain-access.log combined
</VirtualHost>
EOF
	if isDebianFamily; then
		a2enmod -q ssl >/dev/null 2>&1 || true
		a2ensite -q "$domain" >/dev/null 2>&1 || true
	fi
	return 0
}

# ---- misc -------------------------------------------------------------------
# via crontab: /var/spool/cron/root is RHEL-only; on RHEL crontab writes that same file
cronAdd() {
	local match="$1" line="$2" current
	current=$(crontab -l 2>/dev/null || true)
	if printf '%s\n' "$current" | grep -qF -- "$match"; then
		return 0
	fi
	{
		if [ -n "$current" ]; then
			printf '%s\n' "$current"
		fi
		printf '%s\n' "$line"
	} | crontab -
}

getAllIPs() {
	local ips
	ips=$(hostname --all-ip-addresses 2>/dev/null || true)
	if [ -z "${ips// /}" ] && command -v ip >/dev/null 2>&1; then
		ips=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')
	fi
	# shellcheck disable=SC2086
	echo $ips
}

genPassword() { head -c 64 /dev/urandom | sha256sum | base64 | head -c "$1"; }

# abortOperation [exit code]: 1 by default; 0 when the user cancelled
abortOperation() {
	output "\n${Red}The operation aborted!${Color_Off}"
	output "${Yellow}www.parsvt.com${Color_Off}\n"
	restoreDNS
	exit "${1:-1}"
}

# ---- downloads ----------------------------------------------------------------
# A copy of every third-party file is kept on our server under the same name.
mirrorURL() { echo "http://$primarySite/modules/addons/easyservice/Installer/$1"; }

# fetchFile <dest> <url> [<url> ...]: the first URL that yields a non-empty file wins.
fetchFile() {
	local dest="$1" url tmp
	shift
	tmp="${dest}.download"
	for url in "$@"; do
		rm -f "$tmp"
		if command -v curl >/dev/null 2>&1; then
			curl -fsSL --connect-timeout 15 --max-time 1800 --retry 2 -o "$tmp" "$url" 2>/dev/null || true
		else
			wget -q --tries=3 --timeout=30 -O "$tmp" "$url" 2>/dev/null || true
		fi
		if [ -s "$tmp" ]; then
			mv -f "$tmp" "$dest"
			return 0
		fi
		output "${Yellow}  could not download ${url}${Color_Off}"
	done
	rm -f "$tmp"
	return 1
}

# rpmInstallFrom <file name> <url> [<url> ...]: download with fallbacks, then install the local file.
rpmInstallFrom() {
	local f="/tmp/$1" rc=0
	shift
	fetchFile "$f" "$@" || return 1
	# shellcheck disable=SC2086
	"$(rhelPM)" install $DNF_SKIP -y "$f" || rc=$?
	rm -f "$f"
	return "$rc"
}

# ionCube archive name for this CPU; the loaders exist for x86-64, x86 and aarch64
ionCubeArchive() {
	case "$(uname -m)" in
	x86_64) echo "ioncube_loaders_lin_x86-64.tar.gz" ;;
	aarch64 | arm64) echo "ioncube_loaders_lin_aarch64.tar.gz" ;;
	*) echo "ioncube_loaders_lin_x86.tar.gz" ;;
	esac
}

UNTESTED_NOTE="Newer versions within the listed families are accepted but not tested."

printSupportedOS() {
	output "Supported operating systems:"
	output "  RHEL family:"
	output "    RHEL / CentOS 7+, AlmaLinux / Rocky / Oracle Linux 8+, Fedora 39+"
	output ""
	output "  Debian family:"
	output "    Debian 11+, Ubuntu 20.04+, Linux Mint 21+, Pop!_OS 22.04+"
	output ""
	output "  ${UNTESTED_NOTE}"
}

# Above the versions the ParsVT test matrix covers; prints UNTESTED_NOTE at runtime.
isNewerThanTested() {
	case "$OS_ID" in
	centos | rhel | rocky | ol) [ "$OS_MAJOR" -gt 9 ] 2>/dev/null ;;
	almalinux) [ "$OS_MAJOR" -gt 10 ] 2>/dev/null ;;
	fedora) [ "$OS_MAJOR" -gt 40 ] 2>/dev/null ;;
	debian) [ "$OS_MAJOR" -gt 12 ] 2>/dev/null ;;
	ubuntu) [ "$OS_MAJOR" -gt 24 ] 2>/dev/null ;;
	linuxmint | pop) [ "$OS_MAJOR" -gt 22 ] 2>/dev/null ;;
	*) return 1 ;;
	esac
}

isEL7() { isRHEL && ! isFedora && [ "$OS_MAJOR" = "7" ]; }
el7PHPWarning() { echo "PHP $1 on EL7 via remi is deprecated and may fail — verify after install"; }

# OS gate of every menu action. $1: what to do by hand on an unsupported system.
prepareOS() {
	if [ "$OS_FAMILY" = "unknown" ] || [ "$PKG_MGR" = "none" ]; then
		output "\n${Red}Operating system is not supported!${Color_Off}"
		output "Detected: ${OS_NAME}"
		printSupportedOS
		if [ -n "$1" ]; then
			output "$1"
		fi
		abortOperation
	fi
	fullname="$OS_NAME"
	major="$RHEL_MAJOR"
	ARCH=$(uname -m)
	output "${Green}${fullname} ${ARCH}${Color_Off}"
}

requireDownloadTools() {
	if [ ! -f "/usr/bin/wget" ] || [ ! -f "/usr/bin/curl" ]; then
		output "${Red}required packages failed to install!${Color_Off}"
		output "Please check the server's internet connection and DNS settings and run the installer again."
		abortOperation
	fi
}

isNationalInternetCapable() { [ -f /etc/almalinux-release ] && [ "$OS_MAJOR" = "9" ]; }

# The supported list, plus newer versions of each listed distribution; derivatives are not on it.
isSupportedOS() {
	if [ "$PKG_MGR" = "none" ]; then
		return 1
	fi
	case "$OS_ID" in
	centos | rhel) [ "$OS_MAJOR" -ge 7 ] 2>/dev/null ;;
	almalinux | rocky | ol) [ "$OS_MAJOR" -ge 8 ] 2>/dev/null ;;
	fedora) [ "$OS_MAJOR" -ge 39 ] 2>/dev/null ;;
	debian) [ "$OS_MAJOR" -ge 11 ] 2>/dev/null ;;
	ubuntu) [ "$OS_MAJOR" -ge 20 ] 2>/dev/null ;;
	linuxmint) [ "$OS_MAJOR" -ge 21 ] 2>/dev/null ;;
	pop) [ "$OS_MAJOR" -ge 22 ] 2>/dev/null ;;
	*) return 1 ;;
	esac
}

checkSupportedCombination() {
	if isFedora || [ "$OS_ID" = "linuxmint" ] || [ "$OS_ID" = "pop" ]; then
		output "${Yellow}${OS_NAME} is supported on a best-effort basis; it is not part of the ParsVT test matrix.${Color_Off}"
	fi
	if [ "$VTIGER_VERSION" = "7" ]; then
		if isFedora; then
			output "\n${Red}Vtiger 7 / PHP 7.4 is not available on ${OS_NAME}. Install Vtiger 8 (option 1) instead.${Color_Off}"
			abortOperation
		fi
		output "${Yellow}Vtiger 7 / PHP 7.4 is DEPRECATED. PHP 7.4 has had no security fixes since November 2022.${Color_Off}"
		if isDebianFamily; then
			output "${Yellow}PHP 7.4 will come from the ondrej PPA / packages.sury.org.${Color_Off}"
		fi
	fi
	if isRHEL && ! isFedora && [ "$RHEL_MAJOR" -lt 8 ] 2>/dev/null; then
		output "${Yellow}${OS_NAME} is end of life; its repositories may disappear at any time.${Color_Off}"
	fi
	if isEL7 && [ "$VTIGER_VERSION" = "8" ]; then
		output "${Yellow}$(el7PHPWarning "$PHP_TARGET")${Color_Off}"
		output "Press Ctrl+C within the next 10 seconds to cancel the installation."
		sleep 10
	fi
	if [ "$OS_ID" = "ubuntu" ] && [ "$OS_MAJOR" = "20" ]; then
		output "${Yellow}Ubuntu 20.04 is past standard support; the ondrej PPA may no longer publish PHP ${PHP_TARGET} for it.${Color_Off}"
	fi
	if [ "$OS_ID" = "debian" ] && [ "$OS_MAJOR" = "11" ]; then
		output "${Yellow}Debian 11 is at the end of its support; packages.sury.org may no longer publish for it.${Color_Off}"
	fi
	return 0
}

ensureBootstrapTools() {
	if command -v curl >/dev/null 2>&1; then
		return 0
	fi
	output "${Cyan}Installing curl...${Color_Off}"
	if isDebianFamily; then
		aptGet update >/dev/null 2>&1 || true
	fi
	pkgInstall curl wget ca-certificates || true
}

verifyPHPVersion() {
	local want="$1" got
	got=$("$(phpBin "$want")" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo none)
	if [ "$got" = "$want" ]; then
		return 0
	fi
	output "\n${Red}PHP ${want} was not installed; the server reports PHP ${got}.${Color_Off}"
	if isFedora; then
		output "Check that remi provides php:remi-${want} for ${OS_NAME}: https://rpms.remirepo.net/wizard/"
	else
		output "Check the repository output above. Every ParsVT module is ionCube encoded for this PHP version."
	fi
	abortOperation
}

# config.inc.php, then define('VTIGER_VERSION'), then $vtiger_current_version in vtigerversion.php (standard Vtiger)
readVtigerVersion() {
	local v=""
	if [ -f "$1/config.inc.php" ]; then
		v=$(grep -oE "vtiger_current_version[[:space:]]*=[[:space:]]*['\"][^'\"]+" "$1/config.inc.php" | head -1 | sed -E "s/.*['\"]//")
	fi
	if [ -z "$v" ] && [ -f "$1/vtigerversion.php" ]; then
		v=$(grep -oE "define\([[:space:]]*['\"]VTIGER_VERSION['\"][[:space:]]*,[[:space:]]*['\"][^'\"]+" "$1/vtigerversion.php" | head -1 | sed -E "s/.*['\"]//")
	fi
	if [ -z "$v" ] && [ -f "$1/vtigerversion.php" ]; then
		v=$(grep -oE "vtiger_current_version[[:space:]]*=[[:space:]]*['\"][^'\"]+" "$1/vtigerversion.php" | head -1 | sed -E "s/.*['\"]//")
	fi
	echo "${v:-unknown}"
}

# Package must be the Vtiger major that was chosen, checked before the database is touched.
verifyPackageVersion() {
	local found
	found=$(readVtigerVersion "$1")
	if [ "$found" = "unknown" ]; then
		output "${Yellow}Could not read the Vtiger version of the package; continuing.${Color_Off}"
		return 0
	fi
	if [ "${found%%.*}" != "$VTIGER_VERSION" ]; then
		output "\n${Red}The server returned Vtiger ${found}, but Vtiger ${VTIGER_VERSION} was expected (${PACKAGE_URL}?v=${VTIGER_VERSION}).${Color_Off}"
		output "${Red}Installation stopped. No change was made to the database.${Color_Off}"
		abortOperation
	fi
	return 0
}

# MariaDB 10.4+ asks about unix_socket; decided by MariaDB version, not by OS major
mariadbIsModern() {
	local v maj min
	v=$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
	if [ -z "$v" ]; then
		[ "$major" = "9" ] || [ "$major" = "10" ]
		return
	fi
	maj=${v%%.*}
	min=$(echo "$v" | cut -d. -f2)
	[ "$maj" -gt 10 ] || { [ "$maj" -eq 10 ] && [ "$min" -ge 4 ]; }
}

# timezonedb built with the phpize of one exact PHP version (pear would build for the alternatives default)
installTimezonedbSource() {
	local ver="${1:-}" phpcmd phpize="phpize" phpconfig="php-config" rc=0
	if [ -z "$ver" ]; then
		ver=$(getActivePHPVersion)
	fi
	phpcmd=$(phpBin "$ver")
	if "$phpcmd" -m 2>/dev/null | grep -qi "^timezonedb$"; then
		output "${Green}timezonedb extension is already installed!${Color_Off}\n"
		return 0
	fi
	if isDebianFamily; then
		phpize="phpize$ver"
		phpconfig="php-config$ver"
	fi
	if ! command -v "$phpize" >/dev/null 2>&1; then
		output "${Yellow}$phpize is not available; timezonedb skipped, PHP uses the system time zone data.${Color_Off}\n"
		return 0
	fi
	output "${Cyan}Installing timezonedb extension...${Color_Off}"
	rm -rf /tmp/timezonedb
	mkdir -p /tmp/timezonedb
	(
		cd /tmp/timezonedb &&
			fetchFile timezonedb-2026.6.tgz "$(mirrorURL timezonedb-2026.6.tgz)" "https://pecl.php.net/get/timezonedb-2026.6.tgz" &&
			tar xzf timezonedb-2026.6.tgz && cd timezonedb-2026.6 &&
			"$phpize" >/dev/null && ./configure --with-php-config="$(command -v "$phpconfig")" >/dev/null &&
			make >/dev/null && make install >/dev/null
	) || rc=$?
	rm -rf /tmp/timezonedb
	if [ "$rc" -eq 0 ]; then
		phpWriteExtIni timezonedb "extension=timezonedb.so" 20 "$ver"
		output "${Green}timezonedb extension successfully installed!${Color_Off}\n"
	else
		output "${Yellow}timezonedb could not be built; PHP uses the system time zone data.${Color_Off}\n"
	fi
	return "$rc"
}

printInstallSummary() {
	local phpcmd phpv ic="not loaded"
	phpcmd=$(phpBin)
	phpv=$("$phpcmd" -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)
	if "$phpcmd" -r 'exit(extension_loaded("ionCube Loader") ? 0 : 1);' 2>/dev/null; then
		ic=$("$phpcmd" -r 'echo ioncube_loader_version();' 2>/dev/null || echo loaded)
	fi
	output "Installation Summary:"
	output "  Operating System:  ${Yellow}${OS_NAME} (${OS_FAMILY})${Color_Off}"
	output "  Control Panel:     ${Yellow}${PANEL_NAME:-none}${Color_Off}"
	output "  Vtiger Version:    ${Yellow}$(readVtigerVersion "${SETUPDIR%/}")${Color_Off}"
	output "  PHP Version:       ${Yellow}${phpv}${Color_Off}"
	output "  ionCube Loader:    ${Yellow}${ic}${Color_Off}\n"
}

getPHPSAPI() {
	if [ "$PHP_CUR" = "none" ]; then
		echo "not installed"
	elif isDebianFamily; then
		if ls /etc/apache2/mods-enabled/php*.load >/dev/null 2>&1; then
			echo "apache2"
		elif ls /etc/apache2/conf-enabled/php*-fpm.conf >/dev/null 2>&1; then
			echo "fpm"
		else
			echo "cli"
		fi
	elif [ "$PHP_SAPI_FPM" = "yes" ]; then
		echo "fpm"
	elif ls /usr/lib64/httpd/modules/libphp*.so /usr/lib/httpd/modules/libphp*.so >/dev/null 2>&1; then
		echo "apache2"
	else
		echo "cli"
	fi
}

# Printed before the menu on every server, supported or not, panel or not.
printSystemInfo() {
	local php="not installed" ic="not installed" crm="none" web
	detectWebServer
	detectPHP
	detectIonCube
	detectCRM
	web="$WEBSERVER"
	if [ "$web" = "unknown" ]; then
		web="not installed"
	fi
	if [ "$PHP_CUR" != "none" ]; then
		php="$PHP_CUR"
	fi
	if [ "$IONCUBE" = "yes" ]; then
		ic="$IONCUBE_VER"
	fi
	if [ "$CRM_FOUND" = "yes" ] && [ "$CRM_VTIGER" != "unknown" ]; then
		crm="Vtiger $CRM_VTIGER"
	elif [ "$CRM_FOUND" = "yes" ]; then
		crm="Vtiger (version unknown)"
	fi
	output "\nSystem information:"
	output "  Operating system    : ${OS_NAME}"
	output "  OS family           : ${OS_FAMILY}"
	output "  OS major version    : ${OS_MAJOR}"
	output "  Architecture        : ${ARCH} (kernel $(uname -r))"
	output "  Control panel       : ${PANEL_NAME:-none}"
	output "  Package manager     : ${PKG_MGR}"
	output "  Web server          : ${web}"
	output "  PHP current         : ${php} (SAPI: $(getPHPSAPI))"
	output "  ionCube loader      : ${ic}"
	output "  CRM at ${CRM_ROOT}: ${crm}"
}

printDoneBanner() {
	output "\n${Yellow} ___            __   _______              "
	output "| _ \__ _ _ _ __\ \ / /_   _|__ ___ _ __  "
	output "|  _/ _\` | '_(_-<\ V /  | |_/ _/ _ \ '  \ "
	output "|_| \__,_|_| /__/ \_/   |_(_)__\___/_|_|_|${Color_Off}\n"
}

printHelp() {
	cat <<'EOF'
ParsVT CRM installer

  bash parsvt.sh      interactive menu: install (Vtiger 8 or 7), repair,
                      ionCube, PHP upgrade, ClamAV, SSL

PHP upgrader (step 3 of the Vtiger 7.x to 8.4.0 migration):
  bash parsvt.sh --php-upgrade                   detect and report, change nothing
  bash parsvt.sh --php-upgrade --dry-run         show the plan
  bash parsvt.sh --php-upgrade --upgrade         do it
  bash parsvt.sh --php-upgrade --check --json    machine readable report

  --target=8.3        PHP version to install (default 8.3)
  --root=PATH         CRM directory (default /var/www/html)
  --yes               do not ask for confirmation
  --no-ioncube        skip the loader step. Only if you install it yourself.
  --json              report as JSON. Implies --check.

Exit codes of the PHP upgrader
  0 success or a clean report   1 the upgrade failed   2 bad invocation, or not root
  3 a control panel manages PHP   4 OS not supported   5 preconditions not met

Backup and restore:
  Backups run daily at 22:00 via /usr/local/bin/parsvt-backup.sh,
  keeping the newest N sets (asked during installation, default 7) in /home/backup.
  A failed or incomplete backup never replaces or removes an existing one.
  Restore with /usr/local/bin/parsvt-restore.sh, which lists available
  dated sets, dumps the current database and files to safety copies
  first, then restores.

CentOS 7/8 to AlmaLinux 8 (menu option 9, shown only on CentOS 7/8 without a panel):
  bash parsvt.sh --convert-to-alma
  CentOS 8 / Stream 8: almalinux-deploy.sh. CentOS 7: ELevate (leapp), stops on inhibitors.
  Guards, in order: type "convert" after the backup warning, 5 GB free on /,
  CentOS 7 only: warning if /boot < 512 MB and 200 MB free on /boot, internet
  check, confirmation if a CRM is installed, panel re-check. Reboots at the end; then run
  parsvt.sh again and pick the install option.
  Exit codes: 3 control panel, 4 not CentOS 7/8, 5 a pre-flight check failed.

On a server with a control panel (cPanel, DirectAdmin, Plesk, CyberPanel,
Hestia, aaPanel) the script prints the panel's own instructions and exits with code 3.
On an unsupported operating system it exits with code 4.

EOF
	printSupportedOS
}

# #############################################################################
# Original installer functions
# #############################################################################
output() {
	echo -e "$1"
}
startInstallation() {
	echo -e "\nPlease enter the item number you want to use:"
	echo -e "[${Cyan}1${Color_Off}] ${Cyan}Install ParsVT CRM - Vtiger 8 / PHP 8.3 (recommended)${Color_Off}"
	echo -e "[${Yellow}2${Color_Off}] ${Yellow}Install ParsVT CRM - Vtiger 7 / PHP 7.4 (DEPRECATED)${Color_Off}"
	if isNationalInternetCapable; then
		echo -e "[${Yellow}3${Color_Off}] ${Yellow}Install ParsVT CRM - national internet (AlmaLinux 9 only)${Color_Off}"
	else
		echo -e "[3] Install ParsVT CRM - national internet (AlmaLinux 9 only - not available on this server)"
	fi
	echo -e "[${Cyan}4${Color_Off}] ${Cyan}Repair server configurations${Color_Off}"
	echo -e "[${Cyan}5${Color_Off}] ${Cyan}Update ionCube loader${Color_Off}"
	echo -e "[${Cyan}6${Color_Off}] ${Cyan}Upgrade PHP to 8.3 (with dry-run & control-panel detection; run '4' after this)${Color_Off}"
	echo -e "[${Cyan}7${Color_Off}] ${Cyan}Install ClamAV (not recommended for low-end servers)${Color_Off}"
	echo -e "[${Cyan}8${Color_Off}] ${Cyan}Install SSL certificate${Color_Off}"
	if canConvertToAlma; then
		echo -e "[${Yellow}9${Color_Off}] ${Yellow}Convert CentOS 7/8 to AlmaLinux 8 (standalone — no control panel)${Color_Off}"
	fi
	echo -e "[${Yellow}0${Color_Off}] ${Yellow}Cancel installation${Color_Off}\n"
	if canConvertToAlma; then
		read -rp "Please select an action (0-9): " run
	else
		read -rp "Please select an action (0-8): " run
	fi
	if [ "$run" == "1" ]; then
		installationType="Install"
		VTIGER_VERSION="8"
		PHP_TARGET="8.3"
	elif [ "$run" == "2" ]; then
		installationType="Install"
		VTIGER_VERSION="7"
		PHP_TARGET="7.4"
	elif [ "$run" == "3" ]; then
		if isNationalInternetCapable; then
			installationType="Install2"
			VTIGER_VERSION="8"
			PHP_TARGET="8.3"
		else
			echo -e "\n${Red}The national internet installer only runs on AlmaLinux 9. This server is ${OS_NAME}.${Color_Off}"
			startInstallation
		fi
	elif [ "$run" == "4" ]; then
		installationType="Repair"
	elif [ "$run" == "5" ]; then
		installationType="ionCube"
	elif [ "$run" == "6" ]; then
		installationType="PHP"
	elif [ "$run" == "7" ]; then
		installationType="clamAV"
	elif [ "$run" == "8" ]; then
		installationType="SSL"
	elif [ "$run" == "9" ] && canConvertToAlma; then
		installationType="Convert"
	elif [ "$run" == "0" ]; then
		abortOperation 0
	else
		startInstallation
	fi
}
checkInternetConnection() {
	TIMESTAMP=$(date +%s)
	local target="8.8.8.8" rc
	if [ "$installationType" = "Install2" ]; then
		target="aweb.co"
	fi
	set +e
	ping -c 1 -W 2 "$target" >/dev/null 2>&1
	rc=$?
	# ICMP is often filtered; a TCP connection to our server decides
	if [ "$rc" -ne 0 ]; then
		timeout 5 bash -c "exec 3<>/dev/tcp/$primarySite/80" >/dev/null 2>&1
		rc=$?
	fi
	set -e
	if [ "$rc" -eq 0 ]; then
		echo -e "\n${Green}Internet connection is UP - $(date +%Y-%m-%d_%H:%M:%S_%Z) - $(($(date +%s) - $TIMESTAMP))${Color_Off}"
	else
		echo -e "\n${Red}Internet connection is DOWN - $(date +%Y-%m-%d_%H:%M:%S_%Z) - $(($(date +%s) - $TIMESTAMP))${Color_Off}"
		output "Please check the server's internet connection and DNS settings and run the installer again."
		abortOperation
	fi
}
setDNS() {
	read -rp "Do you want to use Shecan as DNS during installation? (y/n): " rundns
	if [ "$rundns" = "y" ] || [ "$rundns" = "yes" ] || [ "$rundns" = "Y" ] || [ "$rundns" = "Yes" ] || [ "$rundns" = "YES" ] || [ "$rundns" = "1" ]; then
		mv -n /etc/resolv.conf /etc/resolv.conf.parsvt
		echo -e "nameserver ${shecanDNS1}\nnameserver ${shecanDNS2}\n" >/etc/resolv.conf
		# restored on every exit, including an error halfway through
		trap restoreDNS EXIT
	elif [ "$rundns" = "n" ] || [ "$rundns" = "no" ] || [ "$rundns" = "N" ] || [ "$rundns" = "No" ] || [ "$rundns" = "NO" ] || [ "$rundns" = "0" ]; then
		echo -e "${Yellow}OK!${Color_Off}"
	else
		setDNS
	fi
}
restoreDNS() {
	if [ -e /etc/resolv.conf.parsvt ]; then
		mv /etc/resolv.conf.parsvt /etc/resolv.conf
	fi
}
getLicense() {
	read -rp "Please enter your ParsVT CRM license key: " LICENSEKEY
	LICENSEKEY=${LICENSEKEY//[[:blank:]]/}
}
precheckLicense() {
	chrlen=${#LICENSEKEY}
	if [[ $chrlen -ne 26 ]] && [[ $chrlen -ne 25 ]]; then
		echo -e "${Red}The license key is invalid!${Color_Off}"
		checkLicense
	fi
	if [[ ${LICENSEKEY:0:6} != "ParsVT" ]] && [[ ${LICENSEKEY:0:5} != "Cloud" ]]; then
		echo -e "${Red}The license key is invalid!${Color_Off}"
		checkLicense
	fi
}
checkLicense() {
	if [[ $counter -gt 3 ]]; then
		echo -e "\n${Red}The number of incorrect entries exceeded!${Color_Off}"
		abortOperation
	fi
	counter=$((counter + 1))
	getLicense
	precheckLicense
}
setAdminPassword() {
	adminPWD=$(genPassword 15)
	mysqlPWD=$(php -r "echo crypt('$adminPWD', 'ad');")
}
setMySQLPassword() {
	DBPassword=$(genPassword 20)
}
removeMySQL() {
	MYSQLFOLDER="/var/lib/mysql"
	if [ -d "$MYSQLFOLDER" ]; then
		dt=$(date '+%d-%m-%Y_%H-%M-%S')
		mv /var/lib/mysql /var/lib/old_backup_mysql_"$dt"
	fi
}
getPHPConfigPath() {
	PHPINI="/etc/php.ini"
	if ! isRHEL; then
		PHPINI=$(getPHPIniPath apache2)
	elif [ ! -f "$PHPINI" ]; then
		PHPINI=$(php -r 'print php_ini_loaded_file();')
	fi
}
restartApache() {
	svcRestart httpd
	set +e
	svcRestartIfPresent php-fpm
	set -e
}
# MariaDB, MySQL (mysqld / mysql); nothing to restart when the database is on another host
restartDatabase() {
	local s
	for s in mariadb mysqld mysql; do
		if svcExists "$s"; then
			svcRestart "$s"
			return
		fi
	done
	output "${Yellow}No local database service found to restart.${Color_Off}"
}
disableSELinux() {
	local nl="\n"
	if [ "$installationType" = "Install2" ]; then
		nl=""
	fi
	if isDebianFamily || ! command -v getenforce >/dev/null 2>&1; then
		output "${nl}${Green}SELinux is not present, skipping!${Color_Off}"
		if command -v aa-status >/dev/null 2>&1; then
			output "AppArmor is present and is left as it is."
		fi
		return 0
	fi
	STATUS=$(getenforce)
	if [ "$STATUS" = "disabled" ] || [ "$STATUS" = "Disabled" ]; then
		output "${nl}${Green}SELinux is already disabled!${Color_Off}"
	else
		output "${nl}${Cyan}Disabling SELinux...${Color_Off}"
		setenforce 0
		sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
		sed -i -e 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
		output "${Green}SELinux successfully disabled!${Color_Off}"
	fi
}
updatePackage() {
	if ! isRHEL; then
		output "\n${Cyan}Updating installed packages...${Color_Off}"
		if pkgUpdate; then
			output "${Green}Installed packages successfully updated!${Color_Off}"
		else
			output "${Yellow}The package update did not finish cleanly; continuing.${Color_Off}"
		fi
		return 0
	fi
	if grep -rnwq "/etc/redhat-release" -e "CentOS"; then
		if ! { [ "$major" = "9" ] || [ "$major" = "10" ]; }; then
			output "\n${Cyan}Fixing deprecated CentOS repositories...${Color_Off}"
			set +e
			sed -i 's/mirror.centos.org/vault.centos.org/g' /etc/yum.repos.d/CentOS-*.repo
			sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/CentOS-*.repo
			sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/CentOS-*.repo
			set -e
			output "${Green}Deprecated CentOS repositories successfully fixed!${Color_Off}"
		fi
	fi
	if [ "$installationType" = "Install2" ]; then
		if grep -rnwq "/etc/redhat-release" -e "AlmaLinux"; then
			output "\n${Cyan}Fixing AlmaLinux repositories...${Color_Off}"
			sed -i 's/repo.almalinux.org/mirror.mobinhost.com/g' /etc/yum.repos.d/almalinux-*.repo
			sed -i 's/^#.*baseurl=http/baseurl=http/g' /etc/yum.repos.d/almalinux-*.repo
			sed -i 's/^mirrorlist=http/#mirrorlist=http/g' /etc/yum.repos.d/almalinux-*.repo
			fixNationalMirrors
			output "${Green}AlmaLinux repositories successfully fixed!${Color_Off}"
		fi
	fi
	# CentOS 7/8 and Stream 8 are end of life and served from the vault; the
	# supported way off them is option 9 (AlmaLinux 8), not CentOS Stream.
	if canConvertToAlma; then
		output "${Yellow}${OS_NAME} is end of life. Consider converting to AlmaLinux 8 first (menu option 9).${Color_Off}"
	fi
	output "\n${Cyan}Updating installed packages...${Color_Off}"
	yum install $DNF_SKIP dnf dnf-plugins-core -y
	if grep -rnwq "/etc/redhat-release" -e "CentOS" && [ "$installationType" != "Install" ] && [ "$major" = "8" ]; then
		dnf update $DNF_SKIP --nobest -y
	else
		dnf update $DNF_SKIP -y
	fi
	output "${Green}Installed packages successfully updated!${Color_Off}"
}
installPackage() {
	output "\n${Cyan}Installing required packages...${Color_Off}"
	if isDebianFamily; then
		pkgInstall wget curl expect psmisc net-tools zip unzip tar cron tzdata chrony dnsutils ca-certificates gnupg lsb-release acl iputils-ping procps
	else
		dnf install $DNF_SKIP wget curl expect psmisc net-tools yum-utils zip unzip tar crontabs tzdata chrony bind-utils -y
	fi
	if isRHEL && { [ "$major" = "9" ] || [ "$major" = "10" ]; }; then
		dnf install $DNF_SKIP initscripts -y
	fi
	output "${Green}Required packages successfully installed!${Color_Off}\n"
}
installIonCube() {
	local phpcmd archive work
	archive=$(ionCubeArchive)
	work=$(mktemp -d)
	if ! fetchFile "$work/$archive" "$(mirrorURL "$archive")" "https://downloads.ioncube.com/loader_downloads/$archive" ||
		! tar xzf "$work/$archive" -C "$work"; then
		rm -rf "$work"
		output "${Red}The ionCube loader archive could not be downloaded.${Color_Off}"
		abortOperation
	fi
	phpcmd=$(phpBin)
	PHP_VERSION=$("$phpcmd" -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
	PHP_EXT_DIR=$(getPHPExtDir "$PHP_VERSION")
	if [ -z "$PHP_EXT_DIR" ] && command -v php-config >/dev/null 2>&1; then
		PHP_EXT_DIR=$(php-config --extension-dir)
	fi
	if [ ! -f "$work/ioncube/ioncube_loader_lin_${PHP_VERSION}.so" ] || [ ! -d "$PHP_EXT_DIR" ]; then
		rm -rf "$work"
		output "${Red}The ionCube archive has no loader for PHP ${PHP_VERSION}, or the PHP extension directory was not found.${Color_Off}"
		abortOperation
	fi
	cp "$work/ioncube/ioncube_loader_lin_${PHP_VERSION}.so" "$PHP_EXT_DIR"
	rm -rf "$work"
	# RHEL: /etc/php.d/00-ioncube.ini; Debian: mods-available, enabled for every SAPI
	phpWriteExtIni ioncube "zend_extension = ${PHP_EXT_DIR}/ioncube_loader_lin_${PHP_VERSION}.so" 00 "$PHP_VERSION"
	restartApache
}
installTimezonedb() {
	getPHPConfigPath
	if ! isRHEL; then
		installTimezonedbSource || true
		restartApache
		return 0
	fi
	if grep -rqs "extension=timezonedb.so" "$PHPINI" /etc/php.d/; then
		output "${Green}timezonedb extension is already installed!${Color_Off}\n"
		return 0
	fi
	output "${Cyan}Installing timezonedb extension...${Color_Off}"
	if ! fetchFile /tmp/timezonedb-2026.6.tgz "$(mirrorURL timezonedb-2026.6.tgz)" "https://pecl.php.net/get/timezonedb-2026.6.tgz" ||
		! pear install -f /tmp/timezonedb-2026.6.tgz; then
		rm -f /tmp/timezonedb-2026.6.tgz
		output "${Yellow}timezonedb could not be installed; PHP uses its own time zone data.${Color_Off}\n"
		return 0
	fi
	rm -f /tmp/timezonedb-2026.6.tgz
	sed -i '/extension=<ext>) syntax./a extension=timezonedb.so' "$PHPINI"
	# php.ini without that comment line: load it from php.d instead
	if ! grep -qs "extension=timezonedb.so" "$PHPINI"; then
		phpWriteExtIni timezonedb "extension=timezonedb.so" 20
	fi
	restartApache
	date
	hwclock 2>/dev/null || true
	output "${Green}timezonedb extension successfully installed!${Color_Off}\n"
}
setRequirements() {
	local inifiles
	output "${Cyan}Setting ParsVT requirements...${Color_Off}"
	getPHPConfigPath
	inifiles="$PHPINI"
	if ! isRHEL; then
		# Debian: separate php.ini per SAPI; the CLI one serves migration_cli.php
		inifiles="$PHPINI $(getPHPIniPath cli)"
	fi
	for PHPINI in $inifiles; do
		[ -f "$PHPINI" ] || continue
		sed -i -e 's/max_execution_time = 30/max_execution_time = 600/g' "$PHPINI"
		sed -i -e 's/memory_limit = 128M/memory_limit = 512M/g' "$PHPINI"
		sed -i -e 's/allow_call_time_pass_reference = Off/allow_call_time_pass_reference = On/g' "$PHPINI"
		sed -i -e 's/short_open_tag = Off/short_open_tag = On/g' "$PHPINI"
		sed -i -e 's/;max_input_vars = 1000/max_input_vars = 10000/g' "$PHPINI"
		sed -i -e 's/; max_input_vars = 1000/max_input_vars = 10000/g' "$PHPINI"
		sed -i -e 's/log_errors = Off/log_errors = On/g' "$PHPINI"
		sed -i -e 's/display_errors = On/display_errors = Off/g' "$PHPINI"
		sed -i -e 's/error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT/error_reporting = E_ALL \& ~E_NOTICE \& ~E_WARNING \& ~E_DEPRECATED \& ~E_STRICT/g' "$PHPINI"
		sed -i -e 's/output_buffering = Off/output_buffering = 4096/g' "$PHPINI"
		sed -i -e 's/file_uploads = Off/file_uploads = On/g' "$PHPINI"
		sed -i -e 's/post_max_size = 8M/post_max_size = 128M/g' "$PHPINI"
		sed -i -e 's/upload_max_filesize = 2M/upload_max_filesize = 128M/g' "$PHPINI"
		if ! grep -rnwq "$PHPINI" -e "max_input_time = 600"; then
			sed -i -e 's/max_input_time = 60/max_input_time = 600/g' "$PHPINI"
		fi
		sed -i -e 's/zlib.output_compression = On/zlib.output_compression = Off/g' "$PHPINI"
		sed -i -e 's/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 21600/g' "$PHPINI"
		sed -i -e 's/session.gc_divisor = 500/session.gc_divisor = 1000/g' "$PHPINI"
		sed -i -e 's/session.gc_probability = 0/session.gc_probability = 1/g' "$PHPINI"
		if ! grep -rnwq "$PHPINI" -e "default_socket_timeout = 600"; then
			sed -i -e 's/default_socket_timeout = 60/default_socket_timeout = 600/g' "$PHPINI"
		fi
		sed -i -e 's/;date.timezone =/date.timezone = "Asia\/Tehran"/g' "$PHPINI"
		sed -i -e 's/session.use_strict_mode = 0/session.use_strict_mode = 1/g' "$PHPINI"
		# anchored so that Repair runs do not append " 1" again; the second line repairs grown values
		sed -i -e 's/^session.cookie_httponly =[[:space:]]*$/session.cookie_httponly = 1/' "$PHPINI"
		sed -i -e 's/^session.cookie_httponly = 1\( 1\)\+[[:space:]]*$/session.cookie_httponly = 1/' "$PHPINI"
		sed -i -e 's/session.cookie_secure = 1/;session.cookie_secure =/g' "$PHPINI"
		sed -i -e 's/expose_php = On/expose_php = Off/g' "$PHPINI"
	done
	httpdfile=$(getApacheConfigFile)
	if ! isRHEL; then
		configureApacheParsVT
	elif [ -f "$httpdfile" ]; then
		sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' "$httpdfile"
		if ! grep -rnwq "$httpdfile" -e "TimeOut"; then
			sed -i '/Listen 80/a Timeout 600' "$httpdfile"
		fi
		if ! grep -rnwq "$httpdfile" -e "ServerTokens"; then
			sed -i '/Timeout 600/a ServerTokens Prod' "$httpdfile"
		fi
		if ! grep -rnwq "$httpdfile" -e "ServerSignature"; then
			sed -i '/ServerTokens Prod/a ServerSignature Off' "$httpdfile"
		fi
	fi
	restartApache
	output "${Green}ParsVT requirements have been set!${Color_Off}\n"
}
installJava() {
	local kind jarch="x64"
	# Vtiger itself does not use Java; Debian has no Oracle JDK 8 package, so OpenJDK, non-fatal
	if isDebianFamily; then
		if command -v java >/dev/null 2>&1; then
			output "${Green}Java libraries are already installed!${Color_Off}\n"
			return 0
		fi
		output "${Cyan}Installing Java libraries (OpenJDK from ${OS_NAME})...${Color_Off}"
		pkgInstall default-jre-headless || true
		if command -v java >/dev/null 2>&1; then
			output "${Green}Java libraries successfully installed!${Color_Off} ${Yellow}(ParsVT is tested with Oracle JDK 8u${JavaVersion})${Color_Off}\n"
		else
			output "${Yellow}Java could not be installed. Install a JRE by hand if a ParsVT feature needs it.${Color_Off}\n"
		fi
		return 0
	fi
	case "$ARCH" in
	x86_64) ;;
	aarch64 | arm64) jarch="aarch64" ;;
	*) jarch="i586" ;;
	esac
	if java -version 2>&1 >/dev/null | grep -q "java version \"1.8.0_$JavaVersion\""; then
		output "${Green}Java libraries are already installed!${Color_Off}\n"
		return 0
	fi
	output "${Cyan}Installing Java libraries...${Color_Off}"
	for kind in jdk jre; do
		rpmInstallFrom "$kind-8u$JavaVersion-linux-$jarch.rpm" \
			"http://files.aweb.asia/JAVA/$kind-8u$JavaVersion-linux-$jarch.rpm" \
			"$(mirrorURL "$kind-8u$JavaVersion-linux-$jarch.rpm")" || true
	done
	if java -version 2>&1 >/dev/null | grep -q "java version \"1.8.0_$JavaVersion\""; then
		output "${Green}Java libraries successfully installed!${Color_Off}\n"
	else
		# the CRM is already installed at this point: a missing JRE must not hide the login details
		output "${Yellow}Java 1.8.0_${JavaVersion} could not be installed. Install JDK/JRE 1.8 by hand if a ParsVT feature needs it.${Color_Off}\n"
	fi
}
openPorts() {
	local port svc
	output "${Cyan}Opening required firewall ports...${Color_Off}"
	if isDebianFamily; then
		# ufw only when already active: enabling a firewall that was off is not ours to decide
		if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
			for port in $PARSVT_PORTS; do
				ufw allow "$port/tcp" >/dev/null
			done
		else
			output "ufw is not active; no firewall rules changed."
		fi
	elif svcActive firewalld; then
		# runtime and permanent, without restarting firewalld: a restart drops
		# runtime rules other services (Docker, fail2ban) have added
		svcEnable firewalld >/dev/null 2>&1 || true
		for svc in http https imaps ssh smtp ntp; do
			firewall-cmd --zone=public --add-service="$svc" >/dev/null || true
			firewall-cmd --zone=public --permanent --add-service="$svc" >/dev/null || true
		done
		for port in $PARSVT_PORTS; do
			firewall-cmd --zone=public --add-port="$port/tcp" >/dev/null || true
			firewall-cmd --zone=public --permanent --add-port="$port/tcp" >/dev/null || true
		done
	elif svcActive iptables; then
		for port in $PARSVT_PORTS; do
			iptables -C INPUT -p tcp -m tcp --dport "$port" -j ACCEPT 2>/dev/null ||
				iptables -A INPUT -p tcp -m tcp --dport "$port" -j ACCEPT
		done
		service iptables save
	else
		output "No active firewall (firewalld/iptables); no rules changed."
	fi
	output "${Green}Required firewall ports successfully opened!${Color_Off}"
}
mysqlConnection() {
	read -rp "Enter your MySQL hostname (default: $(tput bold)localhost$(tput sgr0)): " mysql_db_host
	DBHOST="${mysql_db_host:=localhost}"
	read -rp "Enter your MySQL username (default: $(tput bold)root$(tput sgr0)): " mysql_root_name
	DBUSER="${mysql_root_name:=root}"
	read -rp "Enter your MySQL password: " DBPassword
	read -rp "Enter your new MySQL database (default: $(tput bold)parsvt$(tput sgr0)): " mysql_db_name
	DBNAME="${mysql_db_name:=parsvt}"
	if ! [[ "$DBNAME" =~ ^[A-Za-z0-9_]+$ ]]; then
		output "${Red}The database name may only contain letters, digits and _.${Color_Off}"
		mysqlConnection
		return
	fi
	# credentials through the environment: quotes in a password cannot break the PHP code
	mysqlresult=$(PVT_H="$DBHOST" PVT_U="$DBUSER" PVT_P="$DBPassword" php -r 'error_reporting(0); $c = new mysqli(getenv("PVT_H"), getenv("PVT_U"), getenv("PVT_P")); if ($c->connect_error) { die("Connection failed: " . $c->connect_error); } die("Connected");')
	if [ "$mysqlresult" = "Connected" ]; then
		output "${Green}Connection successfully established!${Color_Off}\n"
		output "Database information:"
		output "Database hostname: ${Yellow}${DBHOST}${Color_Off}"
		output "Database username: ${Yellow}${DBUSER}${Color_Off}"
		output "Database password: ${Yellow}${DBPassword}${Color_Off}"
		output "Database name: ${Yellow}${DBNAME}${Color_Off}\n"
		output "Setting up your new database..."
		mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPassword" --default-character-set=utf8mb4 --silent -e "CREATE DATABASE IF NOT EXISTS \`${DBNAME}\` CHARACTER SET 'utf8mb4' COLLATE 'utf8mb4_unicode_ci';"
		output "${Green}Database successfully created!${Color_Off}\n"
	else
		output "${Red}$mysqlresult${Color_Off}"
		mysqlConnection
	fi
}
sslDomain() {
	read -rp "Please enter your domain name (example.com): " domain
	# the domain goes into file paths, an Apache config and a sed expression
	if ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
		output "${Red}Invalid domain name!${Color_Off}"
		sslDomain
		return
	fi
	staticip=$(curl -fsS --connect-timeout 10 "http://$primarySite/ip.php" 2>/dev/null || true)
	if [ -z "$staticip" ]; then
		staticip=$(getAllIPs | awk '{print $1}')
	fi
	read -rp "Are you sure you have created a DNS (A record) to connect the domain $(tput bold)${domain}$(tput sgr0) to the static IP $(tput bold)${staticip}$(tput sgr0)? (y/n): " confirmdomain
	if [ "$confirmdomain" = "y" ] || [ "$confirmdomain" = "yes" ] || [ "$confirmdomain" = "Y" ] || [ "$confirmdomain" = "Yes" ] || [ "$confirmdomain" = "YES" ] || [ "$confirmdomain" = "1" ]; then
		if [ ! -L "/var/www/$domain" ]; then
			ln -s /var/www/html "/var/www/$domain"
		fi
		# RHEL: our vhost template; anywhere it is unavailable, a generated one
		if ! isRHEL || ! fetchFile "/etc/httpd/conf.d/$domain.conf" "$(mirrorURL domain.txt)"; then
			writeApacheVhost "$domain"
		else
			sed -i -e "s/example.com/$domain/g" "/etc/httpd/conf.d/$domain.conf"
		fi
		restartApache
		if ! certbot --apache -d "$domain"; then
			output "${Red}certbot could not issue a certificate for ${domain}. Check the DNS record and that ports 80/443 are reachable.${Color_Off}"
			abortOperation
		fi
		certbot renew --dry-run || output "${Yellow}The renewal test failed; the certificate is installed, but check 'certbot renew' later.${Color_Off}"
		# renewal: the packaged timer where there is one (snap, EPEL, Debian), else cron
		if ! svcEnableNow snap.certbot.renew.timer >/dev/null 2>&1 &&
			! svcEnableNow certbot-renew.timer >/dev/null 2>&1 &&
			! svcEnableNow certbot.timer >/dev/null 2>&1; then
			cronAdd "certbot renew" "0 0,12 * * * certbot renew -q"
		fi
		restartApache
		svcEnableNow crond
		systemctl daemon-reload
		output "${Green}SSL certificate successfully installed!${Color_Off}\n"
	else
		sslDomain
	fi
}
function string_replace {
	echo "${1/\/\//$2}"
}

# #############################################################################
# Shared install steps (formerly repeated in the install, repair and ionCube paths)
# #############################################################################
installPHPRepository() {
	local file="/etc/yum.repos.d/remi.repo" pm
	if isDebianFamily; then
		output "${Cyan}Installing PHP repository...${Color_Off}"
		debianAddPHPRepo "$PHP_TARGET"
		pkgInstall perl libnet-ssleay-perl openssl libio-pty-perl libencode-detect-perl htop iotop proxychains4
		output "${Green}PHP repository successfully installed!${Color_Off}\n"
		return 0
	fi
	pm=$(rhelPM)
	output "${Cyan}Installing Remi repository...${Color_Off}"
	if [ ! -f "$file" ]; then
		if isFedora; then
			rpmInstallFrom "remi-release-fedora-${OS_MAJOR}.rpm" \
				"https://rpms.remirepo.net/fedora/remi-release-${OS_MAJOR}.rpm" "$(mirrorURL "remi-release-fedora-${OS_MAJOR}.rpm")" || true
		else
			rhelEnableCRB
			rpmInstallFrom "epel-release-latest-$major.noarch.rpm" "$(mirrorURL "epel-release-latest-$major.noarch.rpm")" \
				"https://dl.fedoraproject.org/pub/epel/epel-release-latest-$major.noarch.rpm" || true
			if [ "$major" = "9" ]; then
				rpmInstallFrom "epel-next-release-latest-$major.noarch.rpm" "$(mirrorURL "epel-next-release-latest-$major.noarch.rpm")" \
					"https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-$major.noarch.rpm" || true
			fi
			rpmInstallFrom "remi-release-$major.rpm" "$(mirrorURL "remi-release-$major.rpm")" \
				"https://rpms.remirepo.net/enterprise/remi-release-$major.rpm" || true
		fi
	fi
	if [ ! -f "$file" ]; then
		output "${Red}Remi repository failed to install!${Color_Off}"
		output "Please check the server's internet connection and DNS settings and run the installer again."
		abortOperation
	fi
	if [ "$installationType" = "Install2" ] && grep -rnwq "/etc/redhat-release" -e "AlmaLinux"; then
		fixNationalMirrors
	fi
	# replaces --enablerepo=powertools/crb, which is fatal on RHEL and Oracle Linux
	rhelEnableCRB
	$pm install --enablerepo=remi $DNF_SKIP epel-release perl perl-Net-SSLeay openssl perl-IO-Tty perl-Encode-Detect htop iotop perl-Digest-MD5 perl-Digest-SHA proxychains-ng -y
	if [ "$major" = "9" ]; then
		dnf install --enablerepo=remi $DNF_SKIP epel-next-release -y || true
	fi
	output "${Green}Remi repository successfully installed!${Color_Off}\n"
}

# installApachePHP <php version> [apache-only]
installApachePHP() {
	local v="$1" what="${2:-}" pm pkgs
	if [ "$what" = "apache-only" ]; then
		output "${Cyan}Installing Apache...${Color_Off}"
	else
		output "${Cyan}Installing Apache and PHP ${v}...${Color_Off}"
	fi
	if isDebianFamily; then
		if [ "$what" = "apache-only" ]; then
			pkgInstall apache2 "libapache2-mod-php$v" certbot python3-certbot-apache
		else
			# shellcheck disable=SC2046
			pkgInstall apache2 $(getPHPPackages "$v" modphp) certbot python3-certbot-apache unixodbc-dev make build-essential autoconf
		fi
		debianSwitchApachePHP "$v" modphp
		svcEnable httpd
	else
		pm=$(rhelPM)
		# python-certbot-apache on EL7, python3-certbot-apache on EL8+; the missing one is skipped
		pkgs="httpd httpd-devel mod_ssl python-certbot-apache python3-certbot-apache certbot"
		if [ "$what" != "apache-only" ]; then
			pkgs="$pkgs php php-common php-zip php-gd php-mbstring php-mcrypt php-devel php-bcmath php-xml php-odbc php-pear php-imap php-curl php-ldap php-openssl php-intl php-xmlrpc php-soap php-mysql php-mysqlnd php-sqlsrv php-xz php-fpm php-pdo curl-devel unixODBC-devel make gcc"
			if [ "$major" = "7" ]; then
				$pm install --enablerepo=remi,remi-php${v//./} $DNF_SKIP $pkgs -y
			else
				if ! pkgModule reset php || ! pkgModule install "php:remi-${v}"; then
					output "${Red}The remi PHP ${v} module stream could not be enabled on ${fullname}.${Color_Off}"
					abortOperation
				fi
				dnf install --enablerepo=remi $DNF_SKIP $pkgs -y
			fi
		else
			# shellcheck disable=SC2046
			$pm install $(remiOpt) $DNF_SKIP $pkgs -y
		fi
		svcEnable httpd
	fi
	if [ "$what" = "apache-only" ]; then
		output "${Green}Apache successfully installed!${Color_Off}\n"
	else
		verifyPHPVersion "$v"
		output "${Green}Apache and PHP successfully installed!${Color_Off}\n"
	fi
}

# Sub-directory of /var/www/html: letters, digits, . _ - / only, and no "..";
# everything in it is deleted before the CRM is unpacked.
askAppDir() {
	read -rp "Enter the directory path of your application (default: $(tput bold)${SETUPDIR}$(tput sgr0)): " app_dir
	app_dir="${app_dir#/var/www/html}"
	if [ -n "$app_dir" ] && { ! [[ "$app_dir" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$app_dir" == *..* ]]; }; then
		output "${Red}Invalid directory. Use a sub-directory of /var/www/html, e.g. crm${Color_Off}"
		askAppDir
	fi
}

# checkPHPAndIonCube <install|repair|ioncube> [php target]
checkPHPAndIonCube() {
	local mode="$1" target="${2:-}" phpcmd
	if ! command -v "php" &>/dev/null; then
		output "${Red}PHP is not installed!${Color_Off}"
		abortOperation
	fi
	phpcmd=$(phpBin)
	output "${Green}PHP is already installed!${Color_Off}\n"
	if [ "$mode" = "install" ] && ! hasApache; then
		installApachePHP "$(getActivePHPVersion)" apache-only
	fi
	output "Checking the PHP version..."
	PHP_VER=$($phpcmd -r "if (version_compare(PHP_VERSION,'5.6.0','>=')) echo 'Ok'; else echo 'Failed';")
	PHP_VERSION=$($phpcmd -r "echo PHP_VERSION;")
	if [ "$PHP_VER" != "Ok" ]; then
		output "Current PHP version: ${Red}${PHP_VERSION}${Color_Off}"
		output "${Red}PHP version must be greater than 5.5${Color_Off}"
		abortOperation
	fi
	output "Current PHP version: ${Green}${PHP_VERSION}${Color_Off}\n"
	if [ -n "$target" ] && [ "${PHP_VERSION%%.*}" != "${target%%.*}" ]; then
		output "${Yellow}Vtiger ${VTIGER_VERSION} expects PHP ${target}, this server has PHP ${PHP_VERSION}.${Color_Off}"
		output "Press Ctrl+C within the next 10 seconds to cancel the installation."
		sleep 10
	fi
	output "Checking the ionCube loader version..."
	set +e
	IONCUBE_VERSION=$($phpcmd -r "error_reporting(0); echo ioncube_loader_version();")
	if fetchFile /root/IC.php "$(mirrorURL ic.txt)"; then
		IONCUBE_VER=$($phpcmd -f /root/IC.php)
	else
		# our check is unreachable: decide locally (the minimum is 10.0.0)
		IONCUBE_VER=$($phpcmd -r 'if (!function_exists("ioncube_loader_version")) { echo "None"; } elseif (version_compare(ioncube_loader_version(), "10.0.0", ">=")) { echo "Ok"; } else { echo "Failed"; }')
	fi
	set -e
	rm -f /root/IC.php
	case "$IONCUBE_VER" in
	Ok)
		output "Current ionCube loader version: ${Green}${IONCUBE_VERSION}${Color_Off}\n"
		if [ "$mode" = "install" ]; then
			askAppDir
			SETUPDIR="/var/www/html/$app_dir"
			SETUPDIR=$(string_replace "$SETUPDIR" "/")
			SETUPDIR=$(string_replace "$SETUPDIR" "/")
			mkdir -p "$SETUPDIR"
			rm -rf "${SETUPDIR:?}"/*
			output "\nYour application will be installed in ${Yellow}${SETUPDIR}${Color_Off}.\n"
		elif [ "$mode" = "ioncube" ]; then
			restoreDNS
			exit
		fi
		;;
	Upgrade)
		output "Current ionCube loader version: ${Red}${IONCUBE_VERSION}${Color_Off}"
		output "\n${Cyan}Updating ionCube loader...${Color_Off}"
		installIonCube
		output "${Green}ionCube loader successfully updated!${Color_Off}\n"
		;;
	Failed)
		output "Current ionCube loader version: ${Red}${IONCUBE_VERSION}${Color_Off}"
		output "${Red}ionCube loader version must be greater than 10.0.0${Color_Off}"
		abortOperation
		;;
	*)
		output "ionCube loader is not installed!"
		output "\n${Cyan}Installing ionCube loader...${Color_Off}"
		installIonCube
		output "${Green}ionCube loader successfully installed!${Color_Off}\n"
		;;
	esac
}

installMariaDB() {
	local secure_bin="mysql_secure_installation" rootpw_step
	if type mysql >/dev/null 2>&1; then
		output "${Green}MySQL is already installed!${Color_Off}\n"
		mysqlConnection
		return 0
	fi
	removeMySQL
	output "${Cyan}Installing MySQL (MariaDB)...${Color_Off}"
	if isDebianFamily; then
		pkgInstall mariadb-server mariadb-client mariadb-backup
	else
		# shellcheck disable=SC2046
		$(rhelPM) install $(remiOpt) $DNF_SKIP mariadb mariadb-server mariadb-backup mariadb-common mariadb-devel galera php-mysql php-mysqlnd phpMyAdmin -y
	fi
	if ! command -v mysql >/dev/null 2>&1; then
		output "${Red}MariaDB could not be installed.${Color_Off}"
		abortOperation
	fi
	pmafile="/etc/httpd/conf.d/phpMyAdmin.conf"
	if [ -f "$pmafile" ]; then
		sed -i '/<Directory \/usr\/share\/phpMyAdmin\/>/,/<\/Directory>/ s/Require local/Require all granted/' /etc/httpd/conf.d/phpMyAdmin.conf
	fi
	if ! isRHEL; then
		# the distribution's phpmyadmin would pull a second PHP version into Apache
		output "${Yellow}phpMyAdmin is not installed on ${OS_NAME}; Webmin's MySQL module covers database administration.${Color_Off}"
	fi
	setMySQLPassword
	output "MySQL Username: ${DBUSER}\nMySQL Password: ${DBPassword}" >/root/mysql.txt
	chmod 600 /root/mysql.txt
	restartDatabase
	restartApache
	svcEnable mariadb
	mysqladmin -uroot create "$DBNAME"
	if command -v mariadb-secure-installation >/dev/null 2>&1; then
		secure_bin="mariadb-secure-installation"
	fi
	rootpw_step='expect "Set root password?"'
	if mariadbIsModern; then
		rootpw_step='expect "Switch to unix_socket authentication"
send "n\r"
expect "Change the root password?"'
	fi
	SECURE_MYSQL=$(expect -c "
set timeout 10
spawn $secure_bin
expect \"Enter current password for root (enter for none):\"
send \"\r\"
$rootpw_step
send \"y\r\"
expect \"New password:\"
send \"$DBPassword\r\"
expect \"Re-enter new password:\"
send \"$DBPassword\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
	echo "$SECURE_MYSQL"
	# expect depends on the exact prompts of each MariaDB release: verify, and set it directly if needed
	if ! mysql -u root -p"$DBPassword" -e "SELECT 1" >/dev/null 2>&1; then
		output "${Yellow}Setting the MariaDB root password directly...${Color_Off}"
		# --force: on MariaDB 10.4+ mysql.user is a view and the DELETE fails; the rest still runs
		mysql --force -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DBPassword'); DELETE FROM mysql.user WHERE User=''; DROP DATABASE IF EXISTS test; FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
		if ! mysql -u root -p"$DBPassword" -e "SELECT 1" >/dev/null 2>&1; then
			output "${Red}The MariaDB root password could not be set. It is in /root/mysql.txt; set it by hand and run Repair.${Color_Off}"
			abortOperation
		fi
	fi
	mkdir -p "$(getMySQLConfDir)"
	if ! fetchFile "$(getMySQLConfDir)/disable_mysql_strict_mode.cnf" "$(mirrorURL sqlconf.txt)"; then
		# Vtiger does not run in strict mode
		printf '[mysqld]\nsql_mode = NO_ENGINE_SUBSTITUTION\n' >"$(getMySQLConfDir)/disable_mysql_strict_mode.cnf"
		output "${Yellow}sqlconf.txt could not be downloaded; strict mode was disabled with a default configuration.${Color_Off}"
	fi
	restartDatabase
	output "${Green}MySQL (MariaDB) successfully installed!${Color_Off}\n"
	output "${Cyan}Creating database...${Color_Off}"
	mysql -u "$DBUSER" -p"$DBPassword" --default-character-set=utf8mb4 --silent -e "CREATE DATABASE IF NOT EXISTS \`${DBNAME}\` CHARACTER SET 'utf8mb4' COLLATE 'utf8mb4_unicode_ci';"
	mysql -u "$DBUSER" -p"$DBPassword" --default-character-set=utf8mb4 --silent -e "ALTER DATABASE \`${DBNAME}\` CHARACTER SET 'utf8mb4' COLLATE 'utf8mb4_unicode_ci';"
	output "${Green}Database successfully created!${Color_Off}\n"
}

# installVtiger <7|8>: package, database, _install.php, _extensions.php, cron
installVtiger() {
	local ver="$1" zip="latest8.zip"
	if [ "$ver" = "7" ]; then
		zip="latest.zip"
	fi
	output "${Cyan}Installing ParsVT CRM package...${Color_Off}"
	mkdir -p "$SETUPDIR"
	# always a fresh download: a cached zip may be a broken file from an earlier failed run
	rm -f "$SETUPDIR/$zip" "$SETUPDIR/extensions.zip"
	if ! fetchFile "$SETUPDIR/$zip" "${PACKAGE_URL}?v=${ver}" || ! unzip -tq "$SETUPDIR/$zip" >/dev/null 2>&1; then
		rm -f "$SETUPDIR/$zip"
		output "${Red}The ParsVT CRM package could not be downloaded from ${primarySite}. No change was made to the database.${Color_Off}"
		abortOperation
	fi
	unzip -q -o "$SETUPDIR/$zip" -d "$SETUPDIR"
	verifyPackageVersion "${SETUPDIR%/}"
	mkdir -p "$SETUPDIR/test/data/modules/"
	if ! fetchFile "$SETUPDIR/extensions.zip" "${RESPONSES[2]}" || ! unzip -tq "$SETUPDIR/extensions.zip" >/dev/null 2>&1; then
		rm -f "$SETUPDIR/extensions.zip"
		output "${Red}The ParsVT extensions could not be downloaded. No change was made to the database.${Color_Off}"
		abortOperation
	fi
	unzip -q -o "$SETUPDIR/extensions.zip" -d "$SETUPDIR"
	chown -R "$(getWebUser)" "$SETUPDIR"
	find "$SETUPDIR" -type d -exec chmod 0755 {} \;
	find "$SETUPDIR" -type f -exec chmod 0644 {} \;
	rm -f "${SETUPDIR:?}/$zip" "${SETUPDIR:?}/extensions.zip"
	if [ "$INSTALLTYPE" = "Exist" ]; then
		(
			echo 'SET foreign_key_checks = 0;'
			(mysqldump -h "$DBHOST" -u "$DBUSER" -p"$DBPassword" --add-drop-table --no-data "$DBNAME" | grep ^DROP)
			echo 'SET foreign_key_checks = 1;'
		) |
			mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPassword" -b "$DBNAME" --default-character-set=utf8mb4 --silent
	fi
	mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPassword" "$DBNAME" --default-character-set=utf8mb4 --silent <"$SETUPDIR/test/data/tmp/database.sql"
	setAdminPassword
	mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPassword" "$DBNAME" --default-character-set=utf8mb4 --silent -e "UPDATE vtiger_users SET user_password = '$mysqlPWD', crypt_type = '' WHERE id = '1';
		UPDATE vtiger_users SET accesskey = UPPER(SUBSTRING(MD5(RAND()) FROM 1 FOR 16)) WHERE id = 1;
		TRUNCATE vtiger_crmsetup;
		TRUNCATE vtiger_loginhistory;"
	CRMURL="$ETH_DEV/$app_dir"
	CRMURL=$(string_replace "$CRMURL" "/")
	if ! wget -q -o /dev/null -O /dev/null "http://$CRMURL/_install.php?db_hostname=$DBHOST&db_name=$DBNAME&db_username=$DBUSER&db_password=$DBPassword"; then
		output "${Yellow}http://$CRMURL/_install.php did not answer correctly; check Apache/PHP and the CRM configuration.${Color_Off}"
	fi
	if ! wget -q -o /dev/null -O /dev/null "http://$CRMURL/_extensions.php?token=${RESPONSES[1]}"; then
		output "${Yellow}http://$CRMURL/_extensions.php did not answer correctly; the extensions may need to be activated by hand.${Color_Off}"
	fi
	cronAdd "http://$CRMURL/vtigercron.php" "*/15 * * * * wget --no-check-certificate --spider \"http://$CRMURL/vtigercron.php\" >/dev/null 2>&1"
	rm -rf "${SETUPDIR:?}"/_install* "${SETUPDIR:?}"/_extensions*
	output "${Green}ParsVT CRM package successfully installed!${Color_Off}\n"
}

setupBackup() {
	output "${Cyan}Setting backup directory...${Color_Off}"
	mkdir -p "$backupdirectory"
	installBackupScripts
	backupCron
	output "${Green}Backup directory successfully set!${Color_Off}\n"
}

sedEsc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Writes /usr/local/bin/parsvt-{backup,restore}.sh (mode 700) from the embedded templates below.
installBackupScripts() {
	local s tmp
	for s in backup restore; do
		tmp=$(mktemp)
		"parsvtTemplate_$s" >"$tmp"
		sed -i -e "s|@@DB_HOST@@|$(sedEsc "$DBHOST")|g" -e "s|@@DB_USER@@|$(sedEsc "$DBUSER")|g" \
			-e "s|@@DB_PASS_B64@@|$(printf '%s' "$DBPassword" | base64 -w0)|g" -e "s|@@DB_NAME@@|$(sedEsc "$DBNAME")|g" \
			-e "s|@@WEB_DIR@@|$SETUPDIR2|g" -e "s|@@BACKUP_DIR@@|$backupdirectory|g" -e "s|@@LOG_FILE@@|/var/log/crm_$s.log|g" \
			-e "s|@@WEB_USER@@|$(getWebUser)|g" -e "s|@@WEB_SERVICE@@|$(svcName httpd)|g" \
			-e "s|@@KEEP_COUNT@@|$BACKUP_KEEP|g" "$tmp"
		install -m 700 "$tmp" "/usr/local/bin/parsvt-$s.sh"
		rm -f "$tmp"
	done
}

# One crontab edit: drops the old /home/backup-*.sh line and adds parsvt-backup.sh once.
backupCron() {
	local current line="0 22 * * * /usr/local/bin/parsvt-backup.sh >/dev/null 2>&1"
	current=$(crontab -l 2>/dev/null | grep -vF "/home/backup-" || true)
	{
		if [ -n "$current" ]; then
			printf '%s\n' "$current"
		fi
		if ! printf '%s\n' "$current" | grep -qF "/usr/local/bin/parsvt-backup.sh"; then
			printf '%s\n' "$line"
		fi
	} | crontab -
}

# Repair: DBHOST, DBUSER, DBPassword, DBNAME from $dbconfig in config.inc.php; fails if any is missing.
readCRMDBConfig() {
	local v=() k
	command -v php >/dev/null 2>&1 || return 1
	mapfile -t v < <(php -r 'error_reporting(0); chdir("/var/www/html"); include "config.inc.php";
		foreach (array("db_server", "db_username", "db_password", "db_name") as $k) { echo isset($dbconfig[$k]) ? base64_encode($dbconfig[$k]) : "", "\n"; }' 2>/dev/null)
	for k in 0 1 2 3; do
		[ -n "${v[$k]:-}" ] || return 1
	done
	DBHOST=$(printf '%s' "${v[0]}" | base64 -d)
	DBUSER=$(printf '%s' "${v[1]}" | base64 -d)
	DBPassword=$(printf '%s' "${v[2]}" | base64 -d)
	DBNAME=$(printf '%s' "${v[3]}" | base64 -d)
}

# Install: how many backup sets to keep (1-365, default 7).
askBackupKeep() {
	local n
	output "Free space for backups in ${backupdirectory%/*}: $(df -Ph "${backupdirectory%/*}" | awk 'NR==2 {print $4}')"
	read -rp "How many backups should be kept on this server? (default: $(tput bold)7$(tput sgr0)): " n
	n="${n:-7}"
	if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt 365 ]; then
		output "${Red}Please enter a number from 1 to 365.${Color_Off}"
		askBackupKeep
		return
	fi
	BACKUP_KEEP="$n"
}

# Repair: keep the number chosen at install time (7 for scripts older than this setting).
readBackupKeep() {
	local n
	n=$(sed -n 's/^KEEP_COUNT=\([0-9][0-9]*\).*/\1/p' /usr/local/bin/parsvt-backup.sh 2>/dev/null || true)
	BACKUP_KEEP="${n:-7}"
}

printBackupInfo() {
	echo "Backup Information:"
	echo "  Backup script    : /usr/local/bin/parsvt-backup.sh"
	echo "  Restore script   : /usr/local/bin/parsvt-restore.sh"
	echo "  Backup directory : /home/backup"
	echo "  Backup schedule  : daily at 22:00"
	echo "  Retention        : newest ${BACKUP_KEEP} backups"
	echo "  Log files        : /var/log/crm_backup.log  /var/log/crm_restore.log"
	echo "  Last result      : /var/log/crm_backup.status"
}

# Embedded verbatim from backup.sh; the @@...@@ placeholders are filled by installBackupScripts.
parsvtTemplate_backup() {
	cat <<'PARSVT_BACKUP_EOF'
#!/usr/bin/env bash
# =============================================================================
# backup.sh — CRM full backup (database + files)
# Runs via cron; logs to @@LOG_FILE@@
# Installed by parsvt.sh as /usr/local/bin/parsvt-backup.sh (mode 700);
# the @@...@@ placeholders are filled in at install time.
#
# A new set is written under *.partial names, verified, and only then renamed
# into place. A failed or incomplete run removes its own partial files and
# never touches existing backups; old sets are removed only after a new set
# has been verified.
# =============================================================================

set -euo pipefail
set -o errtrace
umask 077

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_HOST="@@DB_HOST@@"
DB_USER="@@DB_USER@@"
DB_PASS="$(printf '%s' '@@DB_PASS_B64@@' | base64 -d)"          # TODO: move to ~/.my.cnf for production
DB_NAME="@@DB_NAME@@"
WEB_DIR="@@WEB_DIR@@"
BACKUP_DIR="@@BACKUP_DIR@@"
KEEP_COUNT=@@KEEP_COUNT@@                # number of backup sets kept (asked at install)
RESERVE_MB=1024                          # free space that must remain after a backup
DATE=$(date +"%Y-%m-%d")
LOG="@@LOG_FILE@@"
STATUS_FILE="/var/log/crm_backup.status" # readable by the CRM: last result and last success

DB_FILE="${BACKUP_DIR}/parsvt-db-${DATE}.sql.gz"
FILES_FILE="${BACKUP_DIR}/parsvt-files-${DATE}.tar.gz"
DB_TMP="${DB_FILE}.partial"
FILES_TMP="${FILES_FILE}.partial"

# ---------------------------------------------------------------------------
# Logging helper — tool errors (stderr) go to the same log
# ---------------------------------------------------------------------------
exec 2>>"$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# write_status <ok|failed> <message> — keeps last_success across failures
write_status() {
    local last_ok=""
    if [[ -f "$STATUS_FILE" ]]; then
        last_ok=$(sed -n 's/^last_success=//p' "$STATUS_FILE")
    fi
    if [[ "$1" == "ok" ]]; then
        last_ok="$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    {
        echo "status=$1"
        echo "time=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "last_success=${last_ok}"
        echo "message=$2"
    } > "${STATUS_FILE}.tmp" && mv -f "${STATUS_FILE}.tmp" "$STATUS_FILE"
    chmod 644 "$STATUS_FILE"
}

# fail <message> [exit code] — log, record the failure, exit (cleanup runs on EXIT)
fail() {
    set +e
    trap - ERR
    log "=== Backup FAILED: $1 ==="
    log "Existing backups were not changed."
    write_status failed "$1"
    exit "${2:-1}"
}

cleanup() {
    rm -f "$DB_TMP" "$FILES_TMP"
}

rc=0
trap 'rc=$?; fail "line ${LINENO}: ${BASH_COMMAND} (exit ${rc})" "$rc"' ERR

# ---------------------------------------------------------------------------
# One backup at a time. The cleanup trap is set only after the lock is held,
# so a second instance never removes the partial files of the running one.
# ---------------------------------------------------------------------------
exec 8>"/var/lock/parsvt-backup.lock"
flock -n 8 || { log "Another backup is running"; exit 6; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Sanity checks — required tools and a writable backup directory
# ---------------------------------------------------------------------------
command -v mysqldump >/dev/null || fail "mysqldump not found" 5
command -v tar >/dev/null || fail "tar not found" 5
command -v gzip >/dev/null || fail "gzip not found" 5

# ---------------------------------------------------------------------------
# Ensure backup directory exists
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR" || fail "Cannot create ${BACKUP_DIR}" 5
[[ -w "$BACKUP_DIR" ]] || fail "${BACKUP_DIR} is not writable" 5

log "=== Backup started ==="

# ---------------------------------------------------------------------------
# Disk space — estimate before writing anything, so a full disk cannot take
# the database server down with it. The estimate is deliberately high:
# raw database size + web directory size + RESERVE_MB.
# ---------------------------------------------------------------------------
db_kb=$(mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" -N -B \
    --execute="SELECT COALESCE(SUM(data_length+index_length),0) DIV 1024 FROM information_schema.tables WHERE table_schema='${DB_NAME}';" \
    2>/dev/null || echo 0)
web_kb=$( { du -sk "$WEB_DIR" 2>/dev/null || true; } | awk '{print $1}')
need_kb=$(( ${db_kb:-0} + ${web_kb:-0} + RESERVE_MB * 1024 ))
free_kb=$(df -Pk "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if (( free_kb < need_kb )); then
    fail "Not enough disk space in ${BACKUP_DIR}: about $(( need_kb / 1024 )) MB needed, $(( free_kb / 1024 )) MB free" 5
fi

# ---------------------------------------------------------------------------
# Database dump
# --single-transaction : consistent InnoDB snapshot, no table locks
# --quick              : stream rows instead of buffering whole tables
# --routines           : include stored procedures and functions
# --triggers           : include triggers
# --events             : include scheduled events
# --hex-blob           : dump binary columns as hex, safe for any charset
# ---------------------------------------------------------------------------
log "Dumping database: ${DB_NAME}"
mysqldump \
    --host="$DB_HOST" \
    --user="$DB_USER" \
    --password="$DB_PASS" \
    --single-transaction \
    --quick \
    --default-character-set=utf8mb4 \
    --hex-blob \
    --routines \
    --triggers \
    --events \
    "$DB_NAME" | gzip -9 > "$DB_TMP"

log "Database dump written: ${DB_TMP}"

# ---------------------------------------------------------------------------
# File archive
# Excludes directories Vtiger rebuilds by itself (cache, tmp, logs, compiled
# Smarty templates) to reduce archive size.
# -C / with a relative path: no "Removing leading /" warning, and restore
# extracts with tar -xzf ... -C /. GNU tar needs --exclude before the path.
# Exit code 1 means files changed while they were read (normal on a live
# CRM); the archive is still usable. Anything above 1 is a real failure.
# ---------------------------------------------------------------------------
log "Archiving web directory: ${WEB_DIR}"
tar_rc=0
tar -czf "$FILES_TMP" -C / \
    --warning=no-file-changed \
    --warning=no-file-removed \
    --exclude="${WEB_DIR#/}/cache" \
    --exclude="${WEB_DIR#/}/tmp" \
    --exclude="${WEB_DIR#/}/logs" \
    --exclude="${WEB_DIR#/}/test/templates_c" \
    "${WEB_DIR#/}" || tar_rc=$?
if (( tar_rc == 1 )); then
    log "WARNING: some files changed while they were archived; the archive is still usable."
elif (( tar_rc != 0 )); then
    fail "tar failed (exit ${tar_rc})" "$tar_rc"
fi

log "File archive written: ${FILES_TMP}"

# ---------------------------------------------------------------------------
# Verify the new set, then put it in place. Only now is an older backup with
# the same date replaced.
# ---------------------------------------------------------------------------
log "Verifying the new backup"
gzip -t "$DB_TMP" || fail "Database dump is not a valid gzip file"
zcat "$DB_TMP" | tail -n 1 | grep -q "Dump completed" || fail "Database dump is incomplete"
gzip -t "$FILES_TMP" || fail "File archive is not a valid gzip file"

mv -f "$DB_TMP" "$DB_FILE"
mv -f "$FILES_TMP" "$FILES_FILE"
log "Database dump saved: ${DB_FILE}"
log "File archive saved: ${FILES_FILE}"

# ---------------------------------------------------------------------------
# Retention policy — keep the newest KEEP_COUNT sets, delete older ones.
# Runs only after the new set is verified and in place. Restore safety copies
# (parsvt-db-prerestore-*) are counted separately with the same limit.
# Only files directly in BACKUP_DIR are considered; names sort by date.
# ---------------------------------------------------------------------------
prune() {
    local f stamp sets=()
    if (( $# <= KEEP_COUNT )); then
        return 0
    fi
    mapfile -t sets < <(printf '%s\n' "$@" | sort -r)
    for f in "${sets[@]:KEEP_COUNT}"; do
        stamp=$(basename "$f" | sed 's/^parsvt-db-//' | sed 's/\.sql\.gz$//')
        rm -f "$f" "${BACKUP_DIR}/parsvt-files-${stamp}.tar.gz"
        log "Removed old backup set: ${stamp}"
    done
}

log "Applying retention policy: keep the newest ${KEEP_COUNT} sets"
shopt -s nullglob
prune "${BACKUP_DIR}"/parsvt-db-[0-9]*.sql.gz
prune "${BACKUP_DIR}"/parsvt-db-prerestore-*.sql.gz
shopt -u nullglob

write_status ok "${DB_FILE} ${FILES_FILE}"
log "=== Backup completed successfully ==="
PARSVT_BACKUP_EOF
}

# Embedded verbatim from restore.sh; the @@...@@ placeholders are filled by installBackupScripts.
parsvtTemplate_restore() {
	cat <<'PARSVT_RESTORE_EOF'
#!/usr/bin/env bash
# =============================================================================
# restore.sh — Interactive CRM restore (database + files)
# Scans BACKUP_DIR, lets the user choose a dated set, then restores both.
# Installed by parsvt.sh as /usr/local/bin/parsvt-restore.sh (mode 700);
# the @@...@@ placeholders are filled in at install time.
# =============================================================================

set -euo pipefail
umask 077   # safety copies hold the full database: readable by root only

# ---------------------------------------------------------------------------
# Configuration — must match backup.sh
# ---------------------------------------------------------------------------
DB_HOST="@@DB_HOST@@"
DB_USER="@@DB_USER@@"
DB_PASS="$(printf '%s' '@@DB_PASS_B64@@' | base64 -d)"          # TODO: move to ~/.my.cnf for production
DB_NAME="@@DB_NAME@@"
WEB_DIR="@@WEB_DIR@@"
BACKUP_DIR="@@BACKUP_DIR@@"
WEB_USER="@@WEB_USER@@"
WEB_SERVICE="@@WEB_SERVICE@@"
LOG="@@LOG_FILE@@"

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ---------------------------------------------------------------------------
# select_backup — list available dated backups and return user's choice
# Populates globals: CHOSEN_DB and CHOSEN_FILES
# Both archives are verified here, before anything is changed.
# ---------------------------------------------------------------------------
select_backup() {
    mapfile -t DB_LIST < <(ls -1t "${BACKUP_DIR}"/parsvt-db-*.sql.gz 2>/dev/null)

    if [[ ${#DB_LIST[@]} -eq 0 ]]; then
        echo "ERROR: No backup files found in ${BACKUP_DIR}"
        exit 1
    fi

    echo ""
    echo "Available backups:"
    echo "-------------------"
    for i in "${!DB_LIST[@]}"; do
        label=$(basename "${DB_LIST[$i]}" | sed 's/parsvt-db-//' | sed 's/.sql.gz//')
        printf "  [%d] %s\n" "$((i+1))" "$label"
    done
    echo ""

    read -rp "Select backup number [1-${#DB_LIST[@]}]: " SELECTION

    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || \
       (( SELECTION < 1 || SELECTION > ${#DB_LIST[@]} )); then
        echo "ERROR: Invalid selection."
        exit 1
    fi

    CHOSEN_DB="${DB_LIST[$((SELECTION-1))]}"

    DATE_STAMP=$(basename "$CHOSEN_DB" | sed 's/parsvt-db-//' | sed 's/.sql.gz//')
    CHOSEN_FILES="${BACKUP_DIR}/parsvt-files-${DATE_STAMP}.tar.gz"

    if [[ ! -f "$CHOSEN_FILES" ]]; then
        echo "WARNING: File archive not found for date ${DATE_STAMP}: ${CHOSEN_FILES}"
        echo "         Only the database will be restored."
        CHOSEN_FILES=""
    fi

    if ! gzip -t "$CHOSEN_DB" 2>/dev/null; then
        log "ERROR: ${CHOSEN_DB} is not a valid gzip file. Nothing was changed."
        exit 1
    fi
    if [[ -n "$CHOSEN_FILES" ]] && ! tar -tzf "$CHOSEN_FILES" >/dev/null 2>&1; then
        log "ERROR: ${CHOSEN_FILES} is not a valid tar.gz archive. Nothing was changed."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# confirm — show what will be lost, then require the database name typed
# exactly before any destructive action
# ---------------------------------------------------------------------------
confirm() {
    local counts tables rows web_size
    counts=$(mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" -N -B \
        --execute="SELECT COUNT(*), COALESCE(SUM(TABLE_ROWS),0) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "unknown unknown")
    tables=$(echo "$counts" | awk '{print $1}')
    rows=$(echo "$counts" | awk '{print $2}')
    web_size=$(du -sh "$WEB_DIR" 2>/dev/null | awk '{print $1}' || true)

    echo "This will be LOST (overwritten):"
    echo "  Current database ${DB_NAME} : ${tables} tables, ~${rows} rows (estimate)"
    echo "  Current ${WEB_DIR}       : ${web_size:-0}"
    echo "It will be replaced by:"
    echo "  ${CHOSEN_DB} ($(du -h "$CHOSEN_DB" | awk '{print $1}'))"
    if [[ -n "${CHOSEN_FILES:-}" ]]; then
        echo "  ${CHOSEN_FILES} ($(du -h "$CHOSEN_FILES" | awk '{print $1}'))"
    fi
    echo "Safety copies of the current database and files are written to ${BACKUP_DIR} first."
    echo ""
    read -rp "Type the database name (${DB_NAME}) to continue: " ANSWER
    if [[ "$ANSWER" != "$DB_NAME" ]]; then
        echo "Aborted."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# restore_database — safety dump, drop and recreate, then import the SQL dump
# ---------------------------------------------------------------------------
restore_database() {
    local existing
    log "Starting database restore from: ${CHOSEN_DB}"

    # Safety dump of the current database; skipped when it does not exist yet
    existing=$(mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" -N -B \
        --execute="SHOW DATABASES LIKE '${DB_NAME}';")
    if [[ "$existing" == "$DB_NAME" ]]; then
        SAFETY_DB="${BACKUP_DIR}/parsvt-db-prerestore-${STAMP}.sql.gz"
        log "Dumping current database to safety copy: ${SAFETY_DB}"
        mysqldump --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" \
            --single-transaction --quick --default-character-set=utf8mb4 \
            "$DB_NAME" | gzip -9 > "$SAFETY_DB"
    fi

    # Clean restore: tables that are not in the backup must not survive
    mysql \
        --host="$DB_HOST" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        --execute="DROP DATABASE IF EXISTS \`${DB_NAME}\`; \
                   CREATE DATABASE \`${DB_NAME}\` \
                   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    {
        echo "SET NAMES utf8mb4; SET FOREIGN_KEY_CHECKS=0;"
        zcat "$CHOSEN_DB"
        echo "SET FOREIGN_KEY_CHECKS=1;"
    } | mysql \
        --host="$DB_HOST" \
        --user="$DB_USER" \
        --password="$DB_PASS" \
        "$DB_NAME"

    log "Database restore complete."
}

# ---------------------------------------------------------------------------
# restore_files — safety-copy the current web dir, then extract the archive
# ---------------------------------------------------------------------------
restore_files() {
    log "Starting file restore from: ${CHOSEN_FILES}"

    SAFETY_COPY="${BACKUP_DIR}/parsvt-files-prerestore-${STAMP}.tar.gz"
    log "Creating safety snapshot of current web dir: ${SAFETY_COPY}"
    tar -czf "$SAFETY_COPY" -C / "${WEB_DIR#/}" 2>/dev/null || true

    # Same layout as backup.sh: member paths relative to /
    tar -xzf "$CHOSEN_FILES" -C /

    # Same ownership and modes as the installer
    chown -R "$WEB_USER" "$WEB_DIR"
    find "$WEB_DIR" -type d -exec chmod 0755 {} \;
    find "$WEB_DIR" -type f -exec chmod 0644 {} \;

    log "File restore complete. Safety copy is at: ${SAFETY_COPY}"
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
exec 9>"/var/lock/parsvt-restore.lock"
flock -n 9 || { echo "Another restore is running"; exit 6; }

STAMP=$(date +%Y%m%d-%H%M%S)

log "=== CRM Restore Tool ==="

select_backup

echo ""
log "Selected database : ${CHOSEN_DB}"
log "Selected files    : ${CHOSEN_FILES:-'(none)'}"
echo ""

confirm

restore_database

if [[ -n "${CHOSEN_FILES:-}" ]]; then
    restore_files
fi

log "Restarting ${WEB_SERVICE}"
systemctl restart "$WEB_SERVICE" || log "WARNING: ${WEB_SERVICE} did not restart; restart it by hand."

log "=== Restore completed successfully ==="
echo "Check the CRM: http://$(hostname --all-ip-addresses | awk '{print $1}')/"
PARSVT_RESTORE_EOF
}

installWebmin() {
	local deb="/tmp/webmin_${WEBMIN_VERSION}_all.deb"
	output "${Cyan}Installing Webmin...${Color_Off}"
	if isDebianFamily; then
		# 1. the official repository (gets updates), 2. our copy of the .deb
		if fetchFile /tmp/webmin-key.asc https://download.webmin.com/developers-key.asc "$(mirrorURL webmin-developers-key.asc)"; then
			mkdir -p /usr/share/keyrings
			gpg --batch --yes --dearmor -o /usr/share/keyrings/webmin.gpg /tmp/webmin-key.asc
			pkgRepoAdd webmin "deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/newkey/repository stable contrib"
			if ! { aptGet update >/dev/null 2>&1 && aptGet install --install-recommends webmin; }; then
				# a broken source would break every later apt-get update
				rm -f /etc/apt/sources.list.d/webmin.list
			fi
		fi
		rm -f /tmp/webmin-key.asc
		if ! dpkg -s webmin >/dev/null 2>&1 &&
			fetchFile "$deb" "$(mirrorURL "webmin_${WEBMIN_VERSION}_all.deb")" "https://webmin.com/download/deb/webmin-current.deb"; then
			aptGet install "$deb" || true
			rm -f "$deb"
		fi
		if ! dpkg -s webmin >/dev/null 2>&1; then
			output "${Yellow}Webmin could not be installed. Install it by hand if you need it.${Color_Off}\n"
			return 0
		fi
	else
		rpmInstallFrom "webmin-${WEBMIN_VERSION}-1.noarch.rpm" "$(mirrorURL "webmin-${WEBMIN_VERSION}-1.noarch.rpm")" \
			"https://webmin.com/download/rpm/webmin-current.rpm" || true
		if ! rpm -q webmin >/dev/null 2>&1; then
			output "${Yellow}Webmin could not be installed. Install it by hand if you need it.${Color_Off}\n"
			return 0
		fi
	fi
	output "${Green}Webmin successfully installed!${Color_Off}\n"
}

# #############################################################################
# CentOS 7/8 -> AlmaLinux 8 (menu option 9 / --convert-to-alma)
# #############################################################################
CONVERT_MIN_ROOT_MB=5120
# /boot checks apply to the CentOS 7 (ELevate) path only: almalinux-deploy installs no new kernel
CONVERT_EL7_WARN_BOOT_SIZE_MB=512
CONVERT_EL7_MIN_BOOT_FREE_MB=200
ALMA_DEPLOY_URL="https://raw.githubusercontent.com/AlmaLinux/almalinux-deploy/master/almalinux-deploy.sh"
ELEVATE_RELEASE_URL="http://repo.almalinux.org/elevate/elevate-release-latest-el7.noarch.rpm"
EL7_BASE_REPO_URL="https://el7.repo.almalinux.org/centos/CentOS-Base.repo"

canConvertToAlma() { [ "$OS_ID" = "centos" ] && { [ "$OS_MAJOR" = "7" ] || [ "$OS_MAJOR" = "8" ]; } && [ "$PANEL" = "none" ]; }

convertPanelStop() {
	output "\n${Red}${PANEL_NAME} manages this server.${Color_Off}"
	output "Panel-managed servers must be converted through the panel's own tools or moved to a fresh install."
	exit 3
}

convertCancelled() {
	output "Cancelled. Nothing was changed."
	exit 0
}

# Reboot at the end of a conversion; the user reruns parsvt.sh afterwards.
convertReboot() {
	output "\n${Green}$1${Color_Off}"
	output "After the reboot, run parsvt.sh again and pick the install option."
	output "The server reboots in 10 seconds. Press Ctrl+C to reboot later yourself."
	sleep 10
	reboot
}

convertCentOS8() {
	local deploy="/root/almalinux-deploy.sh" flags=""
	output "${Cyan}Downloading almalinux-deploy.sh...${Color_Off}"
	if ! fetchFile "$deploy" "$ALMA_DEPLOY_URL" "$(mirrorURL almalinux-deploy.sh)"; then
		output "${Red}almalinux-deploy.sh could not be downloaded. Nothing was changed.${Color_Off}"
		exit 1
	fi
	if [ "$(head -1 "$deploy")" != "#!/bin/bash" ] || ! grep -qi "almalinux" "$deploy"; then
		output "${Red}The downloaded almalinux-deploy.sh does not look like the AlmaLinux script. Nothing was changed.${Color_Off}"
		rm -f "$deploy"
		exit 1
	fi
	# CentOS Stream 8 (what the ParsVT installer converts CentOS 8 to) needs --downgrade
	case "$OS_NAME" in *Stream*) flags="-d" ;; esac
	output "${Cyan}Running almalinux-deploy.sh ${flags}...${Color_Off}"
	# shellcheck disable=SC2086
	if ! bash "$deploy" $flags; then
		output "${Red}almalinux-deploy.sh failed. Read its output above and /var/log/almalinux-deploy.log.${Color_Off}"
		exit 1
	fi
	convertReboot "The conversion to AlmaLinux 8 finished. A reboot is required."
}

# ELevate, following the AlmaLinux quickstart guide: working repos, updated and rebooted, then leapp.
convertCentOS7() {
	local report="/var/log/leapp/leapp-report.txt" latest
	output "${Cyan}Pointing CentOS-Base.repo at el7.repo.almalinux.org (the CentOS 7 mirrors are offline)...${Color_Off}"
	cp -n /etc/yum.repos.d/CentOS-Base.repo /root/CentOS-Base.repo.parsvt 2>/dev/null || true
	if ! fetchFile /etc/yum.repos.d/CentOS-Base.repo "$EL7_BASE_REPO_URL" "$(mirrorURL CentOS-Base-el7.repo)"; then
		output "${Red}The CentOS 7 repository file could not be downloaded. Nothing was changed.${Color_Off}"
		exit 1
	fi
	output "${Cyan}Updating CentOS 7...${Color_Off}"
	yum update -y || { output "${Red}yum update failed. Fix it before converting.${Color_Off}"; exit 1; }
	latest=$(rpm -q --last kernel | head -1 | awk '{print $1}' | sed 's/^kernel-//')
	if [ -n "$latest" ] && [ "$latest" != "$(uname -r)" ]; then
		output "\n${Yellow}A new kernel (${latest}) was installed. Reboot first, then run: bash parsvt.sh --convert-to-alma${Color_Off}"
		exit 0
	fi
	output "${Cyan}Installing ELevate...${Color_Off}"
	rpmInstallFrom elevate-release-latest-el7.noarch.rpm "$ELEVATE_RELEASE_URL" "$(mirrorURL elevate-release-latest-el7.noarch.rpm)" ||
		{ output "${Red}elevate-release could not be installed.${Color_Off}"; exit 1; }
	yum install -y leapp-upgrade leapp-data-almalinux || { output "${Red}leapp could not be installed.${Color_Off}"; exit 1; }
	output "${Cyan}Running leapp preupgrade...${Color_Off}"
	leapp preupgrade || true
	if [ ! -f "$report" ]; then
		output "${Red}leapp preupgrade produced no ${report}. Check /var/log/leapp/.${Color_Off}"
		exit 1
	fi
	output "\n${Cyan}----- ${report} -----${Color_Off}"
	cat "$report"
	output "${Cyan}----- end of report -----${Color_Off}\n"
	if grep -qi "inhibitor" "$report"; then
		output "${Red}leapp reported inhibitors (marked \"inhibitor\" above). Resolve them, then run: bash parsvt.sh --convert-to-alma${Color_Off}"
		output "Nothing was upgraded."
		exit 5
	fi
	output "${Cyan}Running leapp upgrade...${Color_Off}"
	leapp upgrade || { output "${Red}leapp upgrade failed. Read /var/log/leapp/leapp-upgrade.log.${Color_Off}"; exit 1; }
	convertReboot "leapp upgrade finished. The reboot completes the upgrade to AlmaLinux 8."
}

convertToAlma() {
	local avail_root avail_boot size_boot answer
	if [ "$OS_ID" != "centos" ] || { [ "$OS_MAJOR" != "7" ] && [ "$OS_MAJOR" != "8" ]; }; then
		output "${Red}--convert-to-alma is only for CentOS 7/8. This server is ${OS_NAME}.${Color_Off}"
		exit 4
	fi
	if [ "$PANEL" != "none" ]; then
		convertPanelStop
	fi
	# 1. backup confirmation
	output "\n${Yellow}This converts ${OS_NAME} to AlmaLinux 8. The entire operating system is migrated; it cannot be undone.${Color_Off}"
	output "You should already have run, and copied off this server:"
	output "  tar -czf /root/backup-etc.tar.gz /etc"
	output "  tar -czf /root/backup-www.tar.gz /var/www"
	output "  mysqldump --all-databases --single-transaction | gzip > /root/backup-mysql.sql.gz"
	read -rp "Type the word convert to continue: " answer
	if [ "$answer" != "convert" ]; then
		convertCancelled
	fi
	# 2. disk space on /, both paths
	avail_root=$(df -Pk / | awk 'NR==2 {print int($4/1024)}')
	if [ "$avail_root" -lt "$CONVERT_MIN_ROOT_MB" ]; then
		output "${Red}Not enough disk space: / has ${avail_root} MB free (${CONVERT_MIN_ROOT_MB} needed).${Color_Off}"
		output "Nothing was changed."
		exit 5
	fi
	# 3. /boot, CentOS 7 only: size warning first (so it can fire), then the free-space block
	if [ "$OS_MAJOR" = "7" ]; then
		size_boot=$(df -Pk /boot | awk 'NR==2 {print int($2/1024)}')
		avail_boot=$(df -Pk /boot | awk 'NR==2 {print int($4/1024)}')
		if [ "$size_boot" -lt "$CONVERT_EL7_WARN_BOOT_SIZE_MB" ]; then
			output "${Yellow}The /boot partition is smaller than the 512 MB recommended by ELevate — the upgrade may fail.${Color_Off}"
			output "Press Ctrl+C within the next 10 seconds to cancel."
			sleep 10
		fi
		if [ "$avail_boot" -lt "$CONVERT_EL7_MIN_BOOT_FREE_MB" ]; then
			output "${Red}ELevate needs free space on /boot for the new kernel — free at least 200 MB and rerun.${Color_Off}"
			output "Nothing was changed."
			exit 5
		fi
	fi
	# 4. internet
	checkInternetConnection
	# 6. existing CRM
	if [ -f /var/www/html/config.inc.php ]; then
		output "${Yellow}A CRM is installed in /var/www/html. The conversion replaces PHP, Apache and MariaDB with AlmaLinux 8 packages and will affect it.${Color_Off}"
		read -rp "Type yes to convert anyway: " answer
		if [ "$answer" != "yes" ]; then
			convertCancelled
		fi
	fi
	# 5. panel re-check, right before the conversion
	detectPanel
	if [ "$PANEL" != "none" ]; then
		convertPanelStop
	fi
	if [ "$OS_MAJOR" = "8" ]; then
		convertCentOS8
	else
		convertCentOS7
	fi
}

# #############################################################################
# PHP upgrader - merged from parsvt-php83-upgrade.txt
# #############################################################################
# Program: ParsVT - Upgrade PHP to 8.3
# Developer: Hamid Rabiei
# Purpose: step 3 of the Vtiger 7.x to 8.4.0 migration
# #############################################################################
#
# WHY THIS IS NOT RUN BY THE CRM
#
# The migration wizard shows this step as "Awaiting manual completion" on
# purpose. It prints the command; it never runs it. Four reasons, and the
# last one is the one that matters:
#
#   1. Upgrading PHP restarts httpd and php-fpm. That kills the PHP process
#      serving the request that asked for the upgrade, so the wizard would
#      lose the connection halfway and never learn how it ended.
#   2. It needs root. The web server user must not have root, and giving it
#      root so a CRM can upgrade PHP is a worse problem than the one it
#      solves.
#   3. A failed PHP upgrade takes the site down. The UI you would use to fix
#      it is the thing that is down.
#   4. Every ParsVT module is ionCube encoded. The loader is built per PHP
#      minor version, so the moment PHP changes, every encoded file stops
#      working until a matching loader is in place - including the migration
#      module itself. A tool that disables itself partway cannot finish its
#      own job.
#
# So: run this over SSH, as root, with the CRM closed.
#
# -----------------------------------------------------------------------------
# WHERE THE MIGRATION STEP SENDS PEOPLE
# -----------------------------------------------------------------------------
#
# This file is published as:
#
#   https://aweb.co/modules/addons/easyservice/Installer/parsvt-php83-upgrade.txt
#
# and the PHP upgrade step prints the line below - but only on a server with
# no control panel and a RHEL-like operating system:
#
#   bash <(curl -sSL https://aweb.co/modules/addons/easyservice/Installer/parsvt-php83-upgrade.txt)
#
# That decision is made by modules/ParsVT/helpers/ServerProfile.php, which
# prints no command at all unless it has positively established the server
# type. Keep the two in step: the URL above is also a constant in that file
# (ParsVT_ServerProfile_Helper::INSTALLER_URL), and the panel instructions in
# the "a control panel owns PHP" section below are duplicated there - this
# script is not on the customer's machine at the moment the step is shown, so
# the text has to exist in both places.
#
# MERGED: the upgrader now runs as `parsvt.sh --php-upgrade`; the old URL
# needs a shim that runs this script with --php-upgrade (see the release notes).
#
# One caveat about that one-liner. Process substitution hides a download
# failure: if curl cannot reach the site, bash is handed an empty file, runs
# nothing and exits 0, which looks exactly like success. The step offers a
# two-step form beside it for that reason:
#
#   curl -fsSL <url> -o /root/parsvt-php83-upgrade.sh
#   bash /root/parsvt-php83-upgrade.sh
#
# -----------------------------------------------------------------------------
# WHAT IT DOES
# -----------------------------------------------------------------------------
#
#   --check     the default. Detects the server and reports. Changes nothing.
#   --dry-run   prints every command it would run, runs none of them.
#   --upgrade   does it.
#
# On a server with cPanel, DirectAdmin, Plesk, CyberPanel, Hestia or aaPanel it refuses to
# touch anything and prints the panel's own way of changing the PHP version,
# because those panels manage PHP themselves and a dnf upgrade behind their
# back breaks them.
#
# -----------------------------------------------------------------------------
# USAGE
# -----------------------------------------------------------------------------
#   bash parsvt.sh --php-upgrade                    detect and report
#   bash parsvt.sh --php-upgrade --dry-run          show the plan
#   bash parsvt.sh --php-upgrade --upgrade          do it
#   bash parsvt.sh --php-upgrade --check --json     machine readable report
#
#   --target=8.3        PHP version to install (default 8.3)
#   --root=PATH         CRM directory (default /var/www/html)
#   --yes               do not ask for confirmation
#   --no-ioncube        skip the loader step. Only if you install it yourself.
#   --json              report as JSON. Implies --check.
#
# Exit codes
#   0  success, or a clean report
#   1  the upgrade failed
#   2  bad invocation, or not root
#   3  a control panel manages PHP here, so this script will not
#   4  the operating system is not one this script can upgrade
#   5  preconditions not met (no CRM found, no repository, no network)
#
# #############################################################################

TARGET="8.3"
CRM_ROOT="/var/www/html"
MODE="check"
ASSUME_YES="no"
DO_IONCUBE="yes"
AS_JSON="no"
PRIMARY_SITE="$primarySite"

out() { if [ "$AS_JSON" = "no" ]; then echo -e "$1"; fi; }
err() { echo -e "$1" >&2; }
jsonEsc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

phpUpgradeParseArgs() {
	local arg
	for arg in "$@"; do
		case "$arg" in
		--php-upgrade) ;;
		--check) MODE="check" ;;
		--dry-run) MODE="dryrun" ;;
		--upgrade) MODE="upgrade" ;;
		--yes) ASSUME_YES="yes" ;;
		--no-ioncube) DO_IONCUBE="no" ;;
		--json)
			AS_JSON="yes"
			MODE="check"
			;;
		--target=*) TARGET="${arg#--target=}" ;;
		--root=*) CRM_ROOT="${arg#--root=}" ;;
		-h | --help)
			# heredoc, not the header parsed out of "$0": under bash <(curl ...) $0 cannot be re-read
			printHelp
			exit 0
			;;
		*)
			err "Unknown argument: $arg"
			err "Run with --help."
			exit 2
			;;
		esac
	done
	# TARGET ends up in package names and shell commands
	if ! [[ "$TARGET" =~ ^[0-9]+\.[0-9]+$ ]]; then
		err "Invalid --target: $TARGET (expected e.g. 8.3)"
		exit 2
	fi
	CRM_ROOT="${CRM_ROOT%/}"
}

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------
# Every value below is read, never assumed. The report is the point of this
# script even when it does not upgrade anything: the migration wizard cannot
# know what kind of server it is on, and guessing wrong here means telling a
# cPanel customer to run dnf.

detectIonCube() {
	IONCUBE="no"
	IONCUBE_VER="none"
	if [ -n "$PHP_BIN" ] && "$PHP_BIN" -r 'exit(extension_loaded("ionCube Loader") ? 0 : 1);' 2>/dev/null; then
		IONCUBE="yes"
		IONCUBE_VER="$("$PHP_BIN" -r 'echo function_exists("ioncube_loader_version") ? ioncube_loader_version() : "unknown";' 2>/dev/null || echo unknown)"
	fi
	return 0
}

detectCRM() {
	CRM_FOUND="no"
	CRM_KIND="none"
	if [ -f "$CRM_ROOT/config.inc.php" ] || [ -f "$CRM_ROOT/config.php" ]; then
		CRM_FOUND="yes"
		CRM_KIND="vtiger"
		if [ -d "$CRM_ROOT/modules/ParsVT" ]; then
			CRM_KIND="parsvt"
		fi
	fi
	CRM_VTIGER=$(readVtigerVersion "$CRM_ROOT")
}

phpUpgradeDetect() {
	detectPanel
	detectOS
	detectPackageManager
	detectPHP
	detectIonCube
	detectCRM
	detectWebServer
	# Self managed: no control panel and an OS family / package manager this script was written for.
	SELF_MANAGED="no"
	if [ "$PANEL" = "none" ]; then
		case "$OS_FAMILY:$PKG_MGR" in
		rhel:dnf | rhel:yum | debian:apt) SELF_MANAGED="yes" ;;
		esac
	fi
	UPGRADE_SUPPORTED="$SELF_MANAGED"
	if isRHEL && ! isFedora && [ "$OS_MAJOR" -lt 7 ] 2>/dev/null; then
		UPGRADE_SUPPORTED="no"
	fi
	EXPERIMENTAL="no"
	if isFedora; then
		EXPERIMENTAL="yes"
	fi
	SAPI_MODE="modphp"
	if isDebianFamily; then
		SAPI_MODE=$(getDebianApachePHPMode)
	fi
	return 0
}

# JSON report, for the migration UI to consume. Keys of the standalone script first; the merge only appends.
phpUpgradeJSON() {
	local kv sep=""
	printf '{\n'
	for kv in "panel=$PANEL" "panel_name=$PANEL_NAME" "os_id=$OS_ID" "os_name=$OS_NAME" "os_major=$OS_MAJOR" \
		"os_family=$OS_FAMILY" "pkg_mgr=$PKG_MGR" "remi=$REMI" "webserver=$WEBSERVER" "php_current=$PHP_CUR" \
		"php_target=$TARGET" "php_ini=$PHP_INI" "php_ext_dir=$PHP_EXT_DIR" "php_fpm=$PHP_SAPI_FPM" \
		"ioncube=$IONCUBE" "ioncube_version=$IONCUBE_VER" "crm_root=$CRM_ROOT" "crm_found=$CRM_FOUND" \
		"crm_kind=$CRM_KIND" "self_managed=$SELF_MANAGED" "upgrade_supported=$UPGRADE_SUPPORTED" \
		"experimental=$EXPERIMENTAL" "crm_vtiger_version=$CRM_VTIGER" "php_sapi_mode=$SAPI_MODE"; do
		printf '%b  "%s": "%s"' "$sep" "${kv%%=*}" "$(jsonEsc "${kv#*=}")"
		sep=',\n'
	done
	printf '\n}\n'
}

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
phpUpgradeReport() {
	out "${Cyan}ParsVT - Upgrade PHP to ${TARGET}${Color_Off}"
	out ""
	out "  operating system : $OS_NAME  (family $OS_FAMILY, major $OS_MAJOR)"
	out "  control panel    : ${PANEL_NAME:-none}"
	out "  package manager  : $PKG_MGR"
	out "  remi repository  : $REMI"
	out "  web server       : $WEBSERVER"
	out "  php current      : $PHP_CUR"
	out "  php target       : $TARGET"
	out "  php.ini          : $PHP_INI"
	out "  extension_dir    : $PHP_EXT_DIR"
	out "  php-fpm present  : $PHP_SAPI_FPM"
	if isDebianFamily; then
		out "  apache php mode  : $SAPI_MODE"
	fi
	out "  ionCube loader   : $IONCUBE ${IONCUBE_VER}"
	out "  crm directory    : $CRM_ROOT  (found: $CRM_FOUND, kind: $CRM_KIND)"
	out "  vtiger version   : $CRM_VTIGER"
	out ""
	if [ "${CRM_VTIGER%%.*}" = "7" ] && [ "${TARGET%%.*}" = "8" ]; then
		out "${Yellow}Vtiger ${CRM_VTIGER} is installed, and Vtiger 7 does not run on PHP 8.${Color_Off}"
		out "  Run this only as step 3 of the migration wizard (Vtiger 7.x to 8.4.0)."
		out ""
	fi
}

# -----------------------------------------------------------------------------
# A control panel owns PHP. Stop.
# -----------------------------------------------------------------------------
phpUpgradePanelStop() {
	out "${Yellow}$PANEL_NAME manages PHP on this server.${Color_Off}"
	out ""
	out "This script will not change the PHP version here. A dnf upgrade behind"
	out "a panel's back leaves the panel believing one version is installed"
	out "while another is running, and the next panel update usually undoes it"
	out "or breaks the web server. Change it through the panel instead."
	out ""
	panelInstructions
	out ""
	out "After the panel reports ${TARGET}, come back to the migration wizard"
	out "and confirm the step. The wizard re-reads the PHP version from the"
	out "server, so it will see the change."
	out ""
	out "${Yellow}Do not skip the ionCube loader.${Color_Off} Every ParsVT module is"
	out "encoded, and a loader built for another PHP version will not load"
	out "them. Without it the CRM will not start at all."
	exit 3
}

# The panel's own way to set PHP ${TARGET} and the ionCube loader; shared by the updater and the installer.
panelInstructions() {
	case "$PANEL" in
	cpanel)
		out "${Cyan}cPanel / WHM${Color_Off}"
		out "  WHM > Software > MultiPHP Manager"
		out "    1. set the PHP version for the domain to ${TARGET}"
		out "       (shown as ea-php${TARGET//./})"
		out "    2. WHM > Software > EasyApache 4, install these extensions"
		out "       for ea-php${TARGET//./}: mysqlnd, curl, xml, mbstring, zip, gd,"
		out "       intl, soap, bcmath"
		out "    3. install the ionCube loader for ${TARGET}:"
		out "       WHM > ServerConfiguration > Tweak Settings, or"
		out "       WHM > Software > Module Installers > PHP PECL"
		out "    4. confirm with:  /usr/local/bin/ea-php${TARGET//./} -v"
		;;
	directadmin)
		out "${Cyan}DirectAdmin${Color_Off}"
		out "  Use CustomBuild, not dnf:"
		out "    cd /usr/local/directadmin/custombuild"
		out "    ./build set php1_release ${TARGET}"
		out "    ./build set php1_mode php-fpm"
		out "    ./build php n"
		out "    ./build ioncube"
		out "    ./build rewrite_confs"
		out "  Then confirm:  /usr/local/php${TARGET//./}/bin/php -v"
		;;
	plesk)
		out "${Cyan}Plesk${Color_Off}"
		out "  plesk installer --select-release-current \\"
		out "      --install-component php${TARGET//./}"
		out "  Then set it for the domain:"
		out "    Domains > <domain> > PHP Settings > PHP ${TARGET}"
		out "  The ionCube loader is installed per PHP version from"
		out "  Tools & Settings > Updates > Add/Remove Components."
		;;
	cyberpanel)
		out "${Cyan}CyberPanel / OpenLiteSpeed${Color_Off}"
		out "  CyberPanel > PHP > Install Extensions, choose PHP ${TARGET}"
		out "  then set the website's PHP version under"
		out "  Websites > List Websites > Manage > Configurations."
		;;
	hestia)
		out "${Cyan}Vesta / HestiaCP${Color_Off}"
		out "  v-add-web-php ${TARGET}"
		out "  then assign it to the domain in the panel."
		;;
	aapanel)
		out "${Cyan}aaPanel${Color_Off}"
		out "  1. App Store > install PHP-${TARGET}"
		out "  2. App Store > PHP-${TARGET} > Setting > Install extensions:"
		out "     ionCube, fileinfo, imap, intl, ldap, opcache"
		out "  3. Website > <site> > Conf > PHP version > PHP-${TARGET//./}"
		out "  4. confirm with:  /www/server/php/${TARGET//./}/bin/php -v"
		out "  If ionCube is not offered for PHP ${TARGET}, copy ioncube_loader_lin_${TARGET}.so"
		out "  into that PHP's extension directory and add it under Setting > Configuration."
		;;
	esac
}

# Installer, Repair and every other menu action: a panel owns Apache and PHP, so stop before the menu.
installerPanelStop() {
	out "${Red}${PANEL_NAME} manages Apache and PHP on this server.${Color_Off}"
	out ""
	out "The ParsVT installer does not run on control-panel servers: installing,"
	out "repairing or changing PHP here would break the panel's own configuration."
	out "Set up PHP ${TARGET} and the ionCube loader through the panel:"
	out ""
	panelInstructions
	out ""
	out "Then install the ParsVT CRM package through the panel."
	out "${Yellow}www.parsvt.com${Color_Off}\n"
	exit 3
}

# -----------------------------------------------------------------------------
# Not a system this script knows how to upgrade
# -----------------------------------------------------------------------------
phpUpgradeOSCheck() {
	if [ "$OS_FAMILY" = "unknown" ] || [ "$PKG_MGR" = "none" ]; then
		out "${Yellow}This script does not know how to upgrade PHP on this system.${Color_Off}"
		out ""
		out "Detected: $OS_NAME (family: $OS_FAMILY, package manager: $PKG_MGR)"
		out ""
		out "Upgrade PHP to ${TARGET} using whatever your distribution provides,"
		out "then install the ionCube loader for ${TARGET} and restart the web"
		out "server."
		exit 4
	fi
	if isRHEL && ! isFedora && [ "$OS_MAJOR" -lt 7 ] 2>/dev/null; then
		out "${Yellow}${OS_NAME} has no dnf module streams, which this upgrade path depends on.${Color_Off}"
		out "EL7 and older are end of life; move the CRM to AlmaLinux or Rocky 9 instead."
		exit 4
	fi
	# EL7: same warning as the installer; no module streams there, so the plan uses the remi-php repo
	if isEL7; then
		out "${Yellow}$(el7PHPWarning "$TARGET")${Color_Off}"
		if [ "$MODE" = "upgrade" ]; then
			out "Press Ctrl+C within the next 10 seconds to cancel."
			sleep 10
		fi
		out ""
	fi
	if isNewerThanTested; then
		out "${Yellow}${UNTESTED_NOTE}${Color_Off}"
		out ""
	fi
	if [ "$EXPERIMENTAL" = "yes" ]; then
		out "${Yellow}${OS_NAME} is not part of the ParsVT test matrix for this upgrade.${Color_Off}"
		out "  Run --dry-run first and read the plan before running --upgrade."
		out ""
	fi
	if [ "$WEBSERVER" = "nginx" ]; then
		out "${Yellow}nginx serves PHP here:${Color_Off} point fastcgi_pass at the PHP ${TARGET} php-fpm socket yourself."
		out ""
	fi
}

# -----------------------------------------------------------------------------
# Preconditions for the real thing
# -----------------------------------------------------------------------------
phpUpgradePreconditions() {
	PROBLEMS=0
	if [ "$CRM_FOUND" = "no" ]; then
		out "${Yellow}No CRM found at $CRM_ROOT.${Color_Off}"
		out "  Pass --root=PATH if it is somewhere else. This is a warning, not a"
		out "  blocker: PHP can be upgraded without it. But the ionCube step and"
		out "  the php.ini settings are there for the CRM, so check the path."
		out ""
	fi
	if [ "$PHP_CUR" = "$TARGET" ]; then
		out "${Green}PHP is already ${TARGET}.${Color_Off}"
		out ""
		out "Nothing to upgrade. What is still worth confirming:"
		out "  ionCube loader : $IONCUBE $IONCUBE_VER"
		out ""
		if [ "$IONCUBE" = "no" ]; then
			out "${Red}The loader is missing. Every encoded module is dead until it"
			out "is installed.${Color_Off} Run the ionCube option (5) of this script, or"
			out "install it by hand."
			exit 5
		fi
		out "Go back to the migration wizard and confirm the step."
		exit 0
	fi
	if [ "$PKG_MGR" = "none" ]; then
		err "No supported package manager is available. Cannot continue."
		PROBLEMS=$((PROBLEMS + 1))
	fi
	if [ "$(id -u)" != "0" ] && [ "$MODE" = "upgrade" ]; then
		err "This must run as root. Use: sudo bash $0 --php-upgrade --upgrade"
		exit 2
	fi
	if [ "$PROBLEMS" -gt 0 ]; then
		exit 5
	fi
}

# -----------------------------------------------------------------------------
# The plan
# -----------------------------------------------------------------------------
phpUpgradePackages() {
	if isRHEL; then
		PHP_PKGS="php php-cli php-common php-mysqlnd php-curl php-xml php-mbstring"
		PHP_PKGS="$PHP_PKGS php-zip php-gd php-intl php-soap php-bcmath php-opcache"
		PHP_PKGS="$PHP_PKGS php-json php-pdo php-process php-pear php-devel"
		if [ "$PHP_SAPI_FPM" = "yes" ]; then
			PHP_PKGS="$PHP_PKGS php-fpm"
		fi
	else
		PHP_PKGS="$(getPHPPackages "$TARGET" "$SAPI_MODE")"
	fi
	EL7_REPOS="--enablerepo=remi,remi-php${TARGET//./}"
	STAMP="$(date +%Y%m%d-%H%M%S)"
	BACKUP_DIR="/root/parsvt-php-upgrade-$STAMP"
	NEW_PHP_BIN="php"
	if isDebianFamily; then
		NEW_PHP_BIN="php$TARGET"
	fi
}

plan() {
	local php_steps switch="a2dismod php${PHP_CUR} && a2enmod php${TARGET}"
	php_steps="  $PKG_MGR module reset -y php
  $PKG_MGR module enable -y php:remi-${TARGET}
  $PKG_MGR install -y $DNF_SKIP $PHP_PKGS"
	if isEL7; then
		php_steps="  $PKG_MGR upgrade -y $EL7_REPOS $DNF_SKIP 'php*'     # EL7: no module streams
  $PKG_MGR install -y $EL7_REPOS $DNF_SKIP $PHP_PKGS"
	fi
	if [ "$SAPI_MODE" = "fpm" ]; then
		switch="a2disconf php${PHP_CUR}-fpm && a2enconf php${TARGET}-fpm"
	fi
	if isDebianFamily; then
		cat <<PLAN
  mkdir -p $BACKUP_DIR
  cp -a /etc/php/${PHP_CUR} $BACKUP_DIR/php-${PHP_CUR}     # the old configuration, every SAPI
  dpkg -l 'php*' > $BACKUP_DIR/php-packages-before.txt  # and what was installed

  # PHP ${TARGET} from ${OS_NAME} if it ships it, else ondrej PPA / packages.sury.org
  apt-get install -y $PHP_PKGS

  # PHP ${PHP_CUR} stays installed beside ${TARGET}; Apache is switched over
  $switch
  update-alternatives --set php /usr/bin/php${TARGET}

  # ionCube loader for ${TARGET} from ${PRIMARY_SITE}: /etc/php/${TARGET}/mods-available/ioncube.ini, every SAPI
  # timezonedb rebuilt for ${TARGET} if the old PHP had it
  # php.ini settings re-applied in /etc/php/${TARGET}/{apache2,cli}/php.ini

  systemctl restart apache2
  php${TARGET} -v        # must report ${TARGET}
  php${TARGET} -m        # must list ionCube Loader
PLAN
	else
		cat <<PLAN
  mkdir -p $BACKUP_DIR
  cp -a ${PHP_INI} $BACKUP_DIR/                        # keep the old php.ini
  cp -a /etc/php.d $BACKUP_DIR/php.d                   # and the extension ini files
  rpm -qa 'php*' > $BACKUP_DIR/php-packages-before.txt # and what was installed

  $PKG_MGR install -y epel-release
  $PKG_MGR install -y remi-release-${OS_MAJOR}.rpm     # ${PRIMARY_SITE} mirror first, else rpms.remirepo.net
$php_steps

  # ionCube loader for ${TARGET}, into the new extension_dir
  # downloaded from ${PRIMARY_SITE}, placed as /etc/php.d/00-ioncube.ini
  # timezonedb rebuilt for ${TARGET} if php.ini loads it

  # php.ini settings re-applied: memory_limit, max_execution_time,
  # max_input_vars, upload sizes, date.timezone, session hardening

  systemctl restart httpd
  systemctl restart php-fpm        # if present

  php -v        # must report ${TARGET}
  php -m        # must list ionCube Loader
PLAN
	fi
}

phpUpgradeCheck() {
	out "${Green}This server can be upgraded by this script.${Color_Off}"
	out ""
	out "It would run:"
	out ""
	plan
	out ""
	out "Nothing has been changed. To see it with the real values filled in:"
	out "  bash $0 --php-upgrade --dry-run"
	out "To do it:"
	out "  bash $0 --php-upgrade --upgrade"
	out ""
	out "${Yellow}Before you do: take a backup and close the CRM.${Color_Off}"
	out "  php ${CRM_ROOT}/modules/ParsVT/migration_cli.php backup --what=all"
	exit 0
}

phpUpgradeDryRun() {
	out "${Cyan}DRY RUN. Nothing below is executed.${Color_Off}"
	out ""
	plan
	exit 0
}

# -----------------------------------------------------------------------------
# Upgrade
# -----------------------------------------------------------------------------
run() {
	out "  ${Cyan}\$ $*${Color_Off}"
	if ! "$@"; then
		return 1
	fi
	return 0
}

fail_out() {
	out ""
	out "${Red}FAILED: $1${Color_Off}"
	out ""
	out "Rollback to PHP ${PHP_CUR}:"
	if isDebianFamily; then
		if [ "$SAPI_MODE" = "fpm" ]; then
			out "  a2disconf php${TARGET}-fpm ; a2enconf php${PHP_CUR}-fpm"
		else
			out "  a2dismod php${TARGET} ; a2enmod php${PHP_CUR}"
		fi
		out "  update-alternatives --set php /usr/bin/php${PHP_CUR}"
		out "  systemctl restart apache2"
	elif isEL7; then
		out "  $PKG_MGR downgrade -y --enablerepo=remi,remi-php${PHP_CUR//./} 'php*'"
		out "  cp -a $BACKUP_DIR/$(basename "$PHP_INI") $PHP_INI"
		out "  cp -a $BACKUP_DIR/php.d/. /etc/php.d/"
		out "  systemctl restart httpd"
	else
		out "  $PKG_MGR module reset -y php"
		out "  $PKG_MGR module enable -y php:remi-${PHP_CUR}"
		out "  $PKG_MGR install -y $DNF_SKIP $PHP_PKGS"
		out "  cp -a $BACKUP_DIR/$(basename "$PHP_INI") $PHP_INI"
		out "  cp -a $BACKUP_DIR/php.d/. /etc/php.d/"
		out "  systemctl restart httpd"
	fi
	out ""
	out "What was installed before this run is listed in:"
	out "  $BACKUP_DIR/php-packages-before.txt"
	exit 1
}

set_ini() {
	key="$1"
	value="$2"
	if grep -qE "^\s*;?\s*${key}\s*=" "$NEW_INI"; then
		sed -i -E "s|^\s*;?\s*${key}\s*=.*|${key} = ${value}|" "$NEW_INI"
	else
		echo "${key} = ${value}" >>"$NEW_INI"
	fi
}

phpUpgradeDo() {
	local rc INI_LIST CA_BUNDLE
	out "${Yellow}About to upgrade PHP from ${PHP_CUR} to ${TARGET}.${Color_Off}"
	out ""
	out "This restarts the web server. The CRM will be unreachable for a minute,"
	out "and every ionCube encoded module stays dead until the loader for"
	out "${TARGET} is in place, which is a later step in this same run."
	out ""
	out "If it fails partway, the rollback is printed at the end."
	out ""
	if [ "$ASSUME_YES" != "yes" ]; then
		printf "Type the word upgrade to continue: "
		read -r answer
		if [ "$answer" != "upgrade" ]; then
			out "Cancelled. Nothing was changed."
			exit 0
		fi
	fi
	if ! timeout 5 bash -c "exec 3<>/dev/tcp/${PRIMARY_SITE}/80" >/dev/null 2>&1; then
		err "Cannot reach ${PRIMARY_SITE}, where the ionCube loader comes from. Nothing was changed."
		exit 5
	fi

	# ---- 1. keep what we are about to replace -----------------------------------
	out "${Cyan}Saving the current configuration...${Color_Off}"
	mkdir -p "$BACKUP_DIR" || fail_out "could not create $BACKUP_DIR"
	if [ "$PHP_INI" != "none" ] && [ -f "$PHP_INI" ]; then
		cp -a "$PHP_INI" "$BACKUP_DIR/" || fail_out "could not copy $PHP_INI"
	fi
	if isDebianFamily; then
		if [ -d "/etc/php/$PHP_CUR" ]; then
			cp -a "/etc/php/$PHP_CUR" "$BACKUP_DIR/php-$PHP_CUR" || fail_out "could not copy /etc/php/$PHP_CUR"
		fi
		dpkg -l 'php*' >"$BACKUP_DIR/php-packages-before.txt" 2>/dev/null || true
	else
		if [ -d /etc/php.d ]; then
			cp -a /etc/php.d "$BACKUP_DIR/php.d" || fail_out "could not copy /etc/php.d"
		fi
		rpm -qa 'php*' >"$BACKUP_DIR/php-packages-before.txt" 2>/dev/null || true
	fi
	out "  saved to $BACKUP_DIR"
	out ""

	# ---- 2. repositories --------------------------------------------------------
	out "${Cyan}Enabling the repositories...${Color_Off}"
	if isRHEL; then
		if ! isFedora; then
			run "$PKG_MGR" install -y epel-release || out "  ${Yellow}epel-release not installed, continuing${Color_Off}"
		fi
		if [ "$REMI" = "yes" ]; then
			out "  remi is already configured"
		elif isFedora; then
			run "$PKG_MGR" install -y "https://rpms.remirepo.net/fedora/remi-release-${OS_MAJOR}.rpm" ||
				run "$PKG_MGR" install -y "$(mirrorURL "remi-release-fedora-${OS_MAJOR}.rpm")" ||
				fail_out "the remi repository could not be installed. Without it PHP ${TARGET} is not available on ${OS_NAME}."
		else
			# the ParsVT mirror first: national-internet servers reach it, rpms.remirepo.net they may not
			run "$PKG_MGR" install -y "http://${PRIMARY_SITE}/modules/addons/easyservice/Installer/remi-release-${OS_MAJOR}.rpm" ||
				run "$PKG_MGR" install -y "https://rpms.remirepo.net/enterprise/remi-release-${OS_MAJOR}.rpm" ||
				fail_out "the remi repository could not be installed. Without it PHP ${TARGET} is not available on ${OS_NAME}."
		fi
	else
		run debianAddPHPRepo "$TARGET" || fail_out "the PHP repository (ondrej PPA / packages.sury.org) could not be added"
	fi
	out ""

	# ---- 3. the module stream ---------------------------------------------------
	if isRHEL && ! isEL7; then
		out "${Cyan}Switching the PHP module stream to remi-${TARGET}...${Color_Off}"
		run "$PKG_MGR" module reset -y php || fail_out "module reset failed"
		run "$PKG_MGR" module enable -y "php:remi-${TARGET}" || fail_out "could not enable php:remi-${TARGET}"
		out ""
	fi

	# ---- 4. install -------------------------------------------------------------
	out "${Cyan}Installing PHP ${TARGET} and its extensions...${Color_Off}"
	if isEL7; then
		# shellcheck disable=SC2086
		run "$PKG_MGR" upgrade -y $EL7_REPOS $DNF_SKIP 'php*' || fail_out "the PHP packages could not be upgraded from remi-php${TARGET//./}"
		# shellcheck disable=SC2086
		run "$PKG_MGR" install -y $EL7_REPOS $DNF_SKIP $PHP_PKGS || fail_out "the PHP packages did not install"
	elif isRHEL; then
		# shellcheck disable=SC2086
		run "$PKG_MGR" install -y $DNF_SKIP $PHP_PKGS || fail_out "the PHP packages did not install"
	else
		# shellcheck disable=SC2086
		run pkgInstall $PHP_PKGS || fail_out "the PHP packages did not install"
		run debianSwitchApachePHP "$TARGET" "$SAPI_MODE" || fail_out "Apache could not be switched to PHP ${TARGET}"
	fi
	out ""
	NEW_PHP="$("$NEW_PHP_BIN" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo unknown)"
	if [ "$NEW_PHP" != "$TARGET" ]; then
		fail_out "php reports ${NEW_PHP}, not ${TARGET}. The version switch did not take effect."
	fi
	out "${Green}PHP is now ${NEW_PHP}.${Color_Off}"
	out ""

	# ---- 5. ionCube loader ------------------------------------------------------
	# This is the step that decides whether the CRM comes back at all.
	if [ "$DO_IONCUBE" = "yes" ]; then
		out "${Cyan}Installing the ionCube loader for ${TARGET}...${Color_Off}"
		LOADER_TGZ="$(ionCubeArchive)"
		NEW_EXT_DIR="$(getPHPExtDir "$TARGET")"
		if [ -z "$NEW_EXT_DIR" ] || [ ! -d "$NEW_EXT_DIR" ]; then
			fail_out "extension_dir is ${NEW_EXT_DIR:-empty}, so the loader has nowhere to go"
		fi
		cd /tmp || fail_out "cannot use /tmp"
		rm -rf ioncube ioncube_loaders_lin*.tar.gz*
		fetchFile "$LOADER_TGZ" "$(mirrorURL "$LOADER_TGZ")" "https://downloads.ioncube.com/loader_downloads/$LOADER_TGZ" ||
			fail_out "the loader archive could not be downloaded"
		run tar xfz "$LOADER_TGZ" || fail_out "the loader archive could not be extracted"
		LOADER_SO="ioncube/ioncube_loader_lin_${TARGET}.so"
		if [ ! -f "$LOADER_SO" ]; then
			out ""
			out "  available loaders in this archive:"
			ls -1 ioncube/ioncube_loader_lin_*.so 2>/dev/null | sed 's/^/    /' || true
			fail_out "there is no loader for PHP ${TARGET} in the archive. Get a newer archive from ionCube."
		fi
		cp "$LOADER_SO" "$NEW_EXT_DIR/" || fail_out "the loader could not be copied to $NEW_EXT_DIR"
		phpWriteExtIni ioncube "zend_extension = ${NEW_EXT_DIR}/ioncube_loader_lin_${TARGET}.so" 00 "$TARGET" ||
			fail_out "the ionCube ini file could not be written in $(getPHPExtConfDir "$TARGET")"
		rm -rf /tmp/ioncube /tmp/ioncube_loaders_lin*.tar.gz*
		cd /root 2>/dev/null || cd /
		if "$NEW_PHP_BIN" -r 'exit(extension_loaded("ionCube Loader") ? 0 : 1);' 2>/dev/null; then
			LOADED="$("$NEW_PHP_BIN" -r 'echo function_exists("ioncube_loader_version") ? ioncube_loader_version() : "unknown";' 2>/dev/null)"
			out "${Green}  loader active, version ${LOADED}${Color_Off}"
		else
			fail_out "the loader was placed but PHP does not load it. Check $(getPHPExtConfDir "$TARGET") and the PHP error log."
		fi
		out ""
	else
		out "${Yellow}Skipping the ionCube loader at your request.${Color_Off}"
		out "  Install it yourself before starting the CRM, or nothing encoded will run."
		out ""
	fi

	# ---- 5b. timezonedb: a module built for the old PHP API does not load; rebuild or switch off
	if grep -rqs "timezonedb" "$BACKUP_DIR"; then
		out "${Cyan}Rebuilding the timezonedb extension for ${TARGET}...${Color_Off}"
		rc=0
		if isRHEL; then
			(
				cd /tmp && rm -rf timezonedb-2026.6.tgz &&
					fetchFile timezonedb-2026.6.tgz "$(mirrorURL timezonedb-2026.6.tgz)" "https://pecl.php.net/get/timezonedb-2026.6.tgz" &&
					pear install -f timezonedb-2026.6.tgz
			) >/dev/null 2>&1 || rc=$?
			rm -f /tmp/timezonedb-2026.6.tgz
		else
			installTimezonedbSource "$TARGET" >/dev/null 2>&1 || rc=$?
		fi
		if [ "$rc" -eq 0 ] && "$NEW_PHP_BIN" -m 2>/dev/null | grep -qi "^timezonedb$"; then
			out "${Green}  timezonedb rebuilt${Color_Off}"
		else
			out "  ${Yellow}timezonedb could not be rebuilt and is switched off; PHP uses its own time zone data.${Color_Off}"
			if isRHEL; then
				sed -i -E 's/^\s*extension\s*=\s*timezonedb\.so/;extension=timezonedb.so/' "$(getPHPIniPath)" 2>/dev/null
			else
				phpdismod -v "$TARGET" -s ALL timezonedb >/dev/null 2>&1
			fi
		fi
		out ""
	fi

	# ---- 6. php.ini settings ----------------------------------------------------
	# A fresh PHP brings a fresh php.ini with none of the CRM's requirements in
	# it. These are the same values the ParsVT installer sets.
	out "${Cyan}Applying the CRM's php.ini settings...${Color_Off}"
	if isRHEL; then
		INI_LIST="/etc/php.ini"
		if [ ! -f "$INI_LIST" ]; then
			INI_LIST="$(php -r 'echo php_ini_loaded_file() ?: "";' 2>/dev/null)"
		fi
	else
		INI_LIST="$(getPHPIniPath apache2 "$TARGET") $(getPHPIniPath cli "$TARGET")"
		if [ "$SAPI_MODE" = "fpm" ]; then
			INI_LIST="$INI_LIST $(getPHPIniPath fpm "$TARGET")"
		fi
	fi
	CA_BUNDLE="$(getCABundle)"
	for NEW_INI in $INI_LIST; do
		if [ -z "$NEW_INI" ] || [ ! -f "$NEW_INI" ]; then
			out "  ${Yellow}${NEW_INI:-php.ini} not found, skipping. Set the values by hand.${Color_Off}"
			continue
		fi
		set_ini "max_execution_time" "600"
		set_ini "max_input_time" "600"
		set_ini "memory_limit" "512M"
		set_ini "max_input_vars" "10000"
		set_ini "post_max_size" "128M"
		set_ini "upload_max_filesize" "128M"
		set_ini "default_socket_timeout" "600"
		set_ini "output_buffering" "4096"
		set_ini "file_uploads" "On"
		set_ini "short_open_tag" "On"
		set_ini "log_errors" "On"
		set_ini "display_errors" "Off"
		set_ini "expose_php" "Off"
		set_ini "zlib.output_compression" "Off"
		set_ini "date.timezone" '"Asia/Tehran"'
		set_ini "session.gc_maxlifetime" "21600"
		set_ini "session.use_strict_mode" "1"
		set_ini "session.cookie_httponly" "1"
		# The CA bundle, which PHP on a fresh install does not point at. Without
		# it the migration package download fails with cURL error 60.
		if [ -f "$CA_BUNDLE" ]; then
			set_ini "curl.cainfo" "\"$CA_BUNDLE\""
			set_ini "openssl.cafile" "\"$CA_BUNDLE\""
		fi
		out "  applied to $NEW_INI"
	done
	out ""

	# ---- 7. restart -------------------------------------------------------------
	out "${Cyan}Restarting the web server...${Color_Off}"
	if [ "$WEBSERVER" = "httpd" ] || [ "$WEBSERVER" = "apache2" ]; then
		run svcRestart httpd || fail_out "the web server did not restart. Check: systemctl status $(svcName httpd)"
	fi
	if [ "$PHP_SAPI_FPM" = "yes" ] || [ "$SAPI_MODE" = "fpm" ]; then
		run systemctl restart "$(getPHPServiceName "$TARGET")" || out "  ${Yellow}php-fpm did not restart, check it by hand${Color_Off}"
	fi
	out ""

	# ---- 8. verify --------------------------------------------------------------
	out "${Cyan}Verifying...${Color_Off}"
	FINAL_PHP="$("$NEW_PHP_BIN" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo unknown)"
	out "  php version     : $FINAL_PHP"
	MISSING_EXT=""
	for ext in mysqli curl xml mbstring zip gd intl soap bcmath; do
		if ! "$NEW_PHP_BIN" -r "exit(extension_loaded('$ext') ? 0 : 1);" 2>/dev/null; then
			MISSING_EXT="$MISSING_EXT $ext"
		fi
	done
	if [ -n "$MISSING_EXT" ]; then
		out "  ${Yellow}missing extensions:$MISSING_EXT${Color_Off}"
	else
		out "  extensions      : all present"
	fi
	if "$NEW_PHP_BIN" -r 'exit(extension_loaded("ionCube Loader") ? 0 : 1);' 2>/dev/null; then
		out "  ionCube loader  : active"
	else
		out "  ${Red}ionCube loader  : NOT ACTIVE${Color_Off}"
	fi
	out ""
	if [ "$FINAL_PHP" != "$TARGET" ]; then
		fail_out "php reports $FINAL_PHP after the restart, not $TARGET"
	fi
	out "${Green}PHP ${TARGET} is installed and running.${Color_Off}"
	out ""
	out "The old configuration is kept at:"
	out "  $BACKUP_DIR"
	out ""
	out "Next:"
	out "  1. open the CRM and log in. If a page is blank, the loader is the first"
	out "     thing to check:  $NEW_PHP_BIN -m | grep -i ioncube"
	out "  2. go back to the migration wizard and confirm this step"
	out "  3. the wizard re-reads the PHP version from the server, so it will see"
	out "     ${TARGET} and move on to the Vtiger 8.4.0 step"
	out ""
	if [ -n "$MISSING_EXT" ]; then
		out "${Yellow}Install the missing extensions before continuing:$MISSING_EXT${Color_Off}"
		exit 1
	fi
	exit 0
}

# Entry point: --php-upgrade or menu option 6. Always exits. Runs without set -e, like the standalone script.
phpUpgrade() {
	set +e
	phpUpgradeParseArgs "$@"
	phpUpgradeDetect
	if [ "$AS_JSON" = "yes" ]; then
		phpUpgradeJSON
		exit 0
	fi
	phpUpgradeReport
	if [ "$PANEL" != "none" ]; then
		phpUpgradePanelStop
	fi
	phpUpgradeOSCheck
	phpUpgradePreconditions
	phpUpgradePackages
	if [ "$MODE" = "check" ]; then
		phpUpgradeCheck
	fi
	if [ "$MODE" = "dryrun" ]; then
		phpUpgradeDryRun
	fi
	phpUpgradeDo
}

# #############################################################################
# Main flow
# #############################################################################
for cliarg in "$@"; do
	case "$cliarg" in
	--php-upgrade) PHP_UPGRADE_CLI="yes" ;;
	--convert-to-alma) CONVERT_CLI="yes" ;;
	-h | --help)
		printHelp
		exit 0
		;;
	esac
done
detectOS
detectPanel
detectPackageManager
major="$RHEL_MAJOR"
if [ "$PHP_UPGRADE_CLI" = "yes" ]; then
	phpUpgrade "$@"
fi
if [ "$CONVERT_CLI" = "yes" ] && [ $# -eq 1 ]; then
	convertToAlma
fi
if [ $# -gt 0 ]; then
	echo -e "${Red}Unknown arguments: $*${Color_Off}" >&2
	echo "The PHP upgrader options need --php-upgrade. Run with --help." >&2
	exit 2
fi
echo -e "\n${Yellow}██████   █████  ██████  ███████ ██    ██ ████████"
echo -e "██   ██ ██   ██ ██   ██ ██      ██    ██    ██   "
echo -e "██████  ███████ ██████  ███████ ██    ██    ██   "
echo -e "██      ██   ██ ██   ██      ██  ██  ██     ██   "
echo -e "██      ██   ██ ██   ██ ███████   ████      ██   \n"
echo -e "Shell script to install ParsVT CRM on Linux.\n"
printSupportedOS
echo -e "\nPlease run as root. if you are not, enter '0' now and enter 'sudo su' before running the script.${Color_Off}"
printSystemInfo
if [ "$PANEL" != "none" ]; then
	output ""
	installerPanelStop
fi
if ! isSupportedOS; then
	output "\n${Red}Operating system is not supported!${Color_Off}"
	output "Detected: ${OS_NAME}"
	printSupportedOS
	output "${Yellow}www.parsvt.com${Color_Off}\n"
	exit 4
fi
if isNewerThanTested; then
	output "\n${Yellow}${UNTESTED_NOTE}${Color_Off}"
fi
startInstallation
restoreDNS
cd /root
if [ "$installationType" = "Install" ] || [ "$installationType" = "Install2" ]; then
	if [ -e /var/www/html/config.inc.php ]; then
		output "\n${Red}VtigerCRM already exists!${Color_Off}"
		output "Press Ctrl+C within the next 10 seconds to cancel the installation."
		output "Otherwise, wait until the installation continues, but it will destroy the existing data!"
		INSTALLTYPE="Exist"
		sleep 10
	fi
	if [ "$installationType" != "Install2" ]; then
		checkInternetConnection
	fi
	prepareOS "You have to install Apache, PHP and MySQL manually."
	output "Installing: ${Green}Vtiger ${VTIGER_VERSION} / PHP ${PHP_TARGET}${Color_Off}"
	checkSupportedCombination
	if [ "$installationType" = "Install2" ] && ! isNationalInternetCapable; then
		output "\n${Red}Operating system is not supported!${Color_Off}"
		output "ParsVT (No-Internet) installer only installs on AlmaLinux 9."
		abortOperation
	fi
	read -ra ipsarray <<<"$(getAllIPs)"
	if [ "${#ipsarray[@]}" -gt 0 ]; then
		if [ "${#ipsarray[@]}" -gt 1 ]; then
			output "\nThe following ethernet devices found! Please enter the item number you want to use: "
			COUNT=0
			for i in "${ipsarray[@]}"; do
				:
				output "# $COUNT - $i"
				COUNT=$((COUNT + 1))
			done
			read -rp "Please select an IP address: " DEVS
			if ! [[ "$DEVS" =~ ^[0-9]+$ ]] || [ -z "${ipsarray[$DEVS]:-}" ]; then
				output "${Red}Invalid ethernet adapter!${Color_Off}"
				abortOperation
			fi
			ETH_DEV=${ipsarray[$DEVS]}
		else
			ETH_DEV=${ipsarray[0]}
		fi
	else
		output "${Red}Your ethernet device not found!${Color_Off}"
		abortOperation
	fi
	output "\nParsVT CRM will be installed on ${Green}${ETH_DEV}${Color_Off}\n"
	checkLicense
	ensureBootstrapTools
	RESPONSE=$(curl -fs --connect-timeout 15 --retry 2 -d "licenseid=$LICENSEKEY&serverip=$ETH_DEV" -H "Content-Type: application/x-www-form-urlencoded" -X POST "http://$primarySite/modules/addons/easyservice/Installer/check.php" || true)
	if [ -z "$RESPONSE" ]; then
		output "\n${Red}The license server ($primarySite) could not be reached. Check the network and DNS and run the installer again.${Color_Off}"
		abortOperation
	fi
	IFS=';' read -ra RESPONSES <<<"$RESPONSE"
	if [ "${RESPONSES[0]}" != "Active" ] || [ "${#RESPONSES[2]}" == 0 ]; then
		output "\nLicense key status: ${Red}${RESPONSES[0]}!${Color_Off}"
		output "\n${Red}${RESPONSES[1]}${Color_Off}"
		output "For more information, please contact us."
		abortOperation
	fi
	output "\n${Green}${LICENSEKEY}${Color_Off} will be used as the license key.\n"
	askBackupKeep
	if [ "$installationType" != "Install2" ]; then
		setDNS
	fi
	disableSELinux
	updatePackage
	installPackage
	requireDownloadTools
	installPHPRepository
	if ! command -v "php" &>/dev/null; then
		installApachePHP "$PHP_TARGET"
		output "${Cyan}Installing ionCube loader...${Color_Off}"
		installIonCube
		output "${Green}ionCube loader successfully installed!${Color_Off}\n"
	else
		checkPHPAndIonCube install "$PHP_TARGET"
	fi
	installTimezonedb
	setRequirements
	installMariaDB
	restartDatabase
	installVtiger "$VTIGER_VERSION"
	installJava
	setupBackup
	installWebmin
	openPorts
	svcEnableNow crond
	systemctl daemon-reload
	printDoneBanner
	output "${Green}ParsVT installation successfully completed!${Color_Off}\n"
	output "Webmin Information:"
	output "  Webmin URL:        ${Yellow}http://$ETH_DEV:10000${Color_Off}"
	output "  Webmin Username:   ${Yellow}$USER${Color_Off}"
	output "  Webmin Password:   ${Yellow}$USER SSH Password${Color_Off}\n"
	output "MySQL Information:"
	output "  Database Hostname: ${Yellow}$DBHOST${Color_Off}"
	output "  Database Username: ${Yellow}$DBUSER${Color_Off}"
	output "  Database Password: ${Yellow}$DBPassword${Color_Off}"
	output "  Database Name:     ${Yellow}$DBNAME${Color_Off}\n"
	output "CRM URL:      http://$CRMURL\nCRM Username: admin\nCRM Password: $adminPWD" >/root/crm.txt
	chmod 600 /root/crm.txt
	output "Vtiger Information:"
	output "  CRM URL:           ${Yellow}http://$CRMURL${Color_Off}"
	output "  CRM Username:      ${Yellow}admin${Color_Off}"
	output "  CRM Password:      ${Yellow}$adminPWD${Color_Off}\n"
	printBackupInfo
	output ""
	{ echo; printBackupInfo; } >>/root/crm.txt
	printInstallSummary
	output "For more information, visit: www.parsvt.com\n"
fi
if [ "$installationType" = "Repair" ]; then
	if [ ! -f "/var/www/html/config.inc.php" ]; then
		output "\n${Red}VtigerCRM is not installed!${Color_Off}"
		abortOperation
	fi
	if ! readCRMDBConfig; then
		output "\n${Red}Could not read db_server, db_username, db_password and db_name from /var/www/html/config.inc.php.${Color_Off}"
		output "The backup and restore scripts were not reinstalled."
		abortOperation
	fi
	if [ -f "/home/backup-$DBNAME.sh" ]; then
		output "${Yellow}/home/backup-$DBNAME.sh is no longer used (replaced by /usr/local/bin/parsvt-backup.sh); it does not need to be deleted.${Color_Off}"
	fi
	if ls "$backupdirectory/$DBNAME"-[0-9][0-9][0-9][0-9]-*.gz >/dev/null 2>&1; then
		output "${Yellow}Backups in the old format ($backupdirectory/$DBNAME-YYYY-DD-MM.*, $(du -ch "$backupdirectory/$DBNAME"-[0-9][0-9][0-9][0-9]-*.gz | tail -1 | cut -f1)) are not removed automatically; delete them once new backups exist.${Color_Off}"
	fi
	readBackupKeep
	installBackupScripts
	backupCron
	output "${Green}Backup and restore scripts installed in /usr/local/bin.${Color_Off}"
	checkInternetConnection
	prepareOS "ParsVT repair script only works on the operating systems listed above."
	setDNS
	disableSELinux
	set +e
	updatePackage
	installPackage
	set -e
	requireDownloadTools
	if isRHEL; then
		if [ ! -f "/etc/yum.repos.d/remi.repo" ]; then
			output "${Red}Remi repository is not installed!${Color_Off}"
			abortOperation
		fi
		output "${Green}Remi repository is already installed!${Color_Off}\n"
	fi
	checkPHPAndIonCube repair
	if ! hasApache; then
		output "${Red}Apache is not installed!${Color_Off}"
		abortOperation
	fi
	output "${Green}Apache is already installed!${Color_Off}\n"
	installTimezonedb
	setRequirements
	if ! type mysql >/dev/null 2>&1; then
		output "${Red}MySQL is not installed!${Color_Off}"
		abortOperation
	fi
	output "${Green}MySQL is already installed!${Color_Off}\n"
	installJava
	output "${Cyan}Fixing permissions of directories and files...${Color_Off}"
	chown -R "$(getWebUser)" /var/www/html
	find /var/www/html -type d -exec chmod 0755 {} \;
	find /var/www/html -type f -exec chmod 0644 {} \;
	output "${Green}Permissions of directories and files successfully fixed!${Color_Off}\n"
	set +e
	openPorts
	set -e
	svcEnableNow crond
	systemctl daemon-reload
	printDoneBanner
	output "${Green}ParsVT repair successfully completed!${Color_Off}\n"
fi
if [ "$installationType" = "ionCube" ]; then
	checkInternetConnection
	prepareOS "You have to install/update ionCube loader manually."
	requireDownloadTools
	checkPHPAndIonCube ioncube
fi
if [ "$installationType" = "clamAV" ]; then
	checkInternetConnection
	prepareOS "You have to install ClamAV manually."
	setDNS
	set +e
	updatePackage
	installPackage
	set -e
	requireDownloadTools
	output "${Cyan}Installing ClamAV...${Color_Off}"
	if isDebianFamily; then
		pkgInstall clamav clamav-freshclam acl
	else
		$(rhelPM) install $DNF_SKIP epel-release -y
		$(rhelPM) install $DNF_SKIP clamav clamav-update -y
	fi
	if ! command -v clamscan >/dev/null 2>&1; then
		output "${Red}ClamAV could not be installed.${Color_Off}"
		abortOperation
	fi
	# the ClamAV CDN refuses some regions (Iran included); a failed update must not stop the setup
	set +e
	systemctl stop clamav-freshclam >/dev/null 2>&1
	freshclam || output "${Yellow}freshclam could not update the signatures; it retries daily.${Color_Off}"
	if isDebianFamily; then
		systemctl start clamav-freshclam >/dev/null 2>&1
	fi
	set -e
	mkdir -p /var/log/clamav
	touch /var/log/clamav/daily_scan.log
	chmod 0755 /var/log/clamav
	chmod 0640 /var/log/clamav/daily_scan.log
	if ! fetchFile /usr/local/bin/daily_clamscan.sh "$(mirrorURL daily_clamscan.txt)"; then
		# our scan script is unreachable: a minimal daily scan of the CRM directory
		printf '#!/bin/bash\nclamscan -r -i --log=/var/log/clamav/daily_scan.log /var/www/html >/dev/null 2>&1\n' >/usr/local/bin/daily_clamscan.sh
		output "${Yellow}daily_clamscan.txt could not be downloaded; a minimal scan of /var/www/html was set up instead.${Color_Off}"
	fi
	chmod 700 /usr/local/bin/daily_clamscan.sh
	setfacl -m u:root:rwx /var/log/clamav
	setfacl -m u:root:rx /usr/local/bin/daily_clamscan.sh
	cronAdd "/usr/local/bin/daily_clamscan.sh" "0 2 * * * /usr/local/bin/daily_clamscan.sh"
	svcEnableNow crond
	systemctl daemon-reload
	output "${Green}ClamAV successfully installed!${Color_Off}\n"
fi
if [ "$installationType" = "SSL" ]; then
	if [ ! -f "/var/www/html/config.inc.php" ]; then
		output "\n${Red}VtigerCRM is not installed!${Color_Off}"
		abortOperation
	fi
	checkInternetConnection
	prepareOS "You have to install SSL manually."
	setDNS
	set +e
	updatePackage
	installPackage
	set -e
	requireDownloadTools
	output "${Cyan}Installing SSL certificate requirements...${Color_Off}"
	if isDebianFamily; then
		pkgInstall certbot python3-certbot-apache
	else
		# 1. certbot from snap (current releases), 2. the EPEL package when the snap store is unreachable
		$(rhelPM) install $DNF_SKIP epel-release -y
		$(rhelPM) install $DNF_SKIP snapd mod_ssl -y || true
		if command -v snap >/dev/null 2>&1 && systemctl enable --now snapd.socket >/dev/null 2>&1; then
			if [ ! -L "/snap" ]; then
				ln -s /var/lib/snapd/snap /snap
			fi
			if timeout 600 snap install --classic certbot; then
				pkgRemove certbot >/dev/null 2>&1 || true
				ln -sf /snap/bin/certbot /usr/bin/certbot
			fi
		fi
		if ! command -v certbot >/dev/null 2>&1; then
			output "${Yellow}certbot from snap is not available; installing the EPEL package.${Color_Off}"
			$(rhelPM) install $DNF_SKIP certbot python3-certbot-apache python-certbot-apache -y
		fi
	fi
	if ! command -v certbot >/dev/null 2>&1; then
		output "${Red}certbot could not be installed.${Color_Off}"
		abortOperation
	fi
	output "${Green}SSL certificate requirements successfully installed!${Color_Off}\n"
	sslDomain
fi
if [ "$installationType" = "PHP" ]; then
	echo -e "\nPHP 8.3 upgrade (step 3 of the Vtiger 7.x to 8.4.0 migration):"
	echo -e "[${Cyan}1${Color_Off}] ${Cyan}Check - detect and report, change nothing${Color_Off}"
	echo -e "[${Cyan}2${Color_Off}] ${Cyan}Dry-run - show every command, run none${Color_Off}"
	echo -e "[${Yellow}3${Color_Off}] ${Yellow}Upgrade${Color_Off}"
	echo -e "[${Yellow}0${Color_Off}] ${Yellow}Cancel${Color_Off}\n"
	read -rp "Please select an action (0-3): " pumode
	if [ "$pumode" == "1" ]; then
		phpUpgrade --check
	elif [ "$pumode" == "2" ]; then
		phpUpgrade --dry-run
	elif [ "$pumode" == "3" ]; then
		phpUpgrade --upgrade
	else
		abortOperation 0
	fi
fi
if [ "$installationType" = "Convert" ]; then
	convertToAlma
fi
restoreDNS
