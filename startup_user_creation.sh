#!/bin/bash

# slight dodgy hack to make sure everything has started up
sleep 120

# defaults
INSTALL_EMAIL="ht2testadmin@ht2labs.com"
INSTALL_ORG="testOrg"
CRED_FILE=/home/ubuntu/ll_credentials.txt
LOCAL_PATH=/usr/local/learninglocker/current
INSTALL_PATH_FILE=/etc/learninglocker/install_path
INSTALL_LOG=/var/log/learninglocker/user_setup.log

if [[ ! -d /home/ubuntu ]]; then
    CRED_FILE=/usr/local/learninglocker/ll_credentials.txt
fi


# get the local path from the config
if [[ -f $INSTALL_PATH_FILE ]]; then
    LOCAL_PATH=$(cat $INSTALL_PATH_FILE)
fi

# generate password
if [[ `command -v pwgen` ]]; then
    INSTALL_PASSWD=`pwgen 12 1`
elif [[ `command -v pwmake` ]]; then
    INSTALL_PASSWD=`pwmake 64`
else
    INSTALL_PASSWD="ChangeMeN0w"
fi

CHK=$(cd $LOCAL_PATH/webapp; node cli/dist/server createSiteAdmin "$INSTALL_EMAIL" "$INSTALL_ORG" "$INSTALL_PASSWD" 2>>$INSTALL_LOG | grep "User not found")

if [[ $CHK != "" ]]; then
    echo "[UC] $CHK" >> $INSTALL_LOG
    echo "[UC] creating user $INSTALL_EMAIL" >> $INSTALL_LOG
    if [[ ! -f $CRED_FILE ]]; then
        echo "[UC] creating credential file $CRED_FILE" >> $INSTALL_LOG
        touch $CRED_FILE 2>>$INSTALL_LOG
    fi
    echo "Created user. Writing details to $CRED_FILE"
    echo "email    : $INSTALL_EMAIL" > $CRED_FILE
    echo "org      : $INSTALL_ORG" >> $CRED_FILE
    echo "password : $INSTALL_PASSWD" >> $CRED_FILE

    # get metadata
    aws_region="`wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone`"
    aws_ami="`wget -q -O - http://169.254.169.254/latest/meta-data/ami-id`"
    # adding call to install checker
    chk="`curl lrnloc.kr/AMIinstall`"

else
    echo "[UC] User $INSTALL_EMAIL already exists, not creating" >> $INSTALL_LOG
fi
