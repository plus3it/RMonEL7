## Testing Deployment Modifications

This template set includes the ability to easily duplicate an existing RedMine deployment. Primary intended purpose for this is to create an installation suitable for non-destructively testing software and associated upgrade procedures.

The recommended way to perform an installation duplication is to:

1. Capture the "production" deployment's configuration. This can be done by executing:
    ~~~~
    aws cloudformation describe-stacks --stack-name <PRODUCTION_STACK_NAME> |
      sed -e '/"Tags"/,$d' -e '1,/"Description":/d' \
          -e 's/^.*"Parameters": //' -e 's/],/]/' |
      python -m json.tool > test.parms.json
    ~~~~
1. Execute an RDS cluster-snapshot of the "production" service's database. Perform the snapshot with a method similar to the following:
    ~~~~
    aws rds create-db-cluster-snapshot \
       --db-cluster-snapshot-identifier manual-snap-$(date "+%Y%m%d%H%M") \
       --db-cluster-identifier <RDS_CLUSTER_NAME>
    ~~~~
1. Update the values in your `test.parms.json` file. Note: passwords captured via the prior method will not be valid. Update as necessary.
1. Add a `ParameterKey`/`ParameterValue` stanza to your `test.parms.json` file similar to the following:
    ~~~~
    {
      "ParameterKey": "DbSnapshotId",
      "ParameterValue": "arn:aws:rds:us-east-2:314602174043:cluster-snapshot:manual-snap-201802280852",
    }
    ~~~~
1. Launch a new stack using the updated `test.parms.json` file by doing somthing similar to the following:
    ~~~~
    aws --region us-west-2 cloudformation create-stack \
        --stack-name RedMineTest00 --disable-rollback \
        --capabilities CAPABILITY_NAMED_IAM \
        --template-url Templates/make_RedMine_parent-autoscale-EFS.tmplt.json \
        --parameters file://test.parms.json
    ~~~~

Assuming all goes as expected, a functional duplicate of the "production" RedMine service will be created in the target region. This instance will have all of the same authentication elements as the production instance. 

### Caveats

If the production RedMine had any attachments or other types of file uploads, these will be missing on the testing instance. Attachments are stored on the EFS service and are not automatically migrated. If these attachments are needed for testing purposes, it will be necessary to manually copy the contents of the production RedMine's EFS shares to the testing RedMine's equivalent EFS shares.
