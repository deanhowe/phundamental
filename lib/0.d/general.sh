#!/bin/bash

##
# Checks to see if a command ($1) is available
#
# @param  string  Command to check
# @return boolean True if the command exists
#
function ph_is_installed() {
    command -v $1 > /dev/null 2>&1 && return 0 || return 1
}


##
# Ask the user a yes or no question
#
# @param string The question to ask
# @param string Optional default response if user simpy hits enter <y|n>
# @return boolean True if yes, false if no
#
function ph_ask_yesno() {
    local QUESTION="$1"
    local DEFAULT=${2-"y"}
    local REPLY=

    if [ "${DEFAULT}" == "y" ]; then
        QUESTION="${QUESTION} [Y/n]: "
    else
        QUESTION="${QUESTION} [y/N]: "
    fi

    while true; do
        read -p "${QUESTION}" REPLY

        if [ -z ${REPLY} ]; then
            REPLY="${DEFAULT}"
        fi

        if [ "${REPLY}" == "y" ] || [ "${REPLY}" == "Y" ]; then
            return 0
        elif [ "${REPLY}" == "n" ] || [ "${REPLY}" == "N" ]; then
            return 1
        else
            echo 'Please enter y or n!'
        fi
    done
}


##
# Cross-platform wrapper for sed -i
#
# @param string Search pattern
# @param string Replacement pattern
# @param string Path to target file
#
function ph_search_and_replace() {
    local SEARCH=`echo $1 | sed 's#/#\\\/#g'`
    local REPLACE=`echo $2 | sed 's#/#\\\/#g'`
    local TARGET=$3

    [ ! -f "${TARGET}" ] && echo "ph_search_and_replace() failed! ${TARGET} is not a file"

    sed -ie "s/${SEARCH}/${REPLACE}/g" "${TARGET}"

    # OSX fix
    [ -f "${TARGET}e" ] && rm "${TARGET}e"
}


##
# Copy file and execute an inplace string replacement
#
# @param string Path to source file
# @param string Path to target file
# @param string Search pattern
# @param string Replacement pattern
#
ph_cp_inject() {
    local SOURCE=$1
    local TARGET=$2
    local SEARCH=$3
    local REPLACE=$4

    if [ ! -f "${SOURCE}" ]; then
        echo "ph_cp_inject() failed! ${SOURCE} is not a file"
        return 1
    fi

    if ${PH_INTERACTIVE}; then
        local cp_flags='-i'
    fi

    cp ${cp_flags} "${SOURCE}" "${TARGET}" && ph_search_and_replace "${SEARCH}" "${REPLACE}" "${TARGET}"
}


##
# Creates all directories ($@) if they don't already exist
#
# @param list Directories to create
#
function ph_mkdirs() {
    for DIR in $@; do
        [ ! -d $DIR ] && mkdir -p $DIR
    done
}


##
# (Nicely) create a symlink
#
# @param string   Path to source
# @param string   Path to target
# @param boolean  Force symlink creation <true|false>
# @return boolean True if the symlink was created
#
function ph_symlink() {
    local SOURCE="$1"
    local TARGET="$2"
    local FORCE=$3

    if [ -f ${TARGET} ] || [ -d ${TARGET} ] && [ ! -L ${TARGET} ]; then
        echo "ph_symlink(): Real file or directory already exists where you're trying to create a symlink: ${TARGET}"
        rm -ri ${TARGET}

        # Abort symlink creation if user did not delete existing file/directory
        if [ -f ${TARGET} ] || [ -d ${TARGET} ] && [ ! -L ${TARGET} ]; then
            echo "ph_symlink(): Aborting symlink creation..."
            return 1
        fi
    fi

    echo -n "Creating symlink ${TARGET} -> ${SOURCE} ... "

    if ${FORCE} ; then
        ln -sf ${SOURCE} ${TARGET} 2>/dev/null && { echo "success!"; return 0; } || { echo "failed!"; return 1; }
    else
        ln -sn ${SOURCE} ${TARGET} 2>/dev/null && { echo "success!"; return 0; } || { echo "failed!"; return 1; }
    fi
}


##
# (Paranoid) archive download, extract and cd into created directory
#
# @param string     archive command (e.g. tar)
# @param string     args for archive program (e.g. xzf)
# @param string     filename (without extension)
# @param string     file extension (e.g. tar.gz)
# @param string     URI to download original archive
# @param string     Destination directory (default: /usr/local/src)
# @return boolean   True if managed to cd into extracted directory
#
function ph_cd_archive() {
    local ARCHIVE_CMD="$1"
    local CMD_ARGS="$2"
    local ARCHIVE_FILENAME="$3"
    local ARCHIVE_EXTENSION="$4"
    local URI="$5" # Ampersand (&) must be escaped (\&)
    local DESTINATION_DIR=${6-"/usr/local/src"}

    [ ! -d "${DESTINATION_DIR}" ] && mkdir -piv "${DESTINATION_DIR}"

    cd "${DESTINATION_DIR}"

    if [ ! -d "${ARCHIVE_FILENAME}" ]; then
        if [ ! -f "${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}" ]; then
            wget -O "${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}" "${URI}"

            # Ensure file downloaded
            if [ ! -f "${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}" ]; then
                echo "${FUNCNAME}(): Download failed: ${URI}"
                exit 1
            fi
        fi

        # Extract (hopefully)
        if ! ${ARCHIVE_CMD} ${CMD_ARGS} "${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}"; then
            echo "${FUNCNAME}(): ${ARCHIVE_CMD} ${CMD_ARGS} ${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION} failed. Maybe bad download/URI."
            rm -iv ${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}
            exit 1
        fi

        # Cleanup
        echo "${FUNCNAME}(): Source code downloaded and extracted, deleting archive..."
        rm -v "${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION}"

        # Ensure expected directory was actually created
        if [ ! -d "${ARCHIVE_FILENAME}" ]; then
            echo "${FUNCNAME}(): ${ARCHIVE_FILENAME}${ARCHIVE_EXTENSION} did not extract to ${DESTINATION_DIR}/${ARCHIVE_FILENAME}"
            exit 1
        fi
    fi

    # Directory _definately_ exists now
    cd "${ARCHIVE_FILENAME}" && return 0 || return 1
}


