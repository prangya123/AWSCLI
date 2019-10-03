#!/bin/bash
 
# $Id: //depot/releng/build/ec2/
# $DateTime: 
# $Author: Prangya P Kar
# $Change: 
# `2019-06-01`
export WORKDIR=$(pwd)
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/local/bin:${WORKDIR}:${WORKDIR}/aws:${WORKDIR}/aws/bin:.
 
 
echo $0
 
### colors stuff
CRESET=
CRED=
CGREEN=
CYELLOW=
CBLUE=
if [ -t 1 -a "$NOCOLOR" != "1" ]; then
    TPUT_COLOR=0
    if tput setaf 1 > /dev/null 2>&1; then
        if [ "${JENKINS_URL}" = "" ]; then
            TPUT_COLOR=1
        else
            JENKINS_COLOR=${JENKINS_COLOR:-1}
        fi
    fi
    if [ "$TPUT_COLOR" = "1" ]; then
        tput sgr0
        CRESET=$(tput sgr0)
        CRED=$(tput setaf 1)
        CGREEN=$(tput setaf 2)
        CYELLOW=$(tput setaf 3)
        CBLUE=$(tput setaf 4)
        tput sgr0
    fi
fi
if [ "$JENKINS_COLOR" = "1" ]; then
    CRESET="\033[m"
    CRED="\033[1;31m"
    CGREEN="\033[1;32m"
    CYELLOW="\033[1;33m"
    CBLUE="\033[1;34m"
fi
 
usage() {
    cat <<EOS
 
Usage:
    $0 LaunchTime [REGION]
    
    LaunchTime : YYYY-MM-DD, 2019-06-01
    This will find all instances before LaunchTime
    REGION: us-west-2 
EOS
}
 
 
LaunchTime=$1
REGION=$2
#region=us-west-2
#check region
if [ "$REGION" = "" ]; then
    printf "${CRED}: Missing REGION${CRESET}\n"
    REGION=us-west-2
    printf "${CYELLOW}: Set to default REGION $REGION ${CRESET}\n"
else
    printf "${CYELLOW}: Set to REGION $REGION ${CRESET}\n"
fi
 
region=$REGION
 
if [ "$LaunchTime" = "" ]; then
    printf "${CRED}ERROR: Missing LaunchTime${CRESET}\n"
    usage
    exit 1
else
    printf "${CYELLOW}: Select all instances before LaunchTime i.e. $LaunchTime ${CRESET}\n"
fi
  
export AWSCMD="aws --no-paginate --color off"
export EC2CMD="${AWSCMD} ec2" 
SLEEP_TIME=10
  
#log files
LIST_INSTANCESs_FILE=logs/delete-tagged_stopped_instances_$$.txt #tag_stop_instances_$$.txt
LIST_TAGGED_IDs_FILE=logs/To_delete-tagged_instances.txt

#clean-up
/bin/rm -f logs/delete-tagged_stopped_instances_*.txt
/bin/rm -f $LIST_TAGGED_IDs_FILE
 
#Check dir logs:
if [ -d $WORKDIR/logs ]
then
    echo "Directory exists"
else
    mkdir -p $WORKDIR/logs
    echo "Created dir logs"
fi
 

ACCOUNT=`aws iam list-account-aliases --query 'AccountAliases[0]' --output text`

echo "AWS account is : $ACCOUNT"

$EC2CMD describe-instances  \
--region $REGION \
--query "Reservations[].Instances[?LaunchTime<='${LaunchTime}'][].{id: InstanceId, launched: LaunchTime}" \
--output text | sort > $LIST_INSTANCESs_FILE
 
if [ ! -s $LIST_INSTANCESs_FILE ]; then
    echo
    echo "Nothing to do"
    echo
    #/bin/rm -f $LIST_INSTANCESs_FILE  #UNCOMMENT
    exit 0
fi
 
