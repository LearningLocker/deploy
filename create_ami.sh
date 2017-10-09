#!/bin/bash
#
# Copyright (C) 2017 ht2labs
#
# This program is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see http://www.gnu.org/licenses/.
#
#
# This script will create a directory in S3 with the files relevant for creating an AMI.
# The actual registration process may take place elsewhere


#########################################################################################################
# defaults                                                                                              #
#########################################################################################################
PM2_USER=learninglocker                         # user that pm2 is running as
OS_VERSION=Ubuntu
AWS_MOUNT_POINT=/mnt                            # used for copying data to before pushing - essentially temp storage
AWS_ARCH="x86_64"
AMI_NAME="llv2-0.0.1"
DEFAULT_BUCKET_PREFIX="ll-public-ami"
DEFAULT_REGION="eu-west-1"
CLI_VARS=false
JUSTDOIT=false
AWS_S3_SECRET_KEY=
AWS_S3_ACCESS_KEY=
AWS_REGION=
AMI_NAME=
AMI_DESC=
BUCKET_PREFIX=
VISIBILITY="private"
OUTPUT_LOG=/tmp/ami_build.log
ERROR_LOG=$OUTPUT_LOG
INSTANCE_TYPE="instance"


#########################################################################################################
# functions                                                                                             #
#########################################################################################################
function show_help ()
{
    echo "I need to render help text here"
    exit 1
}


function print_spinner ()
{
    pid=$!
    s='-\|/'
    i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ));
        printf "\b${s:$i:1}";
        sleep .1;
    done
    printf "\b.";

    if [[ $1 == true ]]; then
        echo "done!"
    fi
}


#########################################################################################################
# Get variables from CLI                                                                                #
#########################################################################################################
while getopts ":h:p:n:d:r:a:k:s:y:t:v:" OPT; do
    case "$OPT" in
        h)
            show_help
        ;;
        p)
            BUCKET_PREFIX=$OPTARG
        ;;
        n)
            AMI_NAME=$OPTARG
        ;;
        d)
            AMI_DESC=$OPTARG
        ;;
        r)
            AWS_REGION=$OPTARG
        ;;
        a)
            AWS_ACCOUNT_ID=$OPTARG
        ;;
        k)
            AWS_S3_ACCESS_KEY=$OPTARG
        ;;
        s)
            AWS_S3_SECRET_KEY=$OPTARG
        ;;
        y)
            JUSTDOIT=true
        ;;
        t)
            if [[ $OPTARG == "instance" ]]; then
                INSTANCE_TYPE="instance"
            elif [[ $OPTARG == "ebs" ]]; then
                INSTANCE_TYPE="ebs"
            else
                echo "Invalid AMI type of '${OPTARG}' - needs to be 'instance' or 'ebs'"
                exit 1
            fi
        ;;
        v)
            if [[ $OPTARG == "public" ]]; then
                VISIBILITY="public"
            fi
        ;;
        \?)
            echo "Invalid Option -${OPTARG}"
            exit 1
        ;;
    esac
done
if [[ $AMI_NAME != "" ]]; then
    CLI_VARS=true

    # use defaults if needed
    if [[ $AWS_REGION == "" ]]; then
        AWS_REGION=$DEFAULT_REGION
    fi
    if [[ $BUCKET_PREFIX == "" ]]; then
        BUCKET_PREFIX=$DEFAULT_BUCKET_PREFIX
    fi
    BUCKET_NAME="${BUCKET_PREFIX}-$(date +%Y-%m-%d-%H%M)"

    # validate we have the minimum needed
    if [[ $AWS_ACCOUNT_ID == "" ]] || [[ $AWS_S3_ACCESS_KEY == "" ]] || [[ $AWS_S3_SECRET_KEY == "" ]]; then
        CLI_VARS=false
    fi

    if [[ $AMI_DESC == "" ]]; then
        AMI_DESC=$AMI_NAME
    fi
fi

