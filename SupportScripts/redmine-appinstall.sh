#!/bin/bash
# shellcheck disable=SC2015
#
# Script to handle installation/configuration of the RedMine
# web-application
#
#################################################################
PROGNAME=$(basename "${0}")
LOGFACIL="user.err"
# Read in template envs we might want to use
while read -r RMENV
do
   # shellcheck disable=SC2163
   export "${RMENV}"
done < /etc/cfn/RedMine.envs
FWSVCS=(
      ssh
      http
      https
   )

# Error logging & handling
function err_exit {
   echo "${1}"
   logger -t "${PROGNAME}" -p ${LOGFACIL} "${1}"
   exit 1
}

# Success logging
function logit {
   echo "${1}"
   logger -t "${PROGNAME}" -p ${LOGFACIL} "${1}"
}


##########
## Main ##
##########
case $(rpm -qf /etc/redhat-release --qf '%{name}') in
   centos-release)
      SCLRPMS=$(
            repoquery centos-release-\*scl\* --qf '%{name}' | \
            sed -e :a -e '$!N; s/\n/ /; ta'
         )
      logit "Ensure that SCL repos are available"
      yum install -y ${SCLRPMS} && logit "Success" || \
         err_exit "Failed to install SCL for CentOS"
      ;;
   redhat-release-server)
      if [[ $(rpm -qa \*-rhui-\*) == "" ]]
      then
         err-exit "Currently only RHUI-serviced Red Hat hosts are supported"
      else
      yum-config-manaer --enable rhui-REGION-rhel-server-rhscl
      fi
      ;;
   redhat-release-workstation)
      err-exit "Unsupported Red Hat release"
      ;;
   redhat-release-client)
      err-exit "Unsupported Red Hat release"
      ;;
   redhat-release-computenode)
      err-exit "Unsupported Red Hat release"
      ;;
   *)
      err_exit "Cannot ID Enterprise Linux distriution"
      ;;
esac


# RedMine wants DevTools (and more, brotatochip)
yum install -y gdbm-devel libdb4-devel libffi-devel libyaml libyaml-devel \
    ncurses-devel openssl-devel readline-devel tcl-devel ImageMagick \
    ImageMagick-devel libcurl-devel httpd-devel maradb-devel \
    ipa-pgothic-fonts cyrus-imapd cyrus-sasl-md5 cyrus-sasl-plain stunnel \
    "@Development Tools"

systemctl restart httpd

# Install a more up-to-date Ruby
yum erase -y ruby
yum install -y rh-ruby24

# Use correct character-set with database
sed -i '/mysqld_safe/s/^/character-set-server=utf8\n\n/' /etc/my.cnf

# Enable services
systemctl enable httpd
systemctl enable mariadb

## # Configure Postfix (via add-on script)
## echo "Fetching Postix-config tasks..."
## curl -s -L ${RECONSURI}/main_cf.sh | /bin/bash -
## 
## # Grab and stage RedMine archive
## (cd /tmp ; curl -L http://www.redmine.org/releases/${RMVERS}.tar.gz | \
##  tar zxvf - && mv ${RMVERS} /var/www/redmine )
## 
## # Write standard RedMine main config (via add-on script)
## echo "Fetching RedMine main config tasks..."
## curl -s -L ${RECONSURI}/configuration_yml.sh | /bin/bash -
## 
## # Write standard (temporary) RedMine DB-config
## # (via DL of static config-file)
## echo "Writing RedMine's local database config info..."
## curl -s -L ${RECONSURI}/database.yml -o /var/www/redmine/config/database.yml
## 
## # Ready the ELB-tester for new read-location
## echo "Making sure ELB test-file is still visible"
## cp -al /var/www/html/ELBtest.txt /var/www/redmine/public/
## systemctl restart httpd
## 
## # Ruby-based RedMine setup tasks here
## echo "Fetching Ruby-gem tasks..."
## curl -L ${RECONSURI}/GemStuff.sh | /bin/bash -
## 
## # Ready for Passenger setup
## echo "Fetching Passenger httpd-config tasks..."
## curl -s -L ${RECONSURI}/Passenger_conf.sh | /bin/bash -
## 
## # Install git-remote plugin
## echo "Fetching git-remote install/config tasks..."
## curl -s -L ${RECONSURI}/git_remote.sh | /bin/bash -
## 
## # Install RedMine plugin-group:
## curl -s -L ${RECONSURI}/plugins.sh | /bin/bash -
## 
## # Reboot so everything's there...
## /sbin/shutdown -r +1 "Rebooting to finalize configs"
