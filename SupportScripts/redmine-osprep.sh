#!/bin/bash
# shellcheck disable=SC2015
#
# Script to handle preparation of the instance for installing
# and configuring RedMine
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
NFSOPTS="-rw,vers=4.1"
FWSVCS=(
      ssh
      http
      https
   )
PERSISTED=(
      files
      Repositories
   )

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

# Install/start NFS components if installed
function NfsSetup {
   local NFSRPMS
   NFSRPMS=(
         nfs-utils
         autofs
      )
   local NFSSVCS
   NFSSVCS=(
         rpcbind
         rpc-statd
         nfs-idmapd
         autofs
      )

   # shellcheck disable=SC2145
   logit "Installing RPMs: ${NFSRPMS[@]}... "
   yum install -y -q "${NFSRPMS[@]}" > /dev/null 2>&1 && \
     logit "Success" || err_exit "Yum failure occurred"

   # Configure autofs files
   if [ -e /etc/auto.master ]
   then
      # Ensure auto.direct key present in auto.master
      if [[ $(grep -q "^/-" /etc/auto.master)$? -eq 0 ]]
      then
         echo "Direct-map entry found in auto.master file"
      else
         printf "Adding direct-map key to auto.master file... "
         sed -i '/^+auto.master/ s/^/\/-  \/etc\/auto.direct\n/' \
           /etc/auto.master && echo "Success" || \
           err_exit "Failed to add direct-map key to auto.master file"
      fi

      # Ensure auto.direct file is properly populated
      if [[ ! -e /etc/auto.direct ]]
      then
         (
           printf "/var/www/redmine/files\t%s\t" "${NFSOPTS}"
           printf "%s/files\n" "${RM_PERSISTENT_SHARE_PATH}"
           printf "/var/www/redmine/Repositories\t%s\t" "${NFSOPTS}"
           printf "%s/Repositories\n" "${RM_PERSISTENT_SHARE_PATH}"
          ) >> /etc/auto.direct
          chcon --reference=/etc/auto.master /etc/auto.direct
      fi
   else
      err_exit "Autofs's auto.master file missing"
   fi

   for SVC in "${NFSSVCS[@]}"
   do
      case $(systemctl is-enabled "${SVC}") in
         enabled|static|indirect)
            ;;
         disabled)
            logit "Enabling ${SVC} service..."
            systemctl enable "${SVC}" && logit success || \
              err_exit "Failed to enable ${SVC} service"
            ;;
      esac

      if [[ $(systemctl is-active "${SVC}") != active ]]
      then
         logit "Starting ${SVC} service..."
         systemctl start "${SVC}" && logit success || \
           err_exit "Failed to start ${SVC} service"
      fi
   done
}

function ShareReady {
   local SHARESRVR
   local SHAREROOT

   if [[ $(echo "${RM_PERSISTENT_SHARE_PATH}" | grep -q :)$? -eq 0 ]]
   then
      SHARESRVR=$(echo "${RM_PERSISTENT_SHARE_PATH}" | cut -d ':' -f 1)
      SHAREROOT=$(echo "${RM_PERSISTENT_SHARE_PATH}" | cut -d ':' -f 2)
   else
      SHARESRVR="${RM_PERSISTENT_SHARE_PATH}"
   fi

   logit "Validating available share directories... "

   logit "Verify ${SHARESRVR} is mountable... "
   mount "${SHARESRVR}":/ /mnt && logit "Success" || \
     err_exit "Was not able to mount ${SHARESRVR}:/"

   logit "Ensure target persisted dirs are available... "
   for PDIR in "${PERSISTED[@]}"
   do
      if [[ -d /mnt/${SHAREROOT}/${PDIR} ]]
      then
         logit "${SHARESRVR}:${SHAREROOT}/${PDIR} exists"
      else
         logit "${SHARESRVR}:${SHAREROOT}/${PDIR} doesnt exist"
         logit "Attempting to create ${PDIR}"
         mkdir -p "/mnt/${SHAREROOT}/${PDIR}" && logit "Success" || \
           err_exit "Failed creating ${PDIR}"
      fi
   done

   umount /mnt || err_exit "Failed to unmount test-fs"
}

function NeedEpel {
   if [[ $(yum repolist epel | grep -qw epel)$? -eq 0 ]]
   then
      logit "epel repo already available"
   else
      logit "epel repo not already available: attempting to fix..."
      yum install -y \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
        && logit success || err_exit "Failed to install epel repo-def"
   fi

   logit "Ensure epel repo is active..."
   yum-config-manager --enable epel || err_exit "Failed to enable epel"
}


