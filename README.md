# RedMine on EL7

This project is designed to facilitate the deployment of a modular, flexible, scalable RedMine configuration within AWS. The provided project-elements leverages a mix of tools to achieve this end:

* CFn-based automation to deploy and manage the AWS components underpinning the overall service. Supported elements include
    * SES
    * ELB
    * EC2 - launched in a standalone or AutoScale group context
    * RDS - MySQL flavor via MySQL, MariaDB or Aurora
    * EFS
* Deployment automation scripts to prepare an instance launced from a generic EL7 AMI to host the RedMine application
    * Appliction of STIG-hardening (with following notes/exceptions) via [watchmaker](https://github.com/plus3it/watchmaker.git).
        * FIPS-mode disabled due to underlying RedMine incompatibilities
        * STIG-compliant partitioning dependent on use of suitably-partitioned AMI (see [spel](https://github.com/plus3it/spel.git) project for an example, suitable AMI)
        * SEL-mode currently defaults to Permissive due to use of non-SEL'able filesystems (see EFS note, above)
    * Configuration of firewalld exceptions for HTTP service
    * Enablement of Software Collections (see [SCL](https://www.softwarecollections.org/en/)) repositories.
    * Installation and configuration of RedMine RPM dependencies (e.g. Ruby 2.4 from SCL)
* Deployment automation scripts to handle the ininitial install and configuration of the RedMine application.
    * Launch-time compilation of RedMine and dependent gems
    * Configuration of RedMine to use RDS-hosted MySQL-compatible database. See the [new stack](docs/FreshStackDBnotes.md) document for discussion of issues around configuration of the RDS-hosted database.
    * Configuration of Apache HTTPD for Passenger
    * Installation of optional plugins — via "site" scripts (automation does not include, simply invokes such scripts)

    **Note:** because RedMine stores much of its runtime/continuing configuration information within a database, site-specific customizations are a (mostly) manual task that takes place after the deployment-automation tasks complete.

The expected deployment-model is as follows:

* RDS to host persistent configuration and content elements
* EFS to host persistent, file-based content elements. This content will be things like Git repository (bare) clones, images and other, file-type content. While this content _can_ be stored in databases as BLOBs but is generally contraindicated. If migrating file-based content from an existing RedMine site, see the [file migration](docs/EFS_MigrationNotes.md) document.
* EC2 to host the operating environment - in this case Enterprise Linux 7 (e.g. RHEL, CentOS, etc.) - that hosts the RedMine runtime.
* ELB to provide stable, internet-facing access to the application while allowing the lower-level components to all be run from not publicly-routed address-space.
* SES to provide outbound mail-based notification capabilities to the OS (monitoring-alerts, etc.) and/or the RedMine service (account creation, password-change and other notification).

Scaling and availability is furnished primarily through native AWS services' capabilities: RDS an EFS both have built-in enhancedlreliability/availability and scalability functionality. Clustering of RedMine nodes (EC2 nodes) is not supported with this tool-set: use of AutoScaling Groups are the expected method for improving the baseline EC2-layer's availability.

Data protection is currently only provided within the RDS context. EFS is generally durable but is not further enhanced via backup tools in the current deployment automation tool-set.


## Contribution and Other Guidelines

Please see the guidlines in the [docs](docs) directory.


![Build Status](https://travis-ci.org/plus3it/RMonEL7.svg?branch=master)
