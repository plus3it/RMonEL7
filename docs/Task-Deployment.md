## Initial Deployment

This project provides a collection of CloudFormation (CFn) templates to handle the deployment of all of the AWS components necessary to support a RedMine deployment. Additionally, this project includes a "parent" template. The per-service templates can be run individually or their running can be handled in a monolithic, coordinated fashion via the parent template. 

It will be necessary for the templates' user to have sufficient privileges to execute all of the AWS elements present in this template-set. This means the user will need to have privileges to create/modify:

* S3 buckets
* EC2 security groups
* EC2 load balancers
* EFS storage services
* RDS database clusters and instances
* EC2 autoscaling groups, launch configurations and instances

If all of these privileges are not present in a single user/role, it will be necessary to execute the templates individually with users/roles appropriate to the individual template.

Whether running via the individual CFn templates or the "parent" template, the general deployment process/flow looks like:

1. _Execute the S3 bucket setup:_ A private S3 bucket is created with no permissions set.
1. _Execute the network Security Group setup:_ Three network security groups are set up within the target VPC:
    1. _Application:_ To be applied to the stack's ASG-managed EC2 instance and to its ALB. Allows port 443 from anywhere and allows port 80 between members of the security group. All other sources/destinations are blocked.
    1. _Storage:_ To be applied to the stack's ASG-managed EC2 instance and to its EFS share. Allows NFS traffic between the EC2 instance and the EFS mount-targets. All other sources/destinations are blocked.
    1. _Database:_ To be applied to the stack's ASG-managed EC2 instance and to its RDS service. Allows mysql traffic over standard 3306/TCP between the EC2 instance and its RDS database. All other sources/destinations are blocked.
1. _Execute the EFS service setup:_ A generic, three-AZ EFS share is configured. The "storage" security group is applied to allow NFS traffic only from the RedMine EC2 host.
1. _Execute the ELB service setup:_ An application load-balancer is configured. The "application" security group is applied to all HTTPS-based requests from any source and allow HTTP-based communications only between the active RedMine EC2 instance and the load-balancer. A user-selected, ACM-managed SSL certificate is bound to the load-balancer.
1. _Execute the IAM role setup:_ An IAM policy and attachable instance-role is created. The IAM objects allow unfettered access to the  S3 bucket from the RedMine-hosting EC2 instances. This bucket is used by the EC2 instance to perform backups of the attachment directory. The IAM policy also allows the AutoScaling service to launch and terminate EC2 instances. Lastly, the policy allows the EC2 instance to be managed via SSM and to use the CloudWatch agent to export system logs and metrics to CloudWatch.
1. _Execute the RDS database setup:_ An Aurora database cluster of from 1 to 4 instances are created with a user-selectable instance type. User can opt to provide "friendly" names for objects or allow CFn to generate names. In the former case, the cluster will be named `<USER_PROVIDED_NAME>-cluster` and each instance will be named `<USER_PROVIDED_NAME>-nN` (where `N` is a value from 0 to 3 and assigned based on whether the CFn-user selected a 1, 2, 3 or 4 node cluster to be provisioned). The user can select whether a new (blank) database is created or may supply the ARN of a previously backed up Aurora database cluster to act as a content and configuration source.
1. _Execute the AutoScaling Group setup:_ Creates an AutoScaling Group with an attached Launch Configuration. The default scaling parameters for the AutoScaling group ensure that one EC2 instance is active at all times. The Launch Configuration ensures that the desired instance-type is deployed to the correct subnets with the correct security groups attached (see above). The Launch Configuration also orchestrates the application of STIG-hardening as well as the installation and configuration of RedMine.

### Notes and Caveats for use

These templates support the creation of a fresh/empty database or seeding the database with a snapshot from a prior deployment.

After the ASG CFn template has run to the `CREATE_COMPLETE` state, the service will not yet be immediately online. Upon a "too soon" browse to the ELB's URL, the CFn-user will likely be greeted by a `Service-rebuild in progress. Please be patient.` message. This message is displayed while the final RedMine-relate Ruby-gem tasks are run (plugin installation, etc.). This page auto-refreshes every ten seconds. When the Ruby tasks complete and RedMine is ready to go, the RedMine login page _should_ display: a timing issue between the auto-refresh and the RedMine start can sometimes result in an error page - refreshing the page normally clears the error.

#### "Fresh" deployment

When the last CFn template has been run, a brand new, ready-to-configure RedMine deployment will be available. If your brand new deployment is Internet-facing - or otherwise accessible from untrusted networks, it is _critical_ that the CFn template-user immediately access the RedMine login page and set up admin credentials (before any nefarious actors discover the new deployment and grab ownership, themselves).

#### Snapshot-based deployment

If deploying from snapshot, uderstand the following limitations:

* Changing the "Master User" attribute is not possible. When the "snapshot ID" parameter is set, the "Master User" value is ignored by the RDS creation-tasks. Attempts to subsequently alter the master user's name (by way of stack update actions) will result in data the data from the snapshot being lost.
* Changing the master user's "Password" attribute is not possible. The templated RDS creation-processes ignore the attempt to change.
* If using the "parent" template to orchestrate, it will be necessary to supply the RDS credentials from the snapshot source RDS. These credentials will be propagated into the resultant EC2 instance. If credentials are not supplied or do not match what is within the snapshot, the resultant EC2 instance(s) will not have the correct credentials to work with the database.
