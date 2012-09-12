SGVLUG Mailing List Deployment Script
=====================================

This script will setup and configure Mailman as used by the SGVLUG at:
http://sgvlug.net/mailman/

The script performs the following actions:
* Installs required packages
* Configures exim as the MTA
* Configures lighttpd as the webserver
* Configures mailman except for adding LUG mailing lists

The script was developed and tested under Ubuntu 12.04. However, it has
been designed to apply changes to the distribution configuration files
in a way that should be future compatible. It should hopefully work on
any Debian based distribution.

In order to fully restore the LUG mailing list on a new server one would:
* Run mailman_deploy.sh from this repository
* Extract from a backup file (obtained elsewhere):
    /var/lib/mailman/archives
    /var/lib/mailman/data
    /var/lib/mailman/lists
* Run the following to reset passwords for lists if they are unknown:
    /usr/lib/mailman/bin/change_pw -l <list_name> -p <new_password>
* Also check the modified configuration files against those in the backup to 
ensure no changes have been made that were not incorporated into this script.