if [[ $CLI_VARS == true ]]; then
    echo " Going to create an AMI with the following information:"
    echo "     AMI Name   : $AMI_NAME"
    echo "     AMI Desc   : $AMI_DESC"
    echo "     AWS Region : $AWS_REGION"
    echo "     S3 Bucket  : $BUCKET_NAME"
    echo "     Visibility : $VISIBILITY"
    if [[ $JUSTDOIT == false ]]; then
        echo "[*] Press any key to continue (or ctrl-c to exit)"
        read -r -s -n 1 c
    fi
fi


#########################################################################################################
# Ask questions of user                                                                                 #
#########################################################################################################
if [[ $CLI_VARS == false ]]; then
    while true; do
        echo "Is this an instance based image [i] or ebs backed [e] [i|e] (press enter for the default of ebs)"
        read -r -s -n 1 n
        if [[ $n == "e" ]] || [[ $n == "" ]]; then
            INSTANCE_TYPE="ebs"
        elif [[ $n == "i" ]]; then
            INSTANCE_TYPE="instance"
        fi
    done

    if [[ $INSTANCE_TYPE == "instance" ]]; then
        echo -n "Enter the bucket prefix (press enter for the default of '$DEFAULT_BUCKET_PREFIX'): "
        read -r BUCKET_PREFIX
    fi
    if [[ $BUCKET_PREFIX == "" ]]; then
        BUCKET_PREFIX=$DEFAULT_BUCKET_PREFIX
    fi
    echo -n "Enter the name for the AMI, eg: llv2-1.0.0: "
    read -r AMI_NAME
    echo -n "Enter the description of the AMI (pressing enter will copy the name to this field)"
    read -r AMI_DESC
    if [[ $AMI_DESC == "" ]]; then
        AMI_DESC=$AMI_NAME
    fi
    BUCKET_NAME="${BUCKET_PREFIX}-$(date +%Y-%m-%d-%H%M)"
    echo "We're going to create a ami called '$AMI_NAME' pointing to the S3 bucket of '$BUCKET_NAME'. Is this correct ? [y|n]"
    while true; do
        read -r -s -n 1 n
        if [[ $n == "y" ]] || [[ $n == "Y" ]]; then
            break
        elif [[ $n == "n" ]] || [[ $n == "N" ]]; then
            echo "Ok, Exiting"
            exit 0
        fi
    done
    echo -n "Enter the region to upload to (press enter for the default of '$DEFAULT_REGION')"
    read -r AWS_REGION
    if [[ $AWS_REGION == "" ]]; then
        AWS_REGION=$DEFAULT_REGION
    fi
    echo -n "Please enter the AWS Account Id: "
    read -r AWS_ACCOUNT_ID
    echo -n "Please enter the S3 access key: "
    read -r AWS_S3_ACCESS_KEY
    echo -n "Please enter the S3 secret key: "
    read -r AWS_S3_SECRET_KEY

    while true; do
        echo -n "do you want this AMI to be public (o) or private (p) [o|p] (press enter for the default of 'p')"
        read -r -s -n 1 n
        if [[ $n == "" ]]; then
            n="p"
        fi
        if [[ $n == "o" ]]; then
            VISIBILITY="public"
            break
        elif [[ $n == "p" ]]; then
            VISIBILITY="private"
            break
        fi
    done
fi


#########################################################################################################
# get AWS / system info                                                                                 #
#########################################################################################################
if [[ $OS_VERSION == "Ubuntu" ]]; then
    OS_USER=ubuntu
fi
# get IP address for use in uploading required certs
EC2_IPADDR="`wget -q -O - http://169.254.169.254/latest/meta-data/public-ipv4 || die \"can\'t get Public IP address $?\"`"
INSTANCE_ID="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id/ || die \"can\'t get Instance-ID address $?\"`"



