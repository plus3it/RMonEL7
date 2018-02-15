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

# Need to set this lest the default umask make our lives miserable
umask 022


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
      yum install -y "${SCLRPMS}" && logit "Success" || \
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
yum install -y rh-ruby24 rh-ruby24\*dev\*

# Enable new Ruby in current process-space
# shellcheck disable=SC1091
source /opt/rh/rh-ruby24/enable
export PATH=${PATH}:/opt/rh/rh-ruby24/root/usr/local/bin
# shellcheck disable=SC2155,SC2016
export X_SCLS="$(scl enable rh-ruby24 'echo $X_SCLS')"

# Permanently-enable new Ruby
cat << EOF > /etc/profile.d/enable_rh-ruby24.sh
#!/bin/bash
source /opt/rh/rh-ruby24/enable
export PATH=\${PATH}:/opt/rh/rh-ruby24/root/usr/local/bin
export X_SCLS="\$(scl enable rh-ruby24 'echo \$X_SCLS')"
EOF

# Ensure that the SCL Ruby can find its runtime libs
printf "Updating LDSO config... "
echo /opt/rh/rh-ruby24/root/usr/lib64 > /etc/ld.so.conf.d/rh-ruby24.conf && \
  echo "Success" || echo "Failed"
printf "Forcing re-read of LDSO configs... "
ldconfig && echo "Success" || echo "Failed"

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
   curl -s -L "${RECONSURI}"/main_cf.sh | /bin/bash -
fi

# Grab and stage RedMine archive
(
  cd /tmp && curl -L http://www.redmine.org/releases/"${RMVERS}".tar.gz | \
  tar zxvf -
)

# Use an appropriate method to move the files
if [[ -d /var/www/redmine ]]
then
  (
   cd /tmp/"${RMVERS}" && tar cf - . | ( cd /var/www/redmine && tar xf - )
  )
else
   mv "${RMVERS}" /var/www/redmine
fi

# Write standard RedMine main config (via add-on script)
if [[ -e /etc/cfn/scripts/configuration_yml.sh ]]
then
   echo "Excuting config-YAML script"
   bash -xe /etc/cfn/scripts/configuration_yml.sh
else
   echo "Fetching/running RedMine main config tasks..."
   curl -s -L "${RECONSURI}"/configuration_yml.sh | /bin/bash -
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
   curl -s -L "${RECONSURI}"/database.yml \
     -o /var/www/redmine/config/database.yml
fi

# Ready the ELB-tester for new read-location
echo "Making sure ELB test-file is still visible"
cp -al /var/www/html/ELBtest.txt /var/www/redmine/public/

# Make sure Apache has appropriate rights to RM content
# shellcheck disable=SC2038
find /var/www/redmine ! -user apache | xargs chown apache:apache

systemctl restart httpd

# Remaining tasks don't work under FIPS mode, so...
if [[ -e /proc/sys/crypto/fips_enabled ]] &&
   [[ $(grep -q 1 /proc/sys/crypto/fips_enabled)$? -eq 0 ]]
then
   echo "FIPS mode enabled: must disable for RedMine"
   if [[ -x $(which wam) ]]
   then
      echo "Found WAM: using SaltStack to disable FIPS..."
      salt-call --local ash.fips_disable && echo "Success" || \
        echo "Salt exited with an error"
      printf "Verifying FIPS kernel RPM has been removed: "
      rpm -q dracut-fips || true
   else
      echo "Disabling FIPS..."
      printf "\t- Removing FIPS kernel RPMs... "
      yum -q erase -y dracut-fips\* && echo "Success." || echo "Failed."
      printf "\t- Backing up current boot-kernel... "
      mv -v /boot/initramfs-"$(uname -r)".img{,.FIPS-bak} && \
        echo "Success." || echo "Failed."
      printf "\t- Creating new boot-kernel... "
      dracut && echo "Success." || echo "Failed."
      printf "\t- Updating boot options... "
      grubby --update-kernel=ALL --remove-args=fips=1 && \
        echo "Success." || echo "Failed."
      [[ -f /etc/default/grub ]] && sed -i 's/ fips=1//' /etc/default/grub
   fi
   exit
else
   # Ruby-based RedMine setup tasks here
   if [[ -e /etc/cfn/scripts/GemStuff.sh ]]
   then
      echo "Executing staged Ruby-gem tasks..."
      bash -xe /etc/cfn/scripts/GemStuff.sh
   else
      echo "Fetching/executing Ruby-gem tasks..."
      curl -L "${RECONSURI}"/GemStuff.sh | /bin/bash -
   fi

   # Ready for Passenger setup
   if [[ -e /etc/cfn/scripts/Passenger_conf.sh ]]
   then
      echo "Executing staged Passenger httpd-config tasks..."
      bash -xe /etc/cfn/scripts/Passenger_conf.sh
   else
      echo "Fetching/executing Passenger httpd-config tasks..."
      curl -s -L "${RECONSURI}"/Passenger_conf.sh | /bin/bash -
   fi
fi

## # Install git-remote plugin
## echo "Fetching git-remote install/config tasks..."
## curl -s -L ${RECONSURI}/git_remote.sh | /bin/bash -
## 
## # Install RedMine plugin-group:
## curl -s -L ${RECONSURI}/plugins.sh | /bin/bash -
## 
## # Reboot so everything's there...
## /sbin/shutdown -r +1 "Rebooting to finalize configs"
