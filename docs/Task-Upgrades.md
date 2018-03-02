## Upgrading Service Elements

There are four primary elements to the RedMine deployment that will require periodic upgrades:

- Upgrades to the RedMine software, itself
- Upgrades to RedMine plugins
- Upgrades to Operating system:
  - Newly-available AMIs
  - Between-AMI-publications OS patches
- Upgrades to the RDS engine

In general, upgrades are expected to be handled via a "stack update" action. When performing a stack-update, modify the relevant parameters' values to force the relevant update.

### RedMine Application Upgrades

To upgrade the version of RedMine deployed, update the `RedmineBinaryVersion` parameter's version-string. This string typically takes the form `redmine-<X.Y.Z>`.

Note: current functioning of the project's `redmine-appinstall.sh` script takes the `RedmineBinaryVersion` parameter's string-value, appends it to the standard RedMine download source, `http://www.redmine.org/releases/` and then fetches the software from that assembled URL. If installing into a VPC that does not have access to the Internet-hosted RedMine download site, it will be necessary to alter the root URL. The download repository URL is easily modifiable in the script's header section.

### RedMine Plugin Upgrades (and Additions/Deletions)

Plugins are generally handled by the deployment site's `plugins.sh` script (stored in the `RedmineHelperLocation`). Depending how the site has written their `plugins.sh` script, upgrading plugins may be as simple as re-running the `plugins.sh` script. Similarly, adding or deleting plugins is a matter of updating the site's `plugins.sh` script and re-running.

Re-running can be done interactively on the already deployed instance or by forcing an instance-replacement. It is highly discouraged to do the former, however. To force an instance-replacement, execute a stack-update action, changing the current value of the `ToggleNewInstances` parameter.

### Operating System Upgrades

Operating system updates can take two forms: a `yum update` type of operation or an AMI update operation.

#### Yum Update Method

Each time a new EC2 is launched, the included hardening tasks perform a `yum update` action. Force an instance-replacement by executing a stack-update action with a change of the current value of the `ToggleNewInstances` parameter.

#### AMI Update Method

Changing to a newer AMI (via the tempate's `AmiId` parameter-value) forces an instance-replacement. This will change the starting RPM-set of the deployed instance. Additionally, the included hardening tasks perform a `yum update` action

### RDS Engine Upgrades

RDS is an Amazon-managed service. Upgrades happen automatically and transparently. There is not currently anything for a CFn-user to do.

## Notes and Caveats

* Whether deployed via a "parent" template or individual element-templates, updates _can_ be applied via the individual element-template. If deployed via a "parent" template, direct updates of element-level templates is highly-discouraged. If attempting such an update from within the CloudFormation web console, an alert will pop up warning against such an action. Heed that warning!
* Any modification of the `AmiId`, `KeyPairName`, `IamInstanceProfile`,  deployment-VPC or `ToggleNewInstances` will cause the ASG-managed EC2 instance to be replaced. Be sure these parameters' values are not modified if performing a stack-update where rention of the current EC2 instance is desired.
* Changing the value of the deployed templates' `MasterUsername` parameter typically results in data-loss. 
