# RDS-Hosted Database Peculiarities

RedMine's MySQL database connection-gems need a MySQL database during their compilation. Because the stacks are meant to allow safe-replaceability of the EC2 host, the connection-gems are initially compiled against a local, dummy MySQL database. Once compiled, RedMine is then reconfigured to connect to the RDS-hosted database.

The RDS-hosted database is empty on any initial/fresh stack-deployment. This empty state will cause the RedMine web-service to display an error page once it initially reaches a ready-state. Populate the database to make this error go away.

Populating the RDS-hosted database is a fairly straight-forward task (see [this DigitalOcean article](https://www.digitalocean.com/community/tutorials/how-to-migrate-a-mysql-database-between-two-servers) to get a better idea of the specifics):
1. Use the `mysqldump` tool to create a backup of an existing MySQL database for RedMine.
    * If you have an existing RedMine installation, dump out its contents and transfer them to the new RedMine-hosting EC2 instance.
    * If you do not have an existing RedMine installation, create a dump from the "dummy" database that was created during the EC2 instance's initial deployment.
1. Use the `mysql` utility to restore data from the file created with the `mysqldump` tool. The RDS credentials are stored in the `/etc/cfn/RedMine.envs` file.
1. Restart the httpd processes.

**Note:** It is recommended that, after populating the RDS-hosted database, that an EC2-replacing stack-update be performed. The update ensures that all RedMine plugins are appropriately set up to reference the RDS-hosted database elements. Changing the EC2's AMI, availability zone, (provisioning) key name, private IP address and/or subnet attribute-values will force a redeployment.
