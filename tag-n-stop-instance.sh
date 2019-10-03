#!/bin/bash
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
LIST_INSTANCESs_FILE=logs/tag_stop_instances_$$.txt #tag_stop_instances_$$.txt
LIST_TAGGED_IDs_FILE=logs/tagged_instances.txt
LIST_EMAIL_IDs_FILE=logs/email_ids.txt
EMAIL_ATTACHMENT_FILE=logs/instance_descriptions.txt
NO_OWNER_IDs_FILE=logs/no_owner_ids.txt
NO_OWNER_ATTRIBs_FILE=logs/no_owner_ids_detail.txt
TOTAL_EMAIL_ATTRIBS_FILE=logs/tag_stop_instances_details.txt.
EMAIL_BODY=tag-n-stop-instance-email-body1.html



#clean-up
/bin/rm -f logs/tag_stop_instances_*.txt
/bin/rm -f $LIST_TAGGED_IDs_FILE
/bin/rm -f $EMAIL_ATTACHMENT_FILE
/bin/rm -f $LIST_EMAIL_IDs_FILE
/bin/rm -f $NO_OWNER_IDs_FILE
/bin/rm -f $NO_OWNER_ATTRIBs_FILE
/bin/rm -f $TOTAL_EMAIL_ATTRIBS_FILE
 
sendEmail () {

    INSTANCE_ID1=$1
    ACCOUNT1=$2
    EMAIL_ID1=$3
    EMAIL_ATTACHMENT_FILE1=$4
    EMAIL_BODY1=$5

    echo "$1 , $2 , $3 , $4 , $5 "

    subject="ACTION NEEDED ***Instance $INSTANCE_ID1 of $ACCOUNT1 marked for Termination***"
    
    TO=$EMAIL_ID1,prangya.kar@***.com
    
    #set tag EmailSent to  0 or 1 or 2
    EmailSent_Count=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].Tags[?Key==`EmailSent`].Value[]' --output text)
    echo $EmailSent_Count

    if [ "$EmailSent_Count" = "1" ]; then
        echo "EmailSent_Count is :$EmailSent_Count, increasing the count to 2"

        echo "sending email to $TO for $INSTANCE_ID1"
        export EMAIL="do-not-reply@***.com" && mutt -e "set content_type=text/html" -s "$subject" $TO -a $EMAIL_ATTACHMENT_FILE < $EMAIL_BODY1
    
        (set -x ; $EC2CMD create-tags \
            --resources ${INSTANCE_ID} --tags Key=EmailSent,Value=2)

    elif [ "$EmailSent_Count" = "2" ]; then
        echo "EmailSent_Count is already:$EmailSent_Count"
        echo "EmailSent is already have tag = 2, so no need to tag again"

    else
        echo "EmailSent_Count is :$EmailSent_Count"
        echo "sending email to $TO for $INSTANCE_ID1"
        export EMAIL="do-not-reply@****.com" && mutt -e "set content_type=text/html" -s "$subject" $TO -a $EMAIL_ATTACHMENT_FILE < $EMAIL_BODY1
        (set -x ; $EC2CMD create-tags \
            --resources ${INSTANCE_ID} --tags Key=EmailSent,Value=1)
        
    fi
} 
 

#Check dir logs:
if [ -d $WORKDIR/logs ]
then
    echo "Directory exists"
else
    mkdir -p $WORKDIR/logs
    echo "Created dir logs"
fi
 


#$EC2CMD describe-instances  \
#--region $REGION --filters "Name=instance-state-name,Values=stopped" \
#--query 'Reservations[].Instances[?LaunchTime<=`2019-06-01`][].{id: InstanceId, type: InstanceType, launched: LaunchTime}'| sort >tag_stop_instances_$$.txt
 
ACCOUNT=`aws iam list-account-aliases --query 'AccountAliases[0]' --output text`


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
    
    #stopping if instance is running.
    STATUS=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].[State.Name]" --output text)
    #echo $STATUS
    if [ "$STATUS" = "stopped" ]; then
            echo "INSTANCE_ID status is: $STATUS"
    else
        if [ "$STATUS" = "running" ]; then
            echo "INSTANCE_ID status is: $STATUS , stopping-instance :"
            (set -x ; $EC2CMD stop-instances --instance-ids ${INSTANCE_ID} --output text)
            sleep $SLEEP_TIME
            OUTPUT=$($EC2CMD describe-instances --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].State.Name' --output text)
            echo "INSTANCE_ID status is: $OUTPUT "
        elif [ "$STATUS" = "stopping" -o "$STATUS" = "pending" ]; then
            echo "INSTANCE_ID status is: $STATUS , add sleep time :"
            sleep $SLEEP_TIME
        fi
        
    fi
 
    #tagging the instances as marked for deletion.
    (set -x ; $EC2CMD create-tags \
    --resources ${INSTANCE_ID} --tags Key=ReadytoTerminate,Value=yes)
 
    COUNT=$(($COUNT + 1))
 
