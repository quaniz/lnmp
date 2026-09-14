#!/usr/bin/env bash

set -u

script_dir=$(cd "$(dirname "$0")" && pwd)

usage()
{
    cat <<'EOF'
Usage: ./install-component.sh <mysql|php|nginx|phpmyadmin> <version> [options]
       ./install-component.sh acme <email> [options]
       ./install-component.sh lnmp [--dry-run]
       ./install-component.sh status
       ./install-component.sh sources

Examples:
  ./install-component.sh nginx 1.28.0
  ./install-component.sh mysql 8.4.8 --binary
  ./install-component.sh php 8.3.30
  ./install-component.sh phpmyadmin 5.2.3
  ./install-component.sh acme admin@example.com
  ./install-component.sh lnmp
  ./install-component.sh status
  ./install-component.sh sources
  ./install-component.sh nginx 1.28.0 --yes --dry-run

Options:
  -y, --yes       Skip the final key-press confirmation.
  --binary        Install a MySQL generic binary package when supported.
  --source        Compile MySQL from source.
  --email EMAIL   ACME account email (alternative to the positional email).
  --dry-run       Print the resolved installation settings without installing.
  -h, --help      Show this help message.

The lnmp target only installs the management command; it installs no services.
The status target reports installed component versions, including phpMyAdmin; it changes nothing.
The sources target lists locally cached software archives in src; it changes nothing.
PHP is installed as the main PHP-FPM service and does not require MySQL or Nginx.
PHP 5.2 is the exception and still requires MySQL because of its legacy build options.
phpMyAdmin only deploys its web files; it does not install PHP, MySQL, or Nginx.
ACME only installs acme.sh; it does not issue a certificate or install server services.
Supported MySQL series: 5.1, 5.5, 5.6, 5.7, 8.0, 8.4.
Supported PHP series:   5.2-5.6, 7.0-7.4, 8.0-8.5.
phpMyAdmin versions use the x.y.z format, for example 5.2.3.
EOF
}

die()
{
    echo "Error: $*" >&2
    exit 1
}

print_binary_version()
{
    local Label="$1"
    local Binary="$2"
    shift 2
    local Version_Output

    if [ ! -x "${Binary}" ]; then
        printf '%-9s %s\n' "${Label}:" 'not installed'
        return 0
    fi
    if Version_Output=$("${Binary}" "$@" 2>&1) && [ -n "${Version_Output}" ]; then
        printf '%-9s %s\n' "${Label}:" "$(printf '%s\n' "${Version_Output}" | head -n 1)"
    else
        printf '%-9s %s\n' "${Label}:" "installed (${Binary}), version unavailable"
    fi
}

