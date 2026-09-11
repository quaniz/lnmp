#!/usr/bin/env bash

Nginx_Dependent()
{
    if [ "$PM" = "yum" ]; then
        rpm -e httpd httpd-tools --nodeps
        yum -y remove httpd*
        for packages in make gcc gcc-c++ gcc-g77 wget crontabs zlib zlib-devel openssl openssl-devel perl perl-FindBin patch bzip2 initscripts xz gzip;
        do yum -y install $packages; done
        if [ "${DISTRO}" = "Fedora" ] || echo "${CentOS_Version}" | grep -Eqi "^9"; then
            dnf install chkconfig -y
        fi
    elif [ "$PM" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
        dpkg -P apache2 apache2-doc apache2-mpm-prefork apache2-utils apache2.2-common
        for removepackages in apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker;
        do apt-get purge -y $removepackages; done
        for packages in debian-keyring debian-archive-keyring build-essential gcc g++ make autoconf automake wget cron openssl libssl-dev zlib1g zlib1g-dev perl bzip2 xz-utils gzip;
        do apt-get --no-install-recommends install -y $packages; done
    fi
}

Install_Only_Nginx()
{
    clear
    echo "+-----------------------------------------------------------------------+"
    echo "|              Install Nginx for LNMP, Written by Licess                |"
    echo "+-----------------------------------------------------------------------+"
    echo "|                     A tool to only install Nginx.                     |"
    echo "+-----------------------------------------------------------------------+"
    echo "|           For more information please visit https://lnmp.org          |"
    echo "+-----------------------------------------------------------------------+"
    Press_Install
    Echo_Blue "Install dependent packages..."
    cd ${cur_dir}/src
    Get_Dist_Version
    Modify_Source
    Nginx_Dependent
    cd ${cur_dir}/src
    Download_Files ${Download_Mirror}/web/pcre/${Pcre_Ver}.tar.bz2 ${Pcre_Ver}.tar.bz2
    Install_Pcre
    if [ `grep -L '/usr/local/lib'    '/etc/ld.so.conf'` ]; then
        echo "/usr/local/lib" >> /etc/ld.so.conf
    fi
    ldconfig
    Download_Files ${Download_Mirror}/web/nginx/${Nginx_Ver}.tar.gz ${Nginx_Ver}.tar.gz
    Install_Nginx
    StartUp nginx
    rm -rf ${cur_dir}/src/${Nginx_Ver}
    [[ -d "${cur_dir}/src/${Openssl_Ver}" ]] && rm -rf ${cur_dir}/src/${Openssl_Ver}
    [[ -d "${cur_dir}/src/${Openssl_Compat_Ver}" ]] && rm -rf ${cur_dir}/src/${Openssl_Compat_Ver}
    [[ -d "${cur_dir}/src/${Openssl_New_Ver}" ]] && rm -rf ${cur_dir}/src/${Openssl_New_Ver}
    StartOrStop start nginx
    Add_Iptables_Rules
    \cp ${cur_dir}/conf/index.html ${Default_Website_Dir}/index.html
    \cp ${cur_dir}/conf/lnmp /bin/lnmp
    chmod +x /bin/lnmp
    Check_Nginx_Files
}

Resolve_Harfbuzz_Library()
{
    ldconfig -p 2>/dev/null | awk '$1 == "libharfbuzz.so.0" { print $NF; exit }'
}

Resolve_Harfbuzz_Freetype()
{
    local Harfbuzz_Lib

    Harfbuzz_Lib=$(Resolve_Harfbuzz_Library)
    [ -n "${Harfbuzz_Lib}" ] || return 1
    env -u LD_LIBRARY_PATH ldd "${Harfbuzz_Lib}" 2>/dev/null | \
        awk '$1 ~ /^libfreetype\.so/ && $2 == "=>" { print $3; exit }'
}

Freetype_Has_Color_Glyph_Layer()
{
    local Freetype_Lib="$1"

    [ -r "${Freetype_Lib}" ] || return 1
    readelf --wide -Ws "${Freetype_Lib}" 2>/dev/null | \
        awk '$8 ~ /^FT_Get_Color_Glyph_Layer(@@.*)?$/ { found=1 } END { exit !found }'
}

Resolve_Bundled_Freetype()
{
    local Freetype_Lib

    for Freetype_Lib in /usr/local/freetype/lib/libfreetype.so.6 /usr/local/freetype/lib64/libfreetype.so.6; do
        if [ -r "${Freetype_Lib}" ]; then
            printf '%s\n' "${Freetype_Lib}"
            return 0
        fi
    done
    return 1
}

Use_System_Freetype()
{
    local Freetype_Ld_Config='/etc/ld.so.conf.d/freetype.conf'
    local Freetype_Ld_Backup
    local Freetype_Pc_File='/usr/lib/pkgconfig/freetype2.pc'
    local Freetype_Pc_Backup
    local Bundled_Freetype
    local Bundled_Freetype_Lib_Dir
    local Harfbuzz_Lib
    local Runtime_Freetype

    Echo_Blue "Use the system FreeType for PHP 8..."
    if [ "$PM" = "yum" ]; then
        yum -y install freetype freetype-devel harfbuzz harfbuzz-devel
    elif [ "$PM" = "apt" ]; then
        apt-get --no-install-recommends install -y libfreetype6 libfreetype6-dev libharfbuzz0b libharfbuzz-dev
    fi

    # Older LNMP runs exposed /usr/local/freetype globally. On a modern
    # distribution this can make the system HarfBuzz load an incompatible
    # libfreetype.so and cause unrelated configure runtime tests to fail.
    if [ -f "${Freetype_Ld_Config}" ] && grep -Fxq '/usr/local/freetype/lib' "${Freetype_Ld_Config}"; then
        Freetype_Ld_Backup="${Freetype_Ld_Config}.lnmp-disabled.$(date +%Y%m%d%H%M%S)"
        mv "${Freetype_Ld_Config}" "${Freetype_Ld_Backup}"
        Echo_Yellow "Disabled legacy FreeType loader config: ${Freetype_Ld_Backup}"
    fi
    if [ -f "${Freetype_Pc_File}" ] && grep -Eq '^prefix=/usr/local/freetype$' "${Freetype_Pc_File}"; then
        Freetype_Pc_Backup="${Freetype_Pc_File}.lnmp-disabled.$(date +%Y%m%d%H%M%S)"
        mv "${Freetype_Pc_File}" "${Freetype_Pc_Backup}"
        Echo_Yellow "Disabled legacy FreeType pkg-config file: ${Freetype_Pc_Backup}"
    fi
    ldconfig
    if ! pkg-config --exists freetype2 harfbuzz; then
        Echo_Red "System FreeType/HarfBuzz development packages are unavailable."
        exit 1
    fi

    Harfbuzz_Lib=$(Resolve_Harfbuzz_Library)
    Runtime_Freetype=$(Resolve_Harfbuzz_Freetype)
    if [ -n "${Runtime_Freetype}" ] && Freetype_Has_Color_Glyph_Layer "${Runtime_Freetype}"; then
        Echo_Green "FreeType/HarfBuzz ABI check passed: ${Runtime_Freetype}"
        LNMP_USE_SYSTEM_FREETYPE='y'
        unset LNMP_PHP_FREETYPE_LIBRARY_PATH
        return 0
    fi

    # Some distributions can provide a HarfBuzz package built against
    # FreeType >= 2.10 while the runtime loader still selects an older
    # libfreetype.  PHP then reports this as an iconv errno failure because
    # the iconv configure probe happens to execute the first affected binary.
    Echo_Yellow "System FreeType/HarfBuzz ABI mismatch detected."
    [ -n "${Runtime_Freetype}" ] && Echo_Yellow "Incompatible runtime library: ${Runtime_Freetype}"
    Echo_Blue "Install a compatible bundled FreeType for PHP..."
    LNMP_FORCE_NEW_FREETYPE='y'
    LNMP_FREETYPE_DISABLE_HARFBUZZ='y'
    Install_Freetype
    unset LNMP_FORCE_NEW_FREETYPE
    unset LNMP_FREETYPE_DISABLE_HARFBUZZ

    Bundled_Freetype=$(Resolve_Bundled_Freetype)
    if [ -z "${Bundled_Freetype}" ] || ! Freetype_Has_Color_Glyph_Layer "${Bundled_Freetype}"; then
        Echo_Red "Bundled FreeType does not export FT_Get_Color_Glyph_Layer."
        exit 1
    fi
    Bundled_Freetype_Lib_Dir=$(dirname "${Bundled_Freetype}")
    if [ -z "${Harfbuzz_Lib}" ]; then
        Echo_Red "Cannot resolve the system libharfbuzz.so.0 runtime path."
        exit 1
    fi
    if env LD_LIBRARY_PATH="${Bundled_Freetype_Lib_Dir}" ldd -r "${Harfbuzz_Lib}" 2>&1 | grep -q 'undefined symbol: FT_Get_Color_Glyph_Layer'; then
        Echo_Red "Bundled FreeType is still incompatible with the system HarfBuzz."
        exit 1
    fi

    LNMP_USE_SYSTEM_FREETYPE='n'
    LNMP_PHP_FREETYPE_LIBRARY_PATH="${Bundled_Freetype_Lib_Dir}"
    export PKG_CONFIG_PATH="${Bundled_Freetype_Lib_Dir}/pkgconfig:${PKG_CONFIG_PATH:-}"
    Echo_Green "Bundled FreeType ABI check passed."
}

Install_Only_PHP()
{
    clear
    echo "+-----------------------------------------------------------------------+"
    echo "|                Install PHP for LNMP, Written by Licess                |"
    echo "+-----------------------------------------------------------------------+"
    echo "|                       A tool to only install PHP.                     |"
    echo "+-----------------------------------------------------------------------+"
    echo "|           For more information please visit https://lnmp.org          |"
    echo "+-----------------------------------------------------------------------+"

    if [[ -s /usr/local/php/bin/php || -s /usr/local/php/sbin/php-fpm ]]; then
        Echo_Red "PHP is already installed in /usr/local/php."
        exit 1
    fi

    # Reuse the PHP dependency installer used by the upgrade workflow.
    . include/upgrade_php.sh

    Stack="lnmp"
    DBSelect="${DBSelect:-0}"
    PHP_Selection
    Press_Install
    Get_Dist_Version
    MemTotal=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)
    Check_CMPT

    if [ "${CheckMirror}" != "n" ]; then
        Modify_Source
        Check_Mirror
    fi

    Echo_Blue "Install dependent packages..."
    Install_PHP_Dependent
    Check_Openssl

    cd ${cur_dir}/src
    if ! echo "${Php_Ver}" | grep -Eqi '^php-8\.'; then
        Download_Files ${Download_Mirror}/web/libiconv/${Libiconv_Ver}.tar.gz ${Libiconv_Ver}.tar.gz
        Install_Libiconv
        Install_Freetype
    else
        Use_System_Freetype
    fi

    if [ "$PM" = "yum" ]; then
        CentOS_Lib_Opt
    elif [ "$PM" = "apt" ]; then
        Deb_Lib_Opt
    fi

    if ! getent group www >/dev/null 2>&1; then
        groupadd www
    fi
    if ! id -u www >/dev/null 2>&1; then
        useradd -s /sbin/nologin -M -g www www
    fi

    Check_PHP_Option
    cd ${cur_dir}/src
    Download_Files ${Download_Mirror}/web/php/${Php_Ver}.tar.bz2 ${Php_Ver}.tar.bz2
    Install_PHP
    LNMP_PHP_Opt
    Clean_PHP_Src_Dir

    StartUp php-fpm
    StartOrStop start php-fpm
    Check_PHP_Files
    if [ "${isPHP}" = "ok" ]; then
        Echo_Green "Install ${Php_Ver} completed! enjoy it."
    fi
}