##
# Proxy to autotools build process
#
# @param    The directory containing the configure script
# @param    variable amount of options to pass to configure script
# @return boolean True if build completed successfully
#
function ph_autobuild() {
    local BUILD_DIR="$1"
    shift

    # Support variable argument number
    local CONFIGURE_OPTIONS="$@"

    local configure_log="/tmp/${FUNCNAME}.log"

    if [ ! -d "${BUILD_DIR}" ]; then
        echo "${FUNCNAME}(): Cannot compile in directory that does not exist: ${BUILD_DIR}"
        exit 1
    fi

    echo "${FUNCNAME}(): Preparing to compile ${BUILD_DIR}"

    cd "${BUILD_DIR}"

    if [ ! -x configure ]; then
        echo "${FUNCNAME}(): Cannot compile if ${BUILD_DIR}/configure is not an executable script."
        exit 1
    fi

    echo -n 'make clean   '
    local odd=true
    make clean 2>&1 | while read line; do
        $odd && { odd=false; echo -en "\b\b. "; } || { odd=true; echo -en "\b\b ."; }
    done

    # Ensure log file exists and is empty
    cat /dev/null > ${configure_log}

    # Configure silently and write to log file
    echo
    echo -n "./configure ${CONFIGURE_OPTIONS}   "
    odd=true
    ./configure ${CONFIGURE_OPTIONS} 2>&1 | tee -a ${configure_log} | while read line; do
        $odd && { odd=false; echo -en "\b\b. "; } || { odd=true; echo -en "\b\b ."; }
    done

    # Check exit status of ./configure
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo
        echo "${FUNCNAME}(): Failed when running:"
        echo "./configure ${CONFIGURE_OPTIONS}"
        echo
        echo "See ${configure_log} for full details or tail of it below:"
        tail "${configure_log}"
        exit 1
    fi

    echo
    echo -n "make -j ${PH_NUM_THREADS}   "
    odd=true
    make -j ${PH_NUM_THREADS} 2>&1 | tee -a ${configure_log} | while read line; do
        $odd && { odd=false; echo -en "\b\b. "; } || { odd=true; echo -en "\b\b ."; }
    done

    # Check exit status of make
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo
        echo "${FUNCNAME}(): Failed to compile. See ${configure_log} for full details or tail of it below:"
        tail "${configure_log}"
        exit 1
    fi

    echo
    echo -n 'make install   '
    odd=true
    make install 2>&1 | tee -a ${configure_log} | while read line; do
        $odd && { odd=false; echo -en "\b\b. "; } || { odd=true; echo -en "\b\b ."; }
    done

    # Check exit status of make install
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo
        echo "${FUNCNAME}(): Failed to make install. See ${configure_log} for full details or tail of it below:"
        tail "${configure_log}"
        exit 1
    fi

    echo
    echo "${FUNCNAME}(): Successfully compiled ${BUILD_DIR}"

    return 0
}


##
# Install a phundamental module
#
# @param string $1 <install|uninstall>
# @param string $2 Module name
#
function ph_module_action() {
    local ACTION=$1
    local MODULE=$2
    local RESULT_MSG='with an unknown status'
    local ACTION_FILE=${PH_INSTALL_DIR}/modules/${MODULE}/${ACTION}.sh

    # Check module directory exists
    if [ ! -d ${PH_INSTALL_DIR}/modules/${MODULE} ]; then
        echo "ph_module_action(): Module '${MODULE}' does not exist!"
        return 1
    fi

    # Check action file is executable
    if [ ! -x ${ACTION_FILE} ]; then
        echo "ph_module_action(): ${MODULE}/${ACTION}.sh is not executable, skipping..."
        return 1
    fi

    . ${ACTION_FILE} && RESULT='successfully' || RESULT='unsuccessfully'
    echo "[phundamental/${MODULE}] ${ACTION} script finished ${RESULT}."

    if [[ "${RESULT}" == "successfully" ]]; then
        return 0
    else
        return 1
    fi
}


##
# Process application arguments to deal with request appropriately
#
# @param string $1 <install|uninstall>
# @param list      An optional list of module names to action.
#
function ph_front_controller() {
    local ACTION=$1

    case $# in \
    0)
        echo "Usage: ${PH_INSTALL_DIR}/<install|uninstall> [<module> [<module> ..]]"
    ;;

    # Action all modules
    1)
        for MODULE in `ls -1 ${PH_INSTALL_DIR}/modules`; do
            echo
            if ph_ask_yesno "[phundamental/installer] Would you like to ${ACTION} ${MODULE}?" "n"; then
                ph_module_action ${ACTION} ${MODULE}
            fi
        done
    ;;

    # Action one or more modules
    *)
        # Ignore first parameter as it's stored in ${ACTION}
        shift

        # Loop through all remaining arguments and assume they're module names
        while (( "$#" )); do
            ph_module_action ${ACTION} $1
            shift
        done
    esac
}