##########
## Main ##
##########

########
## Ensure /tmp is tmpfs
########
logit "Checking if tmp.mount service is enabled... "
case $(systemctl is-enabled tmp.mount) in
   masked)
      logit "Masked - attempting to unmask... "
      systemctl -q unmask tmp.mount && logit "Success" || \
        err_exit "Failed to unmask."

      logit "Disableed - attempting to enable... "
      systemctl -q enable tmp.mount && logit "Success" || \
        err_exit "Failed to enable."
      ;;
   disabled)
      logit "Disableed - attempting to enable... "
      systemctl -q enable tmp.mount && logit "Success" || \
        err_exit "Failed to enable."
      ;;
   enabled)
      logit "Already enabled."
      ;;
esac

logit "Checking if tmp.mount service is active... "
case $(systemctl is-active tmp.mount) in
   inactive)
      logit "Inactive - attempting to activate"
      systemctl start tmp.mount && Login "Success" || \
        err_exit "Failed to start tmp.mount service"
      ;;
   active)
      logit "Already active"
      ;;
esac

## Dial-back SEL as needed
logit "Checking SEL mode"
case $(getenforce) in
   Enforcing)
      logit "SEL is in enforcing mode: attemptinto dial back... "
      setenforce 0 && logit "Success" || \
        err_exit "Failed to dial back SEL"

      logit "Permanently dialing back enforcement mode..."
      sed -i '/^SELINUX=/s/enforcing/permissive/' /etc/selinux/config && \
        logit "Success" || err_exit "Failed to dial back SEL"
      ;;
   Disabled|Permissive)
      logit "SEL already in acceptable mode"
      ;;
esac

########
## Ensure firewalld is properly configured
########
logit "Checking firewall state"
case $(systemctl is-active firewalld) in
   inactive)
      logit "Firewall inactive: no exceptions needed"
      logit "However, this is typically not a recommended config-state."
      ;;
   active)
      logit "Firewall active. Checking rules..."

      FWSVCLST=$(firewall-cmd --list-services)

      for SVC in "${FWSVCS[@]}"
      do
         if [[ $(echo "${FWSVCLST}" | grep -wq "${SVC}")$? -eq 0  ]]
         then
            logit "${SVC} already in running firewall-config"
         else
            logit "${SVC} missing from running firewall-config."
            logit "Attempting to add ${SVC}... "
            firewall-cmd --add-service "${SVC}" && logit "Success" || \
              err_exit "Failed to add ${SVC} to running firewall config"
            logit "Attempting to add ${SVC} (permanently)... "
            firewall-cmd --add-service "${SVC}" --permanent && \
              logit "Success" || \
              err_exit "Failed to add ${SVC} to permanent firewall config"
         fi
      done
      ;;
esac

# Call NfsSetup function (make conditional, later)
NfsSetup

# Make sure the persistent-data share is ready
ShareReady

# Install first set of required RPMs
logit "Installing RPMs needed by RedMine..."
yum install -y parted lvm2 httpd mariadb mariadb-server mariadb-devel \
    mariadb-libs wget screen bind-utils mailx iptables-services at jq && \
      logit "Success" || err_exit "Yum experienced a failure"

# Create (temporary) default index-page
logit "Creating temporary index.html..."
cat << EOF > /var/www/html/index.html
<html>
  <head>
    <title>RedMine Rebuild In Progress</title>
    <meta http-equiv="refresh" content="30" />
  </head>
  <body>
    <div style="width: 100%; font-size: 40px; font-weight: bold; text-align: cen
ter;">
      Service-rebuild in progress. Please be patient.
    </div>
  </body>
</html>
EOF

# Because here-documents don't like extra stuff on token-line
# shellcheck disable=SC2181
if [[ $? -eq 0 ]]
then
   logit "Success"
else
   err_exit "Failed creating temporary index.html"
fi

# Create ELB test file
logit "Create ELB-testable file..."
echo "I'm alive" > /var/www/html/ELBtest.txt && logit "Success" || \
  err_exit "Failed creating ELB test-file."

# Let's get ELB/AS happy, early
logit "Temp-start httpd so ELB can monitor..."
systemctl restart httpd && logit success || \
  err_exit "Failed starting httpd"

# Try to activate epel as needed
NeedEpel