Install_Only_PhpMyAdmin()
{
    local PhpMyAdmin_Archive
    local PhpMyAdmin_Backup
    local PhpMyAdmin_Destination
    local PhpMyAdmin_Secret
    local PhpMyAdmin_Version

    clear
    echo "+-----------------------------------------------------------------------+"
    echo "|                    Install phpMyAdmin for LNMP                        |"
    echo "+-----------------------------------------------------------------------+"
    echo "|       This only deploys phpMyAdmin; it installs no server services.  |"
    echo "+-----------------------------------------------------------------------+"
    Press_Install

    PhpMyAdmin_Archive="${PhpMyAdmin_Ver}.tar.xz"
    PhpMyAdmin_Destination="${Default_Website_Dir}/phpmyadmin"
    PhpMyAdmin_Version="${PhpMyAdmin_Ver#phpMyAdmin-}"
    PhpMyAdmin_Version="${PhpMyAdmin_Version%-all-languages}"

    command -v tar >/dev/null 2>&1 || { Echo_Red "tar is required to install phpMyAdmin."; exit 1; }
    mkdir -p "${cur_dir}/src" "${Default_Website_Dir}" || exit 1
    cd "${cur_dir}/src" || exit 1

    if [ ! -s "${PhpMyAdmin_Archive}" ]; then
        Download_Files "https://files.phpmyadmin.net/phpMyAdmin/${PhpMyAdmin_Version}/${PhpMyAdmin_Archive}" "${PhpMyAdmin_Archive}"
        if [ $? -ne 0 ] || [ ! -s "${PhpMyAdmin_Archive}" ]; then
            Download_Files "${Download_Mirror}/datebase/phpmyadmin/${PhpMyAdmin_Archive}" "${PhpMyAdmin_Archive}"
        fi
    else
        Echo_Green "${PhpMyAdmin_Archive} [found], using local archive."
    fi
    if [ ! -s "${PhpMyAdmin_Archive}" ]; then
        Echo_Red "Unable to download ${PhpMyAdmin_Archive}."
        exit 1
    fi
    if ! Verify_Download_File "${PhpMyAdmin_Archive}"; then
        Echo_Red "Unable to verify ${PhpMyAdmin_Archive}."
        exit 1
    fi

    Tar_Cd "${PhpMyAdmin_Archive}" "${PhpMyAdmin_Ver}"
    cd "${cur_dir}/src" || exit 1

    if [ -e "${PhpMyAdmin_Destination}" ]; then
        PhpMyAdmin_Backup="${PhpMyAdmin_Destination}.backup.$(date +%Y%m%d%H%M%S)"
        [ -e "${PhpMyAdmin_Backup}" ] && PhpMyAdmin_Backup="${PhpMyAdmin_Backup}.$$"
        mv "${PhpMyAdmin_Destination}" "${PhpMyAdmin_Backup}" || exit 1
        Echo_Yellow "Existing phpMyAdmin backed up to ${PhpMyAdmin_Backup}"
    fi

    mv "${PhpMyAdmin_Ver}" "${PhpMyAdmin_Destination}" || exit 1
    \cp "${cur_dir}/conf/config.inc.php" "${PhpMyAdmin_Destination}/config.inc.php" || exit 1
    if command -v openssl >/dev/null 2>&1; then
        PhpMyAdmin_Secret=$(openssl rand -hex 16)
    else
        PhpMyAdmin_Secret="LNMP$(date +%s%N)${RANDOM}${RANDOM}${RANDOM}"
        PhpMyAdmin_Secret="${PhpMyAdmin_Secret:0:32}"
    fi
    sed -i "s/LNMPORG/${PhpMyAdmin_Secret}/g" "${PhpMyAdmin_Destination}/config.inc.php" || exit 1
    mkdir -p "${PhpMyAdmin_Destination}/upload" "${PhpMyAdmin_Destination}/save" || exit 1
    printf '%s\n' "${PhpMyAdmin_Version}" > "${PhpMyAdmin_Destination}/.lnmp-version"
    find "${PhpMyAdmin_Destination}" -type d -exec chmod 755 {} + || exit 1
    find "${PhpMyAdmin_Destination}" -type f -exec chmod 644 {} + || exit 1

    if id -u www >/dev/null 2>&1; then
        chown -R www:www "${PhpMyAdmin_Destination}"
    else
        Echo_Yellow "User www does not exist; phpMyAdmin files remain owned by root."
    fi
    if [ ! -x /usr/local/php/bin/php ] && ! command -v php >/dev/null 2>&1; then
        Echo_Yellow "PHP is not installed; phpMyAdmin is deployed but cannot run yet."
    fi

    Echo_Green "phpMyAdmin ${PhpMyAdmin_Version} installed to ${PhpMyAdmin_Destination}"
}

