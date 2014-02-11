#!/bin/bash
###############################################################################
#                                                                             #
#                                                                             #
###############################################################################

PH_NGINX_INSTALL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PH_INSTALL_DIR="$( cd "${PH_NGINX_INSTALL_DIR}" && cd ../../ && pwd )"
. ${PH_INSTALL_DIR}/bootstrap.sh

function ph_module_install_nginx()
{
    [ $# -gt 1 ] && NGINX_INTERACTIVE=false || NGINX_INTERACTIVE=true

    for arg in "$@"; do
        case $arg in
        --version=*)
            NGINX_VERSION_STRING="${arg#*=}"
            shift
            ;;

        --prefix=*)
            NGINX_PREFIX="${arg#*=}"
            shift
            ;;

        --user=*)
            NGINX_USER="${arg#*=}"
            shift
            ;;

        --group=*)
            NGINX_GROUP="${arg#*=}"
            shift
            ;;

        --overwrite-symlinks=*)
            NGINX_OVERWRITE_SYMLINKS="${arg#*=}"
            if [[ "yes" == "${NGINX_OVERWRITE_SYMLINKS}" ]]; then
                NGINX_OVERWRITE_SYMLINKS=true
            else
                NGINX_OVERWRITE_SYMLINKS=false
            fi
            shift
            ;;

        ## Ignore legacy arguments
        install|nginx)
            NGINX_INTERACTIVE=true
            break
            ;;

        *)
            echo "Unknown option $arg"
            return 1
            ;;
        esac
    done

    if ${NGINX_INTERACTIVE}; then
        if ph_is_installed nginx ; then
            echo "nginx is already installed!"
            ls -l `which nginx` | awk '{print $9 $10 $11}'
            nginx -v

            if ! ph_ask_yesno "Do you wish to continue with the nginx installation?"; then
                return 1
            fi
        fi

        read -p "Specify nginx version [1.4.5]: " NGINX_VERSION_STRING
        [ -z ${NGINX_VERSION_STRING} ] && NGINX_VERSION_STRING="1.4.5"
    fi

    NGINX_VERSION_INTEGER=`echo ${NGINX_VERSION_STRING} | tr -d '.' | cut -c1-3`
    NGINX_VERSION_INTEGER_FULL=`echo ${NGINX_VERSION_STRING} | tr -d '.'`

    NGINX_VERSION_MAJOR=`echo ${NGINX_VERSION_STRING} | cut -d. -f1`
    NGINX_VERSION_MINOR=`echo ${NGINX_VERSION_STRING} | cut -d. -f2`
    NGINX_VERSION_RELEASE=`echo ${NGINX_VERSION_STRING} | cut -d. -f3`

    if ${NGINX_INTERACTIVE}; then
        read -p "Specify installation directory [/usr/local/nginx-${NGINX_VERSION_MAJOR}.${NGINX_VERSION_MINOR}]: " NGINX_PREFIX
        [ -z ${NGINX_PREFIX} ] && NGINX_PREFIX="/usr/local/nginx-${NGINX_VERSION_MAJOR}.${NGINX_VERSION_MINOR}"

        case "${PH_OS}" in \
        "linux")
            SUGGESTED_USER="www-data"
            ;;

        "mac")
            SUGGESTED_USER="_www"
            ;;
        esac

        read -p "Specify nginx user [${SUGGESTED_USER}]: " NGINX_USER
        [ -z ${NGINX_USER} ] && NGINX_USER="${SUGGESTED_USER}"

        read -p "Specify nginx group [${SUGGESTED_USER}]: " NGINX_GROUP
        [ -z ${NGINX_GROUP} ] && NGINX_GROUP="${SUGGESTED_USER}"
    fi

    if ${NGINX_INTERACTIVE}; then
        if ph_ask_yesno "Should I create the user and group for you?"; then
            ph_creategroup ${NGINX_GROUP}
            ph_createuser ${NGINX_USER}
            ph_assigngroup ${NGINX_GROUP} ${NGINX_USER}
        fi
    else
        ph_creategroup ${NGINX_GROUP}
        ph_createuser ${NGINX_USER}
        ph_assigngroup ${NGINX_GROUP} ${NGINX_USER}
    fi

    ph_install_packages\
        gcc\
        make\
        openssl\
        pcre\
        wget\
        zlib

    if ${NGINX_INTERACTIVE}; then
        if ph_ask_yesno "Overwrite existing symlinks in /usr/local?"; then
            NGINX_OVERWRITE_SYMLINKS=true
        else
            NGINX_OVERWRITE_SYMLINKS=false
        fi
    fi

    ph_mkdirs \
        /usr/local/src \
        /etc/nginx-${NGINX_VERSION_STRING} \
        /var/log/nginx-${NGINX_VERSION_STRING} \
        /etc/nginx-${NGINX_VERSION_STRING}/global \
        /etc/nginx-${NGINX_VERSION_STRING}/sites-available \
        /etc/nginx-${NGINX_VERSION_STRING}/sites-enabled \
        /var/www/localhost/public

    ph_cd_archive tar xzf nginx-${NGINX_VERSION_STRING} .tar.gz \
        http://nginx.org/download/nginx-${NGINX_VERSION_STRING}.tar.gz

    CONFIGURE_ARGS=("--prefix=${NGINX_PREFIX}"
        "--pid-path=${NGINX_PREFIX}/logs/nginx.pid"
        "--error-log-path=${NGINX_PREFIX}/logs/error.log"
        "--http-log-path=${NGINX_PREFIX}/logs/access.log"
        "--conf-path=/etc/nginx-${NGINX_VERSION_STRING}/nginx.conf"
        "--with-pcre"
        "--with-http_ssl_module"
        "--with-http_realip_module");

    if [[ "${PH_PACKAGE_MANAGER}" == "brew" ]]; then
        # Add homebrew include directories
        CONFIGURE_ARGS=(${CONFIGURE_ARGS[@]}
            "--with-cc-opt=-I/usr/local/include"
            "--with-ld-opt=-L/usr/local/lib")
    fi

    ph_autobuild "`pwd`" ${CONFIGURE_ARGS[@]} || return 1

    ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/nginx.conf /etc/nginx-${NGINX_VERSION_STRING}/nginx.conf\
        "##NGINX_USER##" "${NGINX_USER}"
    ph_search_and_replace "##NGINX_GROUP##" "${NGINX_GROUP}" /etc/nginx-${NGINX_VERSION_STRING}/nginx.conf

    cp ${PH_INSTALL_DIR}/modules/nginx/restrictions.conf /etc/nginx-${NGINX_VERSION_STRING}/global/restrictions.conf
    cp ${PH_INSTALL_DIR}/modules/nginx/localhost.conf /etc/nginx-${NGINX_VERSION_STRING}/sites-available/localhost
    cp ${PH_INSTALL_DIR}/modules/nginx/000-catchall.conf /etc/nginx-${NGINX_VERSION_STRING}/sites-available/000-catchall

    ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/index.html /var/www/localhost/public/index.html\
        "##NGINX_VERSION_STRING##" "${NGINX_VERSION_STRING}"

    # Patch nginx config files for windows
    if [ "${PH_OS}" == "windows" ]; then
        ph_search_and_replace "^user" "#user" /etc/nginx-${NGINX_VERSION_STRING}/nginx.conf
        ph_search_and_replace "worker_connections  1024" "worker_connections  64" /etc/nginx-${NGINX_VERSION_STRING}/nginx.conf
    fi

    ph_symlink /etc/nginx-${NGINX_VERSION_STRING} /etc/nginx ${NGINX_OVERWRITE_SYMLINKS}
    ph_symlink ${NGINX_PREFIX} /usr/local/nginx ${NGINX_OVERWRITE_SYMLINKS}
    ph_symlink ${NGINX_PREFIX}/logs /var/log/nginx ${NGINX_OVERWRITE_SYMLINKS}
    ph_symlink ${NGINX_PREFIX}/sbin/nginx /usr/local/bin/nginx ${NGINX_OVERWRITE_SYMLINKS}
    ph_symlink /etc/nginx-${NGINX_VERSION_STRING}/sites-available/localhost /etc/nginx-${NGINX_VERSION_STRING}/sites-enabled/localhost ${NGINX_OVERWRITE_SYMLINKS}
    ph_symlink /etc/nginx-${NGINX_VERSION_STRING}/sites-available/000-catchall /etc/nginx-${NGINX_VERSION_STRING}/sites-enabled/000-catchall ${NGINX_OVERWRITE_SYMLINKS}

    case "${PH_OS}" in \
    "linux")
        case "${PH_OS_FLAVOUR}" in \
        "arch")
            ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/nginx.in /etc/rc.d/nginx-${NGINX_VERSION_STRING} \
                "##NGINX_PREFIX##" "${NGINX_PREFIX}"

            /etc/rc.d/nginx-${NGINX_VERSION_STRING} start
            ;;

        "suse")
            ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/nginx.in /etc/init.d/nginx-${NGINX_VERSION_STRING} \
                "##NGINX_PREFIX##" "${NGINX_PREFIX}"

            chkconfig nginx-${NGINX_VERSION_STRING} on
            /etc/init.d/nginx-${NGINX_VERSION_STRING} start
            ;;

        *)
            ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/nginx.in /etc/init.d/nginx-${NGINX_VERSION_STRING} \
                "##NGINX_PREFIX##" "${NGINX_PREFIX}"

            /etc/init.d/nginx-${NGINX_VERSION_STRING} start
            update-rc.d nginx-${NGINX_VERSION_STRING} defaults
            ;;
        esac
        ;;

    "mac")
        ph_cp_inject ${PH_INSTALL_DIR}/modules/nginx/org.nginx.nginx.plist /Library/LaunchAgents/org.nginx.nginx.plist \
            "##NGINX_VERSION_STRING##" "${NGINX_VERSION_STRING}"

        chown root:wheel /Library/LaunchAgents/org.nginx.nginx.plist
        launchctl load -w /Library/LaunchAgents/org.nginx.nginx.plist
        ;;

    *)
        echo "nginx startup script not implemented for this OS... starting manually"
        ${NGINX_PREFIX}/sbin/nginx
        ;;
    esac

    echo -n "Deleting source files... "
    rm -rf /usr/local/src/nginx-${NGINX_VERSION_STRING}

    echo "Complete."
    return 0
}

ph_module_install_nginx $@ || exit 0
