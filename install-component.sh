#!/usr/bin/env bash

set -u

script_dir=$(cd "$(dirname "$0")" && pwd)

usage()
{
    cat <<'EOF'
Usage: ./install-component.sh <mysql|php|nginx> <version> [options]
       ./install-component.sh lnmp [--dry-run]
       ./install-component.sh status

Examples:
  ./install-component.sh nginx 1.28.0
  ./install-component.sh mysql 8.4.8 --binary
  ./install-component.sh php 8.3.30
  ./install-component.sh lnmp
  ./install-component.sh status
  ./install-component.sh nginx 1.28.0 --yes --dry-run

Options:
  -y, --yes       Skip the final key-press confirmation.
  --binary        Install a MySQL generic binary package when supported.
  --source        Compile MySQL from source.
  --dry-run       Print the resolved installation settings without installing.
  -h, --help      Show this help message.

The lnmp target only installs the management command; it installs no services.
The status target reports installed component versions; it changes nothing.
PHP is installed as the main PHP-FPM service and does not require MySQL or Nginx.
PHP 5.2 is the exception and still requires MySQL because of its legacy build options.
Supported MySQL series: 5.1, 5.5, 5.6, 5.7, 8.0, 8.4.
Supported PHP series:   5.2-5.6, 7.0-7.4, 8.0-8.5.
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

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ $# -ge 1 ] || { usage >&2; exit 1; }

component=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
shift

version=
if [ "$component" != lnmp ] && [ "$component" != status ]; then
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
    *)
        die "Unsupported component '$component'. Use lnmp, status, mysql, php, or nginx."
        ;;
esac

echo "Component: $component"
if [ -n "$version" ]; then
    echo "Version:   $version"
fi
if [ -n "$selector" ]; then
    echo "Selector:  $selector"
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

export "$override_name=$version"
[ "$auto_install" = y ] && export LNMP_Auto=y
[ -n "$binary_mode" ] && export Bin="$binary_mode"

case "$component" in
    mysql) export DBSelect="$selector" ;;
    php) export PHPSelect="$selector" ;;
esac

cd "$script_dir" || exit 1
exec ./install.sh "$installer_action"