DB_Dependent()
{
    if [ "$PM" = "yum" ]; then
        yum -y remove mysql-server mysql mysql-libs mariadb-server mariadb mariadb-libs
        rpm -qa|grep mysql
        if [ $? -ne 0 ]; then
            rpm -e mysql mysql-libs --nodeps
            rpm -e mariadb mariadb-libs --nodeps
        fi
        for packages in make cmake gcc gcc-c++ gcc-g77 flex bison wget zlib zlib-devel openssl openssl-devel ncurses ncurses-devel libaio-devel rpcgen libtirpc-devel patch cyrus-sasl-devel pkg-config pcre-devel libxml2-devel hostname ncurses-libs numactl-devel libxcrypt gnutls-devel initscripts libxcrypt-compat perl xz gzip;
        do yum -y install $packages; done
        if echo "${CentOS_Version}" | grep -Eqi "^8" || echo "${RHEL_Version}" | grep -Eqi "^8" || echo "${Rocky_Version}" | grep -Eqi "^8" || echo "${Alma_Version}" | grep -Eqi "^8"; then
            Check_PowerTools
            dnf --enablerepo=${repo_id} install rpcgen -y
            dnf install libarchive -y

            dnf install gcc-toolset-10 -y
        fi

        if [ "${DISTRO}" = "Oracle" ] && echo "${Oracle_Version}" | grep -Eqi "^8"; then
            Check_Codeready
            dnf --enablerepo=${repo_id} install rpcgen re2c -y
            dnf install libarchive -y
        fi

        if [ "${DISTRO}" = "Oracle" ] && echo "${Oracle_Version}" | grep -Eqi "^9"; then
            Check_Codeready
            dnf --enablerepo=${repo_id} install libtirpc-devel -y
            if [[ "${Bin}" != "y" && "${DBSelect}" = "5" ]]; then
                dnf install gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils gcc-toolset-12-annobin-annocheck gcc-toolset-12-annobin-plugin-gcc -y
            fi
        fi

        if [ "${DISTRO}" = "Fedora" ] || echo "${CentOS_Version}" | grep -Eqi "^9" || echo "${Alma_Version}" | grep -Eqi "^9" || echo "${Rocky_Version}" | grep -Eqi "^9"; then
            dnf install chkconfig -y
        fi

        if echo "${CentOS_Version}" | grep -Eqi "^9" || echo "${Alma_Version}" | grep -Eqi "^9" || echo "${Rocky_Version}" | grep -Eqi "^9"; then
            dnf --enablerepo=crb install libtirpc-devel libxcrypt-compat -y
            if [[ "${Bin}" != "y" && "${DBSelect}" = "5" ]]; then
                dnf install gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils gcc-toolset-12-annobin-annocheck gcc-toolset-12-annobin-plugin-gcc -y
            fi
        fi

        if [ -s /usr/lib64/libtinfo.so.6 ]; then
            ln -sf /usr/lib64/libtinfo.so.6 /usr/lib64/libtinfo.so.5
        elif [ -s /usr/lib/libtinfo.so.6 ]; then
            ln -sf /usr/lib/libtinfo.so.6 /usr/lib/libtinfo.so.5
        fi

        if [ -s /usr/lib64/libncurses.so.6 ]; then
            ln -sf /usr/lib64/libncurses.so.6 /usr/lib64/libncurses.so.5
        elif [ -s /usr/lib/libncurses.so.6 ]; then
            ln -sf /usr/lib/libncurses.so.6 /usr/lib/libncurses.so.5
        fi
    elif [ "$PM" = "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
        for removepackages in mysql-client mysql-server mysql-common mysql-server-core-5.5 mysql-client-5.5 mariadb-client mariadb-server mariadb-common;
        do apt-get purge -y $removepackages; done
        dpkg -l |grep mysql
        dpkg -P mysql-server mysql-common libmysqlclient15off libmysqlclient15-dev
        dpkg -P mariadb-client mariadb-server mariadb-common
        for packages in debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf automake wget openssl libssl-dev zlib1g zlib1g-dev libncurses5 libncurses5-dev bison libaio-dev libtirpc-dev libsasl2-dev pkg-config libpcre2-dev libxml2-dev libtinfo-dev libnuma-dev gnutls-dev xz-utils gzip;
        do apt-get --no-install-recommends install -y $packages; done
    fi
}

Install_Database()
{
    echo "============================check files=================================="
    cd ${cur_dir}/src
    if [[ "${DBSelect}" =~ ^(1|2|3|4|5|11)$ ]]; then
        if [[ "${Bin}" = "y" && "${DBSelect}" =~ ^[2-4]$ ]]; then
            Mysql_Ver_Short=$(echo ${Mysql_Ver} | sed 's/mysql-//' | cut -d. -f1-2)
            Download_Files https://cdn.mysql.com/Downloads/MySQL-${Mysql_Ver_Short}/${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz ${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz
            [[ $? -ne 0 ]] && Download_Files https://cdn.mysql.com/archives/mysql-${Mysql_Ver_Short}/${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz ${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz
            if [ ! -s ${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz ]; then
                Echo_Red "Error! Unable to download MySQL ${Mysql_Ver_Short} Generic Binaries, please download it to src directory manually."
                sleep 5
                exit 1
            fi
        elif [[ "${Bin}" = "y" && "${DBSelect}" = "5" ]]; then
            [[ "${DB_ARCH}" = "aarch64" ]] && mysql8_glibc_ver="2.17" || mysql8_glibc_ver="2.12"
            Download_Files https://cdn.mysql.com/Downloads/MySQL-8.0/${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz ${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz
            [[ $? -ne 0 ]] && Download_Files https://cdn.mysql.com/archives/mysql-8.0/${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz ${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz
            if [ ! -s ${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz ]; then
                Echo_Red "Error! Unable to download MySQL 8.0 Generic Binaries, please download it to src directory manually."
                sleep 5
                exit 1
            fi
        elif [[ "${Bin}" = "y" && "${DBSelect}" = "11" ]]; then
            Download_Files https://cdn.mysql.com/Downloads/MySQL-8.4/${Mysql_Ver}-linux-glibc2.17-${DB_ARCH}.tar.xz ${Mysql_Ver}-linux-glibc2.17-${DB_ARCH}.tar.xz
            [[ $? -ne 0 ]] && Download_Files https://cdn.mysql.com/archives/mysql-8.4/${Mysql_Ver}-linux-glibc2.17-${DB_ARCH}.tar.xz ${Mysql_Ver}-linux-glibc2.17-${DB_ARCH}.tar.xz
            if [ ! -s ${Mysql_Ver}-linux-glibc2.17-${DB_ARCH}.tar.xz ]; then
                Echo_Red "Error! Unable to download MySQL 8.4 Generic Binaries, please download it to src directory manually."
                sleep 5
                exit 1
            fi
        else
            Download_Files ${Download_Mirror}/datebase/mysql/${Mysql_Ver}.tar.gz ${Mysql_Ver}.tar.gz
            if [ ! -s ${Mysql_Ver}.tar.gz ]; then
                Echo_Red "Error! Unable to download MySQL source code, please download it to src directory manually."
                sleep 5
                exit 1
            fi
        fi
    elif [[ "${DBSelect}" =~ ^(6|7|8|9|10|12|13)$ ]]; then
        Mariadb_Version=$(echo ${Mariadb_Ver} | cut -d- -f2)
        if [ "${Bin}" = "y" ]; then
            MariaDB_FileName="${Mariadb_Ver}-linux-systemd-${DB_ARCH}"
        else
            MariaDB_FileName="${Mariadb_Ver}"
        fi
        Download_Files https://downloads.mariadb.org/rest-api/mariadb/${Mariadb_Version}/${MariaDB_FileName}.tar.gz ${MariaDB_FileName}.tar.gz
        if [ ! -s ${MariaDB_FileName}.tar.gz ]; then
            Echo_Red "Error! Unable to download MariaDB, please download it to src directory manually."
            sleep 5
            exit 1
        fi
    fi
    echo "============================check files=================================="

    Echo_Blue "Install dependent packages..."
    Get_Dist_Version
    Modify_Source
    DB_Dependent
    Check_Openssl
    if [ "${DBSelect}" = "1" ]; then
        Install_MySQL_51
    elif [ "${DBSelect}" = "2" ]; then
        Install_MySQL_55
    elif [ "${DBSelect}" = "3" ]; then
        Install_MySQL_56
    elif [ "${DBSelect}" = "4" ]; then
        Install_MySQL_57
    elif [ "${DBSelect}" = "5" ]; then
        Install_MySQL_80
    elif [ "${DBSelect}" = "6" ]; then
        Install_MariaDB_5
    elif [ "${DBSelect}" = "7" ]; then
        Install_MariaDB_104
    elif [ "${DBSelect}" = "8" ]; then
        Install_MariaDB_105
    elif [ "${DBSelect}" = "9" ]; then
        Install_MariaDB_106
    elif [ "${DBSelect}" = "10" ]; then
        Install_MariaDB_1011
    elif [ "${DBSelect}" = "11" ]; then
        Install_MySQL_84
    elif [ "${DBSelect}" = "12" ]; then
        Install_MariaDB_114
    elif [ "${DBSelect}" = "13" ]; then
        Install_MariaDB_118
    fi
    TempMycnf_Clean

    if [[ "${DBSelect}" =~ ^(6|7|8|9|10|12|13)$ ]]; then
        StartUp mariadb
        StartOrStop start mariadb
    elif [[ "${DBSelect}" =~ ^(1|2|3|4|5|11)$ ]]; then
        StartUp mysql
        StartOrStop start mysql
    fi

    Clean_DB_Src_Dir
    Check_DB_Files
    if [[ "${isDB}" = "ok" ]]; then
        if [[ "${DBSelect}" =~ ^(1|2|3|4|5|11)$ ]]; then
            Echo_Green "MySQL root password: ${DB_Root_Password}"
            Echo_Green "Install ${Mysql_Ver} completed! enjoy it."
        elif [[ "${DBSelect}" =~ ^(6|7|8|9|10|12|13)$ ]]; then
            Echo_Green "MariaDB root password: ${DB_Root_Password}"
            Echo_Green "Install ${Mariadb_Ver} completed! enjoy it."
        fi
    fi
}

Install_Only_Database()
{
    clear
    echo "+-----------------------------------------------------------------------+"
    echo "|      Install MySQL/MariaDB database for LNMP, Written by Licess       |"
    echo "+-----------------------------------------------------------------------+"
    echo "|               A tool to install MySQL/MariaDB for LNMP                |"
    echo "+-----------------------------------------------------------------------+"
    echo "|           For more information please visit https://lnmp.org          |"
    echo "+-----------------------------------------------------------------------+"

    Get_Dist_Name
    Check_DB
    if [ "${DB_Name}" != "None" ]; then
        echo "You have install ${DB_Name}!"
        exit 1
    fi

    Database_Selection
    if [ "${DBSelect}" = "0" ]; then
        echo "DO NOT Install MySQL or MariaDB."
        exit 1
    fi
    Echo_Red "The script will REMOVE MySQL/MariaDB installed via yum or apt-get and it's databases!!!"
    Press_Install
    Run_Logged /root/install_database.log Install_Database
}