COUNT=0 
while read INSTANCE_ID LAUNCH_TIME
do
    echo
    echo "*** Processing instance id $INSTANCE_ID ***"
    INAME=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[Tags[?Key==\`Name\`].Value]" --output text)
    LAUNCHTIME=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[LaunchTime]" --output text)
    #LAUNCHTIME_EPOCH=`date --utc --date="${LAUNCHTIME}" +%s`
    
    printf "${CYELLOW}: Instance name: $INAME ${CRESET}\n"
    printf "${CYELLOW}: Launch time: $LAUNCHTIME ${CRESET}\n"
    #printf "${CYELLOW}: Launch time: $LAUNCHTIME ($LAUNCHTIME_EPOCH)${CRESET}\n"
    
    echo "*** Processing fe_common.owner_accountname $INSTANCE_ID ***"
    EMAIL_ID=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].Tags[?Key==`fe_common.owner_accountname`].Value[]' --output text)
    EMAIL_ID=`echo $EMAIL_ID|tr '[:upper:]' '[:lower:]'`
    printf "${CYELLOW}: fe_common.owner_accountname name: $EMAIL_ID ${CRESET}\n"
    
    echo "*** Processing tag ReadytoTerminate $INSTANCE_ID ***"
    ReadytoTerminateTag=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].Tags[?Key==`ReadytoTerminate`].Value[]' --output text)
    printf "${CYELLOW}: ReadytoTerminateTag: $ReadytoTerminateTag ${CRESET}\n"

    echo "*** Processing tag EmailSent $INSTANCE_ID ***"
    EmailSentTag=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].Tags[?Key==`EmailSent`].Value[]' --output text)    
    printf "${CYELLOW}: Num of Email sent: $EmailSentTag ${CRESET}\n"

    #stopping if instance is running.
    StateTransitionReason=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[StateTransitionReason]" --output text)
    printf "${CYELLOW}: StateTransitionReason: $StateTransitionReason ${CRESET}\n" 

    #stopping if instance is running.
    STATUS=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[State.Name]" --output text)
    #echo $STATUS
    if [ "$STATUS" = "stopped" ]; then
            echo "$INSTANCE_ID status is: $STATUS"
            echo "Instance ready for termination"
            echo "writting instance details into $LIST_TAGGED_IDs_FILE"
            echo "aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
            
            #aws ec2 terminate-instances --instance-ids $INSTANCE_ID
            STATUS2=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[State.Name]" --output text)
            echo "$INSTANCE_ID,$STATUS,$INAME,$EMAIL_ID,$ReadytoTerminateTag,$EmailSentTag,$StateTransitionReason,$LAUNCHTIME,$ACCOUNT,$region"|tee -a $LIST_TAGGED_IDs_FILE
            # if [ "$STATUS2" = "shutting-down" ]; then
            #     echo "$INSTANCE_ID is shutting-down, status :$STATUS2"
            #     echo "$INSTANCE_ID','$STATUS','INAME','EMAIL_ID','ReadytoTerminateTag','$EmailSentTag','$StateTransitionReason','LAUNCHTIME','$ACCOUNT','$region" >>LIST_TAGGED_IDs_FILE
            # fi
    else
        if [ "$STATUS" = "running" ]; then
            echo "INSTANCE_ID status is: $STATUS , no need to terminate."
        
        elif [ "$STATUS" = "stopping" -o "$STATUS" = "pending" ]; then
            echo "INSTANCE_ID status is: $STATUS , no need to terminate."
            sleep $SLEEP_TIME
        fi
        
    fi

 
    COUNT=$(($COUNT + 1))
 
done <${LIST_INSTANCESs_FILE}
 
#echo
#/bin/rm -f $LIST_INSTANCESs_FILE
 
echo "No. of Instances before LaunchTime : `cat ${LIST_INSTANCESs_FILE}|wc -l` "
echo "No. of Instances processed : $COUNT "
