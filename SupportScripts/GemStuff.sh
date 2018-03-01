#!/bin/sh
#
# Master script for preparing node to act as RedMine web-tier
#
# Add this script to the stack's RedmineHelperLocation
#
#################################################################
while read -r RMENV
# Read args from envs file
do
   # shellcheck disable=SC2163
   export "${RMENV}"
done < /etc/cfn/RedMine.envs
DBHOST="${RM_DB_FQDN}"
DBINST="${RM_DB_INSTANCE_NAME}"
DBUSER="${RM_DB_ADMIN_NAME}"
DBPASS="${RM_DB_ADMIN_PASS}"
SQLCMD="mysql -u ${RM_DB_ADMIN_NAME} -h ${RM_DB_FQDN}
        --password="${RM_DB_ADMIN_PASS}" ${RM_DB_INSTANCE_NAME}"
EMPTYDB=$(echo "show tables" | ${SQLCMD})

# Need to set this lest the default umask make our lives miserable
umask 022


##########################################################
# Configure a temp-db so that RedMine's gem-configurator
# tools may function properly
##########################################################
printf "Ensure local DB is running... "
systemctl restart mariadb && echo "Success." || echo "Failure."
if [[ $? -eq 0 ]]
then
   printf "Creating (temporary) config-DB..."
   mysql -u root << EOF
create database ${DBINST};
grant all privileges on ${DBINST}.* to ${DBUSER}@'localhost' identified by '${DBPASS}';
flush privileges;
EOF
fi

# Ruby-based RedMine setup tasks here
echo "Running ruby-gem tasks..."
( cd /var/www/redmine 
  gem install bundler --no-rdoc --no-ri && \
  bundle install --without development test postgresql sqlite && \
  bundle exec rake generate_secret_token && \
  bundle exec rake db:migrate RAILS_ENV=production && \
  gem install passenger --no-rdoc --no-ri && \
  passenger-install-apache2-module -a || \
  echo "One or more RedMine-related Ruby tasks failed")

# Take further actions if RDS DB is empty
if [[ $EMPTYDB = '' ]]
then
   echo "RDS DB is empty: attempting to populate..."
   mysqldump -u root --opt "${DBINST}" | ${SQLCMD}
else
   echo "RDS DB already has data: executing no further tasks"
fi

# Stop and disable local DB
echo "Disabling local DB"
systemctl stop mariadb
systemctl disable mariadb

# Point RedMine to RDS
printf "Redirecting RedMine database config to point to remote DB... "
sed -i '/host:/s/localhost/'${DBHOST}'/' \
  /var/www/redmine/config/database.yml && echo "Success" || echo "Failed"
