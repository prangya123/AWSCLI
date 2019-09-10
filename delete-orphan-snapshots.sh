#!/bin/bash
 
#set -e
#  Orphaned Snapshots costing you $$$
#  
WORKDIR=$(pwd)
 
usage() {
    cat <<EOS
 
Usage:
    find the snapshots which are orphan i.e. the AMI's are already de-registered.
 
EOS
 
}
 
 
AWSCMD="aws --no-paginate --color off"
EC2CMD="${AWSCMD} ec2"
DRYRUN="--dry-run"
 
AWS_ACCOUNT_ID=self
REGION=<DEFAULT_REGION>

 
if [ "$REGION" == "" ]; then
    REGION=$($AWSCMD configure list | awk '$1 == "region" {print $2}' | head -1)
fi
 
 
 
/bin/rm -f all_snapshots snapshots_attached_to_ami
$EC2CMD describe-snapshots --owner-ids self --filters Name=tag-key,Values=<TAG-KEY> Name=tag-value,Values=<TAG-VALUE> Name=tag-key,Values=<TAG-KEY> Name=tag-value,Values='REGEXP-*' --query Snapshots[*].SnapshotId --output text | tr '\t' '\n' | sort > $WORKDIR/all_snapshots
$EC2CMD describe-images --region $REGION --filters Name=tag-key,Values=<TAG-KEY> Name=tag-value,Values=<TAG-VALUE> Name=tag-key,Values=<TAG-KEY> Name=tag-value,Values='REGEXP-*' Name=state,Values=available --owners self --query "Images[*].BlockDeviceMappings[*].Ebs.SnapshotId" --output text | tr '\t' '\n' | sort > $WORKDIR/snapshots_attached_to_ami
 
#grep -Fxf $WORKDIR/all_snapshots $WORKDIR/snapshots_attached_to_ami > file-comm.txt
diff $WORKDIR/all_snapshots $WORKDIR/snapshots_attached_to_ami | grep '< ' | sed 's/< //g'  > ORPHANED_SNAPSHOT_IDS
 
cat ORPHANED_SNAPSHOT_IDS | while read SNAPSHOT_ID
do
  echo "$EC2CMD --region $REGION delete-snapshot --snapshot-id $SNAPSHOT_ID"
  #$EC2CMD --region $REGION delete-snapshot --snapshot-id $SNAPSHOT_ID
done
 