print_source_inventory()
{
    local Archive
    local Archive_Name
    local Archive_Size
    local Software
    local Source_Dir="${script_dir}/src"
    local Stem
    local Version
    local Found=0

    if [ ! -d "${Source_Dir}" ]; then
        echo "Source cache directory not found: ${Source_Dir}"
        return 1
    fi

    printf '%-18s %-14s %-9s %s\n' 'SOFTWARE' 'VERSION' 'SIZE' 'FILE'
    printf '%-18s %-14s %-9s %s\n' '------------------' '--------------' '---------' '----'
    while IFS= read -r Archive; do
        [ -n "${Archive}" ] || continue
        Found=1
        Archive_Name=${Archive##*/}
        Stem=${Archive_Name}
        Stem=${Stem%.tar.gz}
        Stem=${Stem%.tar.bz2}
        Stem=${Stem%.tar.xz}
        Stem=${Stem%.tgz}
        Stem=${Stem%.zip}
        Stem=${Stem%.phar}
        Stem=${Stem%.rpm}
        Version=$(printf '%s\n' "${Stem}" | grep -Eo '[0-9]+([._][0-9]+){1,3}[A-Za-z]*' | head -n 1)
        Version=${Version//_/.}
        [ -n "${Version}" ] || Version='unknown'

        case "${Stem}" in
            phpMyAdmin-*) Software='phpMyAdmin' ;;
            mysql-*) Software='MySQL' ;;
            mariadb-*) Software='MariaDB' ;;
            php-*) Software='PHP' ;;
            nginx-*) Software='Nginx' ;;
            acme.sh-*|latest) Software='acme.sh'; [ "${Version}" = 'unknown' ] && Version='latest' ;;
            composer*) Software='Composer'; [ "${Version}" = 'unknown' ] && Version='current' ;;
            boost_*) Software='Boost' ;;
            icu4c-*) Software='ICU' ;;
            p) Software='PHP Prober' ;;
            *)
                if [ "${Version}" != 'unknown' ]; then
                    Software=${Stem%%-${Version}*}
                    [ "${Software}" = "${Stem}" ] && Software=${Stem%%_${Version//./_}*}
                else
                    Software=${Stem}
                fi
                ;;
        esac

        if [ -s "${Archive}" ]; then
            Archive_Size=$(du -h "${Archive}" | awk '{print $1}')
        else
            Archive_Size='EMPTY'
        fi
        printf '%-18s %-14s %-9s %s\n' "${Software}" "${Version}" "${Archive_Size}" "${Archive_Name}"
    done < <(find "${Source_Dir}" -maxdepth 1 -type f \( \
        -name '*.tar.gz' -o -name '*.tar.bz2' -o -name '*.tar.xz' -o \
        -name '*.tgz' -o -name '*.zip' -o -name '*.phar' -o -name '*.rpm' \
        \) -print | LC_ALL=C sort)

    if [ ${Found} -eq 0 ]; then
        echo '(no local software archives found)'
    fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ $# -ge 1 ] || { usage >&2; exit 1; }

component=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
shift
[ "$component" = 'acme.sh' ] && component=acme

version=
acme_email=${LNMP_ACME_EMAIL:-}
if [ "$component" = acme ]; then
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
        acme_email=$1
        shift
    fi
elif [ "$component" != lnmp ] && [ "$component" != status ] && [ "$component" != sources ] && [ "$component" != src ]; then
    [ $# -ge 1 ] || die "A version is required for $component."
    version=$1
    shift
fi

auto_install=n
dry_run=n
binary_mode=

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            auto_install=y
            ;;
        --binary)
            [ -z "$binary_mode" ] || die "--binary and --source cannot be used together."
            binary_mode=y
            ;;
        --source)
            [ -z "$binary_mode" ] || die "--binary and --source cannot be used together."
            binary_mode=n
            ;;
        --email)
            [ "$component" = acme ] || die "--email only applies to ACME."
            [ $# -ge 2 ] || die "--email requires an email address."
            acme_email=$2
            shift
            ;;
        --dry-run)
            dry_run=y
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
    shift
done

if [ -n "$version" ]; then
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "Version must use the x.y.z format, for example 8.4.8."
fi
if [ "$component" = acme ]; then
    [ -n "$acme_email" ] || die "An account email is required, for example: ./install-component.sh acme admin@example.com"
    [[ "$acme_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]] || \
        die "Invalid ACME account email: $acme_email"
fi

selector=
installer_action=
override_name=

case "$component" in
    lnmp)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        ;;
    status)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        [ "$auto_install" = n ] || die "--yes does not apply to status."
        [ "$dry_run" = n ] || die "--dry-run does not apply to status."
        ;;
    sources|src)
        component=sources
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        [ "$auto_install" = n ] || die "--yes does not apply to sources."
        [ "$dry_run" = n ] || die "--dry-run does not apply to sources."
        ;;
    mysql)
        case "$version" in
            5.1.*) selector=1 ;;
            5.5.*) selector=2 ;;
            5.6.*) selector=3 ;;
            5.7.*) selector=4 ;;
            8.0.*) selector=5 ;;
            8.4.*) selector=11 ;;
            *) die "Unsupported MySQL series: $version" ;;
        esac
        if [ "$selector" = 1 ] && [ "$binary_mode" = y ]; then
            die "MySQL 5.1 does not support --binary in this project."
        fi
        installer_action=db
        override_name=LNMP_MYSQL_VERSION_OVERRIDE
        ;;
    php)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        case "$version" in
            5.2.17) selector=1 ;;
            5.2.*) die "PHP 5.2 installation is fixed to 5.2.17 by the bundled FPM patch." ;;
            5.3.*) selector=2 ;;
            5.4.*) selector=3 ;;
            5.5.*) selector=4 ;;
            5.6.*) selector=5 ;;
            7.0.*) selector=6 ;;
            7.1.*) selector=7 ;;
            7.2.*) selector=8 ;;
            7.3.*) selector=9 ;;
            7.4.*) selector=10 ;;
            8.0.*) selector=11 ;;
            8.1.*) selector=12 ;;
            8.2.*) selector=13 ;;
            8.3.*) selector=14 ;;
            8.4.*) selector=15 ;;
            8.5.*) selector=16 ;;
            *) die "Unsupported PHP series: $version" ;;
        esac
        installer_action=php
        override_name=LNMP_PHP_VERSION_OVERRIDE
        ;;
    nginx)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        installer_action=nginx
        override_name=LNMP_NGINX_VERSION_OVERRIDE
        ;;
    phpmyadmin)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        installer_action=phpmyadmin
        override_name=LNMP_PHPMYADMIN_VERSION_OVERRIDE
        ;;
    acme)
        [ -z "$binary_mode" ] || die "--binary/--source only apply to MySQL."
        installer_action=acme
        ;;
    *)
        die "Unsupported component '$component'. Use lnmp, status, sources, mysql, php, nginx, phpmyadmin, or acme."
        ;;