#########################################################################################################
# get cert & keyfile                                                                                    #
#########################################################################################################
if [[ $INSTANCE_TYPE == "instance" ]]; then
    if [[ ! -d /tmp/cert ]]; then
        mkdir -p /tmp/cert
        chown $OS_USER:$OS_USER -R /tmp/cert
    else
        DIR_USER=`ls -l /tmp/cert | awk '{print $3}'`
        if [[ $DIR_USER != $OS_USER ]]; then
            chown $OS_USER:$OS_USER -R /tmp/cert
        fi
    fi

    cert_file=""
    key_file=""
    if [[ -f /tmp/cert/cert*.pem ]]; then
        cert_file=$(ls -1 /tmp/cert/cert*.pem)
    fi
    if [[ -f /tmp/cert/pk*.pem ]]; then
        key_file=$(ls -1 /tmp/cert/pk*.pem)
    fi

    if [ ! -r "$cert_file" -o ! -r "$key_file" ]; then
        echo "Now transfer the private key and x.509 certificate by running:"
        echo "    scp -i MY_SSH_KEY EC2_X509_CERT EC2_PRIVATE_KEY ${OS_USER}@${EC2_IPADDR}:/tmp/cert/"
        echo "on your local machine - obviously replacing the paths to the various files"
        echo "  the cert file should be called cert*.pem and the private key called pk*.pem"
        echo
        echo "    our standard form of this is:"
        echo "    scp -i \$EC2_KEY \$AWS_X509_CERT \$AWS_X509_PK ${OS_USER}@${EC2_IPADDR}:/tmp/cert/"
        echo
        echo "You must have local access to these keys to continue. Press y when ready."
        while true; do
            read -r -s -n 1 n
            if [[ $n == "y" ]] || [[ $n == "Y" ]]; then
                echo "[*] Ok, continuing"
                break
            fi
        done
        echo -n "[*] Checking keys... "
        cert_file=$(ls -1 /tmp/cert/cert*.pem)
        key_file=$(ls -1 /tmp/cert/pk*.pem)
        if [ ! -r "$cert_file" -o ! -r "$key_file" ]; then
            echo "Key and/or certificate file missing. Aborting."
            exit 0
        else
            echo "Looks ok, continuing"
        fi
    else
        echo "[*] key & cert file found in /tmp/cert and appear valid - continuing"
    fi
fi

#########################################################################################################
# base system installs                                                                                  #
#########################################################################################################
# install software
if [[ $OS_VERSION == "Ubuntu" ]]; then

    echo -n "[*] running package list update...."
    apt-get update >>$OUTPUT_LOG 2>>$ERROR_LOG &
    print_spinner true

    echo "[*] running dist-upgrade...."
    apt-get dist-upgrade
    #print_spinner true

    echo -n "[*] installing required software...."
    apt-get -y install ec2-ami-tools >>$OUTPUT_LOG 2>>$ERROR_LOG &
    print_spinner true
else
    echo "[*] unsupported OS - exiting"
    exit 0
fi


# Stop services prior to bundling the image
echo "[*] stopping services prior to bundling"
service nginx stop
service pm2-${PM2_USER} stop


#########################################################################################################
# Instance Prep                                                                                         #
#########################################################################################################
if [[ $INSTANCE_TYPE == "instance" ]]; then
    #########################################################################################################
    # Create bundle directory                                                                               #
    #########################################################################################################

    # mount secondary EBS volume if available
    mkdir -p $AWS_MOUNT_POINT
    if mount | grep -q "$AWS_MOUNT_POINT"; then
        mount $AWS_MOUNT_POINT
    fi
    # create the dir
    mkdir -p $AWS_MOUNT_POINT/bundle/image
    chown $OS_USER:$OS_USER -R $AWS_MOUNT_POINT/bundle
    cd $AWS_MOUNT_POINT/bundle


    #########################################################################################################
    # cleanup prior to bundling                                                                             #
    #########################################################################################################
    # remove old bundling files
    if [[ -d $AWS_MOUNT_POINT/bundle/image ]]; then
        REMOVE_BUNDLE=true
        if [[ -f $AWS_MOUNT_POINT/bundle/image/image.manifest.xml ]]; then
            REMOVE_BUNDLE=false
            echo "[*] not removing old bundle as it looks good - you'll need to remove manually if you want to rebuild"
        fi
        if [[ $REMOVE_BUNDLE == true ]]; then
            echo -n "[*] removing old bundle files...."
            rm -rf $AWS_MOUNT_POINT/bundle/image
            mkdir -p $AWS_MOUNT_POINT/bundle/image
            echo "done!"
        fi
    fi
