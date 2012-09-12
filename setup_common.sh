# Originally based off of:
# https://github.com/lowendbox/lowendscript/blob/master/setup-debian.sh

if [ ! -e "/lib/lsb/init-functions" ]; then
    echo "Could not find /lib/lsb/init-functions"
    exit 1
fi
. /lib/lsb/init-functions

function print_info {
    echo -n -e '\e[1;32m'"$1"'\e[0m'
    shift
    while [ -n "$1" ]
    do
       echo -n  -e '\e[32m'" $1"'\e[0m'
       shift
    done
    echo
}

function print_warn {
    echo -n -e '\e[1;31m'"$1"'\e[0m'
    shift
    while [ -n "$1" ]
    do
       echo -n  -e '\e[31m'" $1"'\e[0m'
       shift
    done
    echo
}

function die {
    echo "ERROR: $1" > /dev/null 1>&2
    exit 1
}

function install_pkgs {
   apt-get -q -y install $*
   print_info installed: $*
}

function remove_pkgs {
   DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge $*
   print_info removed: $*
}

function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
            apt-get -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
}

function check_remove {
    if [ -n "`which "$1" 2>/dev/null`" ]
    then
        DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
        print_info "$2 removed"
    else
        print_warn "$2 is not installed"
    fi
}

function check_sanity {
    # Do some sanity checking.
    if [ $(/usr/bin/id -u) != "0" ]
    then
        die 'Must be run by root user'
    fi

    if [ ! -f /etc/debian_version ]
    then
        die "Distribution is not supported"
    fi
}

function backup_file {
    backup_fn=$1

    if [ ! -e "${backup_fn}.orig" ]; then
        cp -v $backup_fn ${backup_fn}.orig
    else
        print_warn "Backup of $backup_fn already exists"
    fi
}