esac

echo "Component: $component"
if [ -n "$version" ]; then
    echo "Version:   $version"
fi
if [ -n "$selector" ]; then
    echo "Selector:  $selector"
fi
if [ "$component" = acme ]; then
    echo "Email:     $acme_email"
fi
if [ "$component" = mysql ]; then
    case "$binary_mode" in
        y) echo "Build mode: generic binary" ;;
        n) echo "Build mode: source" ;;
        *) echo "Build mode: ask/default" ;;
    esac
fi

if [ "$dry_run" = y ]; then
    echo "Dry run: installation was not started."
    exit 0
fi

if [ "$component" = sources ]; then
    print_source_inventory
    exit $?
fi

if [ "$component" = status ]; then
    if [ -x /bin/lnmp ]; then
        echo "lnmp:    installed (/bin/lnmp)"
    elif [ -e /bin/lnmp ]; then
        echo "lnmp:    installed but not executable (/bin/lnmp)"
    else
        echo "lnmp:    not installed"
    fi

    if [ -x /usr/local/mysql/bin/mysql ]; then
        print_binary_version mysql /usr/local/mysql/bin/mysql --version
    elif [ -x /usr/local/mariadb/bin/mysql ]; then
        print_binary_version mariadb /usr/local/mariadb/bin/mysql --version
    else
        echo "mysql:   not installed"
    fi

    print_binary_version php /usr/local/php/bin/php -r 'echo PHP_VERSION;'
    print_binary_version nginx /usr/local/nginx/sbin/nginx -v
    if [ -x /usr/local/acme.sh/acme.sh ]; then
        Acme_Version=$(/usr/local/acme.sh/acme.sh --version 2>&1 | tail -n 1)
        printf '%-9s %s\n' 'acme.sh:' "${Acme_Version:-installed (/usr/local/acme.sh/acme.sh)}"
    else
        printf '%-9s %s\n' 'acme.sh:' 'not installed'
    fi
    if [ -s "${script_dir}/lnmp.conf" ]; then
        Default_Website_Dir=$(awk -F"'" '/^Default_Website_Dir=/ {print $2; exit}' "${script_dir}/lnmp.conf")
        if [ -s "${Default_Website_Dir}/phpmyadmin/.lnmp-version" ]; then
            printf '%-9s %s\n' 'phpMyAdmin:' "$(head -n 1 "${Default_Website_Dir}/phpmyadmin/.lnmp-version")"
        elif [ -d "${Default_Website_Dir}/phpmyadmin" ]; then
            printf '%-9s %s\n' 'phpMyAdmin:' "installed (${Default_Website_Dir}/phpmyadmin), version unavailable"
        else
            printf '%-9s %s\n' 'phpMyAdmin:' 'not installed'
        fi
    fi
    exit 0
fi

[ "$(id -u)" = 0 ] || die "You must be root to install LNMP components."

if [ "$component" = lnmp ]; then
    [ -s "$script_dir/conf/lnmp" ] || die "Source command not found: $script_dir/conf/lnmp"
    cp "$script_dir/conf/lnmp" /bin/lnmp
    chmod 0755 /bin/lnmp
    echo "Installed lnmp command to /bin/lnmp."
    exit 0
fi

[ -n "$override_name" ] && export "$override_name=$version"
[ "$component" = acme ] && export LNMP_ACME_EMAIL="$acme_email"
[ "$auto_install" = y ] && export LNMP_Auto=y
[ -n "$binary_mode" ] && export Bin="$binary_mode"

case "$component" in
    mysql) export DBSelect="$selector" ;;
    php) export PHPSelect="$selector" ;;
esac

cd "$script_dir" || exit 1
exec ./install.sh "$installer_action"