fi


#########################################################################################################
# Delete temp files and clean up                                                                        #
#########################################################################################################
echo "[*] cleaning up old and unneeded data"
if [[ $OS_VERSION == "Ubuntu" ]]; then
    apt-get -q 2 -y autoremove
    apt-get clean
fi

rm -rf /root/.viminfo /root/.lesshst /root/config/* /root/.bash_history /var/spool/mail/* /root/.nano_history
rm -rf ${PM2_USER}/.bash_history
rm -rf ${PM2_USER}/.nano_history
rm -rf ${OS_USER}/.bash_history
rm -rf ${OS_USER}/.nano_history
# get rid of cron
for a in hourly daily weekly monthly;
    do rm -rf /etc/cron.$a/*;
done
rm -rf /var/www/*
# finally clear history
set +o history
history -c


#########################################################################################################
# Instance specific - create bundle                                                                     #
#########################################################################################################
if [[ $INSTANCE_TYPE == "instance" ]]; then
    echo "[*] Creating bundle, can take 5-10 minutes"
    if [[ -f $AWS_MOUNT_POINT/bundle/image/image.manifest.xml ]]; then
        echo "      not creating bundle as already exists"
    else
        ec2-bundle-vol -c $cert_file -k $key_file -u $AWS_ACCOUNT_ID -d $AWS_MOUNT_POINT/bundle/image -r $AWS_ARCH
    fi
    echo ""
    echo "[*] Does everything look like it completed successfully [y|n] ?"
    read -r -s -n 1 n
    while true; do
        if [[ $n == "y" ]] || [[ $n == "Y" ]]; then
            echo "      Ok, continuing"
            break
        elif [[ $n == "n" ]] || [[ $n == "N" ]]; then
            echo "      can't continue then - exiting"
            exit 0
        fi
    done
fi


#########################################################################################################
# determine regions / zones to upload and register to                                                   #
#########################################################################################################
# stupidly needed to map ec2 zones to S3 regions as they're not a 1-2-1 map
S3_REGIONS=()
REGIONS=$(echo $AWS_REGION | tr "," "\n")
for REGION in $REGIONS; do
    #EU,US,us-gov-west-1,us-west-1,us-west-2,ap-southeast-1,ap-southeast-2,ap-northeast-1,sa-east-1

    # US west
    if [[ $REGION == "us-west-1" ]]; then
        S3_REGIONS+=('us-west-1')
    elif [[ $REGION == "us-west-2" ]]; then
        S3_REGIONS+=('us-west-2')
    # US east
    elif [[ $REGION == "us-east-1" ]]; then
        S3_REGIONS+=('US')
    elif [[ $REGION == "us-east-2" ]]; then
        S3_REGIONS+=('US')
    # eu
    elif [[ $REGION == "eu-west-1" ]]; then
        S3_REGIONS+=('EU')
    elif [[ $REGION == "eu-central-" ]]; then
        S3_REGIONS+=('EU')
    elif [[ $REGION == "eu-west-2" ]]; then
        S3_REGIONS+=('EU')
    # ap northeast
    elif [[ $REGION == "ap-northeast-1" ]]; then
        S3_REGIONS+=('ap-northeast-1')
    # ap southeast
    elif [[ $REGION == "ap-southeast-1" ]]; then
        S3_REGIONS+=('ap-southeast-1')
    elif [[ $REGION == "ap-southeast-2" ]]; then
        S3_REGIONS+=('ap-southeast-2')
    # sa east
    elif [[ $REGION == "sa-east-1" ]]; then
        S3_REGIONS+=('sa-east-1')
    # default / failure case
    else
        echo "AWS Region of $REGION is unsupported"
        exit
    fi
done

# dedupe array we just created
S3_REGIONS=($(echo "${S3_REGIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))


#########################################################################################################
# Instance specific - Upload bundle to S3                                                               #
#########################################################################################################
if [[ $INSTANCE_TYPE == "instance" ]]; then
    for S3_REGION in $S3_REGIONS; do
        echo "[*] Uploading bundle to S3 for region: $S3_REGION"
        cd $AWS_MOUNT_POINT/bundle/image
        ec2-upload-bundle -b $BUCKET_NAME -m image.manifest.xml -a $AWS_S3_ACCESS_KEY -s $AWS_S3_SECRET_KEY --location $S3_REGION
        echo ""
        echo "[*] Does everything look like it completed successfully [y|n] ?"
        read -r -s -n 1 n
        while true; do
            if [[ $n == "y" ]] || [[ $n == "Y" ]]; then
                echo "     Ok, continuing"
                break
            elif [[ $n == "n" ]] || [[ $n == "N" ]]; then
                echo "     can't continue then - exiting"
                exit 0
            fi
        done
    done
fi


#########################################################################################################
# Install creation software                                                                             #
#########################################################################################################
# install the ec2 tools now - don't do it before, no point it being part of the bundle
if [[ $OS_VERSION == "Ubuntu" ]]; then
    echo -n "[*] installing ec2 bundling tools...."
    apt-get -y install ec2-api-tools >>$OUTPUT_LOG 2>>$ERROR_LOG &
    print_spinner true
fi

#########################################################################################################
# Register Bundle                                                                                       #
#########################################################################################################
for REGION in $REGIONS; do

    if [[ $INSTANCE_TYPE == "instance" ]]; then
        # INSTANCE
        echo "[*] Creating Instance AMI in region: $REGION"
        AMI_ID=$(ec2-register $BUCKET_NAME/image.manifest.xml -a x86_64 -n $AMI_NAME -O $AWS_S3_ACCESS_KEY -W $AWS_S3_SECRET_KEY --region $REGION --virtualization-type hvm | awk '{print $2}')
    elif [[ $INSTANCE_TYPE == "ebs" ]]; then
        # EBS
        echo "[*] Creating EBS AMI in region: $REGION"
        AMI_ID=$(ec2-create-image -O $AWS_S3_ACCESS_KEY -W $AWS_S3_SECRET_KEY --region $REGION -n "${AMI_NAME}" -d "${AMI_DESC}" --no-reboot $INSTANCE_ID | awk '{print $2}')
    fi

    if [[ $AMI_ID == "" ]]; then
        echo "[*] Error creating AMI - are you sure you started this instance in the same region you're trying to create it in?"
        continue
    fi
    echo "[*] registered AMI ID: $AMI_ID"

    # make the ami public
    if [[ $VISIBILITY == "public" ]]; then
        echo -n "[*] making AMI public"
        # have to go into a loop here to check if the image is created
        while true; do
            CHK=$(ec2-modify-image-attribute $AMI_ID -l --region $REGION -a all -O $AWS_S3_ACCESS_KEY -W $AWS_S3_SECRET_KEY 2>/dev/null | awk '{print $1}')
            if [[ $CHK == "launchPermission" ]]; then
                echo "done!"
                echo "[*] setting description to Name tag"
                ec2-create-tags $AMI_ID --region $REGION -O $AWS_S3_ACCESS_KEY -W $AWS_S3_SECRET_KEY --tag Name="${AMI_DESC}" 2>/dev/null
                break
            else
                echo -n "."
                sleep 10
            fi
        done
    else
        echo "[*] leaving AMI private"
    fi
done

echo "[*] All done!"