done <${LIST_INSTANCESs_FILE}
 
#echo
#/bin/rm -f $LIST_INSTANCESs_FILE
 
echo "No. of Instances before LaunchTime : `cat ${LIST_INSTANCESs_FILE}|wc -l` "
echo "No. of Instances processed : $COUNT "
 
 
 
####email to owner_accountname
 
 
#LIST_EMAIL_IDs_FILE
$EC2CMD describe-instances  \
    --region $REGION \
    --filters Name=tag-key,Values=ReadytoTerminate Name=tag-value,Values=yes \
    --query 'Reservations[].Instances[].[InstanceId]' --output text> $LIST_TAGGED_IDs_FILE
 

 
while read INSTANCE_ID
do
    echo
    echo "*** Processing instance id $INSTANCE_ID ***"
    EMAIL_ID=$($EC2CMD describe-instances --region $REGION --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].Tags[?Key==`fe_common.owner_accountname`].Value[]' --output text)
    EMAIL_ID=`echo $EMAIL_ID|tr '[:upper:]' '[:lower:]'`
    
    echo $EMAIL_ID
 
    if [ "$EMAIL_ID" = "" ]; then
        echo "Tag fe_common.owner_accountname not set for instance $INSTANCE_ID"|tee -a $NO_OWNER_IDs_FILE >> $NO_OWNER_ATTRIBs_FILE
 
        $EC2CMD describe-instances  \
            --region $REGION \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].{ID: InstanceId, Type: InstanceType, Launched: LaunchTime, DeleteOnTermination: BlockDeviceMappings[0].Ebs.DeleteOnTermination,st: State.Name, AccountOwner : Tags[?Key==`fe_common.owner_accountname`], ReadytoTerminate : Tags[?Key==`ReadytoTerminate`] }' --output table |tee -a $NO_OWNER_ATTRIBs_FILE >/dev/null
        
        

        echo "set tag EmailSent to  0"
        (set -x ; $EC2CMD create-tags \
            --resources ${INSTANCE_ID} --tags Key=EmailSent,Value=0)
    


    elif [ "$EMAIL_ID" != *"****.com" ]; then
        echo "$EMAIL_ID, email id is invalid for instance $INSTANCE_ID"|tee -a $NO_OWNER_IDs_FILE >> $NO_OWNER_ATTRIBs_FILE
        
        $EC2CMD describe-instances  \
            --region $REGION \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].{ID: InstanceId, Type: InstanceType, Launched: LaunchTime, DeleteOnTermination: BlockDeviceMappings[0].Ebs.DeleteOnTermination,st: State.Name, AccountOwner : Tags[?Key==`fe_common.owner_accountname`], ReadytoTerminate : Tags[?Key==`ReadytoTerminate`] }' --output table |tee $EMAIL_ATTACHMENT_FILE >> $NO_OWNER_ATTRIBs_FILE 
        
 
        echo "call sendEmail"
        echo "sendEmail $INSTANCE_ID $ACCOUNT $EMAIL_ID $EMAIL_ATTACHMENT_FILE $EMAIL_BODY"
        sendEmail $INSTANCE_ID $ACCOUNT $EMAIL_ID $EMAIL_ATTACHMENT_FILE $EMAIL_BODY 
 
    else 
        echo "Sending email to $EMAIL_ID" |tee $LIST_EMAIL_IDs_FILE >>$TOTAL_EMAIL_ATTRIBS_FILE
        #echo "Sending email to $EMAIL_ID" |tee -a $TOTAL_EMAIL_ATTRIBS_FILE >/dev/null
        
        $EC2CMD describe-instances  \
            --region $REGION \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].{ID: InstanceId, Type: InstanceType, Launched: LaunchTime, DeleteOnTermination: BlockDeviceMappings[0].Ebs.DeleteOnTermination,st: State.Name, AccountOwner : Tags[?Key==`fe_common.owner_accountname`], ReadytoTerminate : Tags[?Key==`ReadytoTerminate`] }' --output table |tee $EMAIL_ATTACHMENT_FILE  >> $TOTAL_EMAIL_ATTRIBS_FILE 
        
        echo "call sendEmail"
        echo "sendEmail $INSTANCE_ID $ACCOUNT $EMAIL_ID $EMAIL_ATTACHMENT_FILE $EMAIL_BODY"
        sendEmail $INSTANCE_ID $ACCOUNT $EMAIL_ID $EMAIL_ATTACHMENT_FILE $EMAIL_BODY
 
    fi
 
done <${LIST_TAGGED_IDs_FILE}
