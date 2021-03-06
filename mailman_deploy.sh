#!/bin/bash

script_dir=`dirname $0`
. $script_dir/setup_common.sh

function setup_packages {
    print_info "Installing required packages"

    # If running trusty then allow upgrading mailman version
    curr_release=$(lsb_release -c | awk '{print $2}')
    if [[ "$curr_release" -eq "trusty" ]]; then
        upgrade_release=vivid
        print_info "Using $upgrade_release for mailman"

        echo "deb http://archive.ubuntu.com/ubuntu $upgrade_release main restricted universe multiverse" >  /etc/apt/sources.list.d/${upgrade_release}.list
        cat > /etc/apt/preferences.d/$upgrade_release <<END
Package: *
Pin: release a=$upgrade_release
Pin-Priority: 100
END
        # Update package list now
        /usr/bin/apt-get -q -y update

        # Update apt to remove error messages whenever running apt
        apt-get -y -t ${upgrade_release} install apt/${upgrade_release}
    else

        # Just update package list if not upgrading mailman
        /usr/bin/apt-get -q -y update

    fi

    # Make sure all 
    /usr/bin/apt-get -q -y dist-upgrade

    # Remove anacron if installed, since it stops anything
    # in /etc/cron.daily running as expected
    check_remove /usr/sbin/anacron anacron

    # Make sure cron is installed
    check_install /usr/sbin/cron cron

    # Install a MTA and web server before mailman
    # To satisfy the mailman package dependencies
    # with our desired MTA and webserver
    # Otherwise mailman would install apache+postfix
    check_install /usr/sbin/exim exim4
    check_install /usr/sbin/lighttpd lighttpd

    # Now install the mailman package
    if [ -z "$upgrade_release" ]; then
        check_install /usr/lib/mailman/bin/newlist mailman/
    else
        check_install /usr/lib/mailman/bin/newlist mailman/${upgrade_release}
    fi
}

function copy_scripts {
    print_info "Copying scripts"

    cp -v $script_dir/scripts/mmbackup /etc/cron.daily/
}

function configure_exim {
    print_info "Configuring exim"

    # Copy or mailman configs into the exim split directory
    # system
    cp -v $script_dir/configs/exim/04_exim4-config_mailman /etc/exim4/conf.d/main/
    cp -v $script_dir/configs/exim/40_exim4-config_mailman /etc/exim4/conf.d/transport/
    cp -v $script_dir/configs/exim/101_exim4-config_mailman /etc/exim4/conf.d/router/
    cp -v $script_dir/configs/exim/00_localmacros /etc/exim4/conf.d/main/

    # Update mailname to our desired name, not hostname
    mailname=/etc/mailname
    backup_file $mailname
    echo "sgvlug.net" > $mailname

    # Change exim config to:
    # 1. Be a internet connected MTA
    # 2. Handle mail for our domains
    # 3. Listen on all interfaces
    # 4. Use split configuration, which will pick up files copied above 
    exim_update_conf=/etc/exim4/update-exim4.conf.conf
    backup_file $exim_update_conf    

    sed -i "s/dc_eximconfig_configtype.*$/dc_eximconfig_configtype='internet'/" $exim_update_conf
    sed -i "s/dc_other_hostnames.*$/dc_other_hostnames='sgvlug.towhee.org;sgvlug.net;sgvlug.org;sgvhak.net;sgvhak.org;lists.repair-cafe-pasadena.org'/"  $exim_update_conf 
    sed -i "s/dc_local_interfaces.*$/dc_local_interfaces=''/" $exim_update_conf
    sed -i "s/dc_use_split_config.*$/dc_use_split_config='true'/" $exim_update_conf

    # Run exim update script, creates the file:
    # /var/lib/exim4/config.autogenerated
    /usr/sbin/update-exim4.conf -v

    # Restart exim
    /etc/init.d/exim4 restart
}

function configure_lighttpd {
    print_info "Configuring lighttpd"

    # Copy our configs to be included in the mail lighttpd.conf config
    cp -v $script_dir/configs/lighttpd/mailman.conf /etc/lighttpd
    cp -v $script_dir/configs/lighttpd/website.conf /etc/lighttpd


    # Disable directory listing in lighttpd config
    lighttpd_config=/etc/lighttpd/lighttpd.conf
    backup_file $lighttpd_config

    sed -i 's/server.dir-listing.*$/server.dir-listing          = "disable"/' $lighttpd_config

    # Add includes for our configs
    if [ -z "`grep mailman.conf $lighttpd_config`" ]; then
        cat >> $lighttpd_config <<END
# SGVLUG Lighttpd configuration
include "website.conf"
include "mailman.conf"
END
    fi

    # Restart lighttpd
    /etc/init.d/lighttpd restart
}

function configure_mailman {
    print_info "Configuring mailman"

    # Modify mailman config in etc
    # 1. Get rid of cgi-bin in urls
    # 2. Use our preferred domain by default
    # 3. Suppress alias output on newlist
    mm_config=/etc/mailman/mm_cfg.py
    backup_file $mm_config

    sed -r -i "s/^DEFAULT_URL_PATTERN.*$/DEFAULT_URL_PATTERN = 'http:\/\/%s\/mailman\/'/" $mm_config
    sed -r -i "s/^PRIVATE_ARCHIVE_URL.*$/PRIVATE_ARCHIVE_URL = '\/mailman\/private'/" $mm_config
    sed -i "s/^DEFAULT_EMAIL_HOST.*$/DEFAULT_EMAIL_HOST = 'sgvlug.towhee.org'/" $mm_config
    sed -i "s/^DEFAULT_URL_HOST.*$/DEFAULT_URL_HOST   = 'sgvlug.towhee.org'/" $mm_config
    sed -i "s/^\s*#\s*MTA\s*=\s*None/MTA=None/" $mm_config

    # Edit sitelist.cfg to disable responding to non-members
    # This keeps from generating bounces in messages sent to
    # potential spammers trying to send to open mailing lists
    sitelist_config=/var/lib/mailman/data/sitelist.cfg
    backup_file $sitelist_config

    sed -i "s/^generic_nonmember_action.*$/generic_nonmember_action = 3/" $sitelist_config
    sed -i "s/^forward_auto_discards.*$/forward_auto_discards = 0/" $sitelist_config

    # Create mailman list, necessary for mailman to start up
    if [ ! -e "/var/lib/mailman/lists/mailman" ]; then
        rand_pw=`tr -dc "[:alpha:]" < /dev/urandom | head -c 8`
        /usr/lib/mailman/bin/newlist -q mailman admin@sgvlug.net $rand_pw
    fi

    # Restart mailman, or start for first time if mailman list did not exist
    /etc/init.d/mailman restart

    # Check that site can handle the default list
    print_info "Checking mailing list routine"
    print_info "You should NOT see 'Unrouteable address' if things are configured correctly"
    exim -bt mailman@sgvlug.org
    exim -bt mailman@sgvlug.net
}

setup_packages
copy_scripts
configure_exim
configure_lighttpd
configure_mailman
