#!/bin/bash
 
 
export WORKDIR=$(pwd)
 
if [ "$REGION" = "" ]; then
   REGION=$1
fi
REGION=${REGION:=us-west-2}
 
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/local/bin:${WORKDIR}:${WORKDIR}/aws:${WORKDIR}/aws/bin:.
 
echo -e "\nUsage: $0 [region]\n"
 
export AWSCMD="aws --no-paginate --color off"
export EC2CMD="${AWSCMD} ec2"
# 10800=3 hrs
export MAX_TSDIFF=${MAX_TSDIFF:=10800}
 
LIST_FILE=stale_instances_$$.txt
 
(set -x ; $EC2CMD describe-instances --region $REGION --filters "Name=instance-state-name,Values=running,shutting-down,stopping,stopped" "Name=key-name,Values=RE-*" "Name=tag-key,Values=Builder" "Name=tag-value,Values=RelEng" --query "Reservations[*].Instances[*].[InstanceId,State,StateTransitionReason,LaunchTime,Tags[?Key==\`Name\`].Value,KeyName]" )
 
/bin/rm -f $LIST_FILE
$EC2CMD describe-instances --region $REGION --filters "Name=instance-state-name,Values=running,shutting-down,stopping,stopped" "Name=key-name,Values=RE-*" "Name=tag-key,Values=Builder" "Name=tag-value,Values=RelEng" --query "Reservations[*].Instances[*].[InstanceId]" --output text > $LIST_FILE
 
if [ ! -s $LIST_FILE ]; then
    echo
    echo "Nothing to do"
    echo
    /bin/rm -f $LIST_FILE
    exit 0
fi
 
CURRENTTS=`date +%s`
CURRENTTS_STR=`date --date=@${CURRENTTS}`
CURRENTTS_UTC_STR=`date --utc --date=@${CURRENTTS}`
echo
echo "Current timestamp:"
echo "    $CURRENTTS"
echo "    ${CURRENTTS_STR}"
echo "    ${CURRENTTS_UTC_STR}"
echo "Max elapsed time allowed is $MAX_TSDIFF seconds."
echo
 
COUNT=0
 
while read INSTANCE_ID
do
    echo
    echo "*** Processing instance id $INSTANCE_ID ***"
    INAME=$($EC2CMD describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].[Tags[?Key==\`Name\`].Value]" --output text)
    if [ "$INAME" = "" ]; then
        echo "Skipping. No tag 'Name'"
        continue
    fi
    LAUNCHTIME=$($EC2CMD describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].[LaunchTime]" --output text)
    LAUNCHTIME_EPOCH=`date --utc --date="${LAUNCHTIME}" +%s`
    echo "Instance name: $INAME"
    echo "Launch time: $LAUNCHTIME ($LAUNCHTIME_EPOCH)"
 
    TSDIFF=$(($CURRENTTS - $LAUNCHTIME_EPOCH))
    echo "Elapsed time: $TSDIFF seconds"
    if [ "$TSDIFF" != "" -a "$TSDIFF" -ge "${MAX_TSDIFF}" ]; then
        echo "Elapsed time of $TSDIFF seconds more than ${MAX_TSDIFF} seconds. Terminating..."
 
        echo
        (set -x ; $EC2CMD terminate-instances --region $REGION --instance-ids ${INSTANCE_ID} --output text)
        echo
 
        KEYNAME=$($EC2CMD describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].[KeyName]" --output text)
        if [ "$KEYNAME" != "" ]; then
            echo "Deleting key: $KEYNAME"
            (set -x ; $EC2CMD delete-key-pair --region $REGION --key-name "${KEYNAME}" )
            echo
        fi
        echo
 
        VOLUME_IDS=$($EC2CMD describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].[BlockDeviceMappings[*].Ebs.VolumeId]" --output text)
        for VOLUME_ID in $VOLUME_IDS
        do
            echo "Deleting volume: $VOLUME_ID"
            (set -x ; $EC2CMD delete-volume --region $REGION --volume-id $VOLUME_ID)
            echo
        done
 
        COUNT=$(($COUNT + 1))
    fi
    echo
done <${LIST_FILE}
 
echo
/bin/rm -f $LIST_FILE
echo "Exit $COUNT"
exit $COUNT
