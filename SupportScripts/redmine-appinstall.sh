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
RMVERS="${RM_BIN_VERS}"
RECONSURI="${RM_HELPER_ROOT_URL}"
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

# Enable new Ruby
cat << EOF > /etc/profile.d/enable_rh-ruby24.sh
#!/bin/bash
source /opt/rh/rh-ruby24/enable
export X_SCLS="\$(scl enable rh-ruby24 'echo \$X_SCLS')"
EOF
chmod 000755 /etc/profile.d/enable_rh-ruby24.sh


# Use correct character-set with database
sed -i '/mysqld_safe/s/^/character-set-server=utf8\n\n/' /etc/my.cnf

# Enable services
systemctl enable httpd
systemctl enable mariadb

# Configure Postfix (via add-on script)
if [[ -e "/etc/cfn/scripts/main_cf.sh" ]]
then
   echo "Excuting main_cf script"
   bash -xe /etc/cfn/scripts/main_cf.sh
else
   echo "Fetching Postix-config tasks..."
   curl -s -L ${RECONSURI}/main_cf.sh | /bin/bash -
fi

# Grab and stage RedMine archive
(
  cd /tmp && curl -L http://www.redmine.org/releases/${RMVERS}.tar.gz | \
  tar zxvf -
)

# Use an appropriate method to move the files
if [[ -d /var/www/redmine ]]
then
  (
   cd /tmp/"${RMVERS}" && tar cf - . | ( cd /var/www/redmine && tar xf - )
  )
else
   mv ${RMVERS} /var/www/redmine
fi

# Write standard RedMine main config (via add-on script)
if [[ -e /etc/cfn/scripts/configuration_yml.sh ]]
then
   echo "Excuting config-YAML script"
   bash -xe /etc/cfn/scripts/configuration_yml.sh
else
   echo "Fetching/running RedMine main config tasks..."
   curl -s -L ${RECONSURI}/configuration_yml.sh | /bin/bash -
fi

# Write standard (temporary) RedMine DB-config
# (via DL of static config-file)
if [[ -e /etc/cfn/files/database.yml ]]
then
   echo "Copying RedMine's local database config info from source..."
   install -b -m 000640 -o apache -g apache /etc/cfn/files/database.yml \
     /var/www/redmine/config/database.yml
else
   echo "Writing RedMine's local database config info..."
   curl -s -L ${RECONSURI}/database.yml -o /var/www/redmine/config/database.yml
fi

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
