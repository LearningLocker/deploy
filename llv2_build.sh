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


#########################################
# GENERIC FUNCTIONS IRRESPECTIVE OF OS  #
#########################################
function checkCopyDir ()
{
    path=*
    if [ $1 ]; then
        path=$1/*
    fi

    if [[ $2 != "p" ]]; then
        echo -n "[LL] copying files..."
    fi
    for D in $path; do
        if [ -d "${D}" ]; then

            # checks to make sure we don't copy unneccesary files
            if [ $D == "node_modules" ]; then
                :
            elif [[ $D =~ .*/src$ ]]; then
                :
            #elif [ $D == "lib" ]; then
            #    :
            else
                # actual copy process (recursively)
                #echo "copying ${D}"
                if [[ ! -d ${TMPDIR}/${D} ]]; then
                    mkdir ${TMPDIR}/${D}
                fi
                # copy files
                for F in $D/*; do
                    if [ -f "${F}" ]; then
                        cp ${F} ${TMPDIR}/${D}/
                    fi
                done

                # go recursively into directories
                checkCopyDir $D p
            fi
        elif [ -f "${D}" ]; then
            cp $D ${TMPDIR}/${D}
        fi
    done
    if [[ $2 != "p" ]]; then
        echo "done"
    fi
}


function determine_os_version ()
{
    VERSION_FILE=/etc/issue.net
    REDHAT_FILE=/etc/redhat-release
    CENTOS_FILE=/etc/centos-release

    OS_SUBVER=false
    OS_VERSION=false
    OS_VNO=false

    # Make sure that the version is one we know about - if not, there'll likely be some strangeness with the package names
    if [ ! -f $VERSION_FILE ]; then
        echo "[LL] Couldn't determine version from $VERSION_FILE, file doesn't exist"
        exit 0
    fi
    RAW_OS_VERSION=$(cat $VERSION_FILE)
    if [[ $RAW_OS_VERSION == *"Amazon"* ]]; then
        OS_VERSION="Redhat"
        OS_SUBVER="Amazon"
        OS_ARCH=$(uname -a | awk '{print $12}')
    elif [[ $RAW_OS_VERSION == *"Debian"* ]]; then
        OS_VERSION="Debian"
    elif [[ $RAW_OS_VERSION == *"Ubuntu"* ]]; then
        OS_VERSION="Ubuntu"
        OS_VNO=`lsb_release -a | grep Release | awk '{print $2}'`
        if [[ $OS_VNO == "14.04" ]]; then
            NODE_OVERRIDE="6.x"
            PM2_OVERRIDE="ubuntu14"
        fi
    elif [[ -f $REDHAT_FILE ]]; then
        RAW_OS_VERSION=$(cat $REDHAT_FILE)
        OS_ARCH=$(uname -a | awk '{print $12}')
        # centos detection
        if [[ $RAW_OS_VERSION == *"CentOS"* ]]; then
            OS_VNO=$(cat $CENTOS_FILE | awk '{print $4}' | tr "." " " | awk '{print $1}')
            if [[ OS_VNO < 6 ]]; then
                echo "[LL] This version of CentOS isn't supported"
                exit 0
            fi
            OS_VERSION="Redhat"
            OS_SUBVER="CentOS"
        # RHEL
        elif [[ $RAW_OS_VERSION == *"Red Hat Enterprise Linux"* ]]; then
            OS_VERSION="Redhat"
            OS_SUBVER="RHEL"
            OS_VNO=$(cat $REDHAT_FILE | awk '{print $7}')
            echo
            echo "[LL] Sorry, we don't support RHEL at the moment"
            echo

        # Fedora
        elif [[ $RAW_OS_VERSION == *"Fedora"* ]]; then
            OS_VERSION="Redhat"
            OS_SUBVER="Fedora"
            OS_VNO=$(cat $REDHAT_FILE | awk '{print $3}')
            if [[ OS_VNO < 24 ]]; then
                echo
                echo "[LL] Sorry, we don't support this version of Fedora at the moment"
                echo
                exit 0
            fi

        # unknown redhat - bail
        else
            echo "[LL] Only set up for debian/ubuntu/centos at the moment I'm afraid - exiting"
            exit 0
        fi
    fi

    if [[ ! $OS_VERSION ]]; then
        echo "[LL] Couldn't determind version from $VERSION_FILE, unknown OS: $RAW_OS_VERSION"
        exit 0
    fi
}


#################################################################################
#                            LEARNINGLOCKER FUNCTIONS                           #
#################################################################################
# $1 is the path to the install directory
# $2 is the username to run under
function setup_init_script ()
{
    if [[ ! -d $1 ]]; then
        echo "[LL] path to install directory (${1}) wasn't a valid directory in setup_init_script(), exiting"
        exit 0
    fi

    echo -n "[LL] starting base processes...."
    su - $2 -c "cd $1; pm2 start all.json"
    echo "done"

    echo -n "[LL] starting xapi process...."
    su - $2 -c "cd ${1}/xapi; pm2 start xapi.json"
    echo "done"

    su - $2 -c "pm2 save"
    # I'm going to apologise here for the below line - for some reason when executing the resultant command
    # from the output of pm2 startup, the system $PATH doesn't seem to be set so we have to force it to be
    # an absolute path before running the command. It also needs to go into a variable and be run rather than
    # be run within backticks or the path still isn't substituted correctly. I know, right? it's a pain.
    PM2_STARTUP=$(su - $2 -c "pm2 startup $PM2_OVERRIDE | grep sudo | sed 's?sudo ??' | sed 's?\$PATH?$PATH?'")
    CHK=$($PM2_STARTUP)

    if [[ $OS_SUBVER == "fedora" ]]; then
        echo "=========================="
        echo "|         NOTICE         |"
        echo "=========================="
        echo "As you're on fedora, you may need to either turn off SELinux (not recommended) or add a rule to allow"
        echo "access to the PIDFile in /etc/systemd/system/pm2-${2}.service or the startup script will fail to run"
        echo
        echo "In addition, you'll need to punch a hole in your firewalld config or disable the firewall with:"
        echo "  service stop firewalld"
        echo
        echo
        sleep 5
    fi
}


function base_install ()
{
    # if the checkout dir exists, prompt the user for what to do
    DEFAULT_RM_TMP=y
    DO_BASE_INSTALL=true
    if [[ -d learninglocker_node ]]; then
        while true; do
            echo "[LL] Tmp directory already exists for checkout - delete [y|n] ? (enter is the default of ${DEFAULT_RM_TMP})"
            read n
            if [[ $n == "" ]]; then
                n=$DEFAULT_RM_TMP
            fi
            if [[ $n == "y" ]]; then
                rm -R learninglocker_node
                break
            elif [[ $n == "n" ]]; then
                echo "[LL] ok, not removing it - could cause weirdness though so be warned"
                sleep 5
                DO_BASE_INSTALL=false
                break
            fi
        done
    fi


    echo "[LL] Will now try and clone the git repo for the main learninglocker software. May prompt for user/pass and may take some time...."
    if [[ ! `command -v git` ]]; then
        echo
        echo "Can't find git - can't continue"
        echo
        exit 0
    fi

# release/v2.4.1 needs removing later
    # in a while loop to capture the case where a user enters the user/pass incorrectly
    if [[ $DO_BASE_INSTALL -eq true ]]; then
        while true; do
            #git clone -b ${GIT_BRANCH} https://github.com/LearningLocker/learninglocker_node learninglocker_node
            git clone https://github.com/LearningLocker/learninglocker_v2 learninglocker_node
            if [[ -d learninglocker_node ]]; then
                break
            fi
        done
    fi

    cd learninglocker_node
    if [[ ! -f .env ]]; then
        cp .env.example .env
        echo "[LL] Copied example env to .env - This will need editing by hand"
        sleep 5
    fi

    echo "[LL] running yarn install"
    CHK=$(yarn install)
    echo "[LL] adding pm2"
    CHK=$(yarn global add pm2@latest)
    echo "[LL] running yarn build-all"
    CHK=$(yarn build-all)
    echo "[LL] setting up pm2 logrotate"
    CHK=$(pm2 install pm2-logrotate)
    CHK=$(pm2 set pm2-logrotate:compress true)
    echo "[LL] running npm dedupe"
    CHK=$(npm dedupe)
}


function xapi_install ()
{
    echo "Will now try and clone the git repo for XAPI. Will prompt for user/pass and may take some time...."
    # not checking for presence of 'git' command as done in git_clone_base()

    DO_XAPI_CHECKOUT=true;
    if [[ -d xapi ]]; then
        DEFAULT_RM_TMP="y"
        while true; do
            echo "[LL] Tmp directory already exists for checkout of xapi - delete [y|n] ? (enter is the default of ${DEFAULT_RM_TMP})"
            read n
            if [[ $n == "" ]]; then
                n=$DEFAULT_RM_TMP
            fi
            if [[ $n == "y" ]]; then
                rm -R xapi
                break
            elif [[ $n == "n" ]]; then
                echo "[LL] ok, not removing it - could cause weirdness though so be warned"
                DO_XAPI_CHECKOUT=false
                sleep 5
                break
            fi
        done
    fi

    # do the checkout in a loop in case the users enters user/pass incorrectly
    if [[ $DO_XAPI_CHECKOUT -eq true ]]; then
        while true; do
            git clone https://github.com/LearningLocker/xapi-service.git xapi
            if [[ -d xapi ]]; then
                break
            fi
        done
    fi

    cd xapi/

    # sort out .env
    if [[ ! -f .env ]]; then
        cp .env.example .env
        echo "[LL] Copied example env to .env - This will need editing by hand"
        sleep 5
    fi

    # npm
    echo "[LL] running npm build...."
    while true; do
        CHK=$(npm install)
        if [[ $CHK == *"ERR"* ]]; then
            echo "It looks like there was a problem - please check the output above - do you want to retry [y|n|e] (default is 'y', 'e' to exit, 'n' to continue regardless)"
            while true; do
                read n
                if [[ $n == "" ]]; then
                    n="y"
                fi
                if [[ $n == "e" ]]; then
                    exit 0
                elif [[ $n == "y" ]]; then
                    break
                elif [[ $n == "n" ]]; then
                    break 2
                fi
            done
        else
            break
        fi
    done

    echo "[LL] running npm run build"
    while true; do
        CHK=$(npm run build)
        if [[ $CHK == *"ERR"* ]]; then
            echo "It looks like there was a problem - please check the output above - do you want to retry [y|n|e] (default is 'y', 'e' to exit, 'n' to continue regardless)"
            while true; do
                read n
                if [[ $n == "" ]]; then
                    n="y"
                fi
                if [[ $n == "e" ]]; then
                    exit 0
                elif [[ $n == "y" ]]; then
                    break
                elif [[ $n == "n" ]]; then
                    break 2
                fi
            done
        else
            break
        fi
    done

    cd ../
}



function nvm_install ()
{
    wget -qO- https://raw.githubusercontent.com/creationix/nvm/v0.33.2/install.sh | bash
}


# $1 is the file to reprocess
# $2 is the path to the install dir
# $3 is the log path - if not passed in we'll assume it's $2/logs/
# $4 is the pid path - if not passed in we'll assume it's $2/pids/
function reprocess_pm2 ()
{
    if [[ ! $1 ]]; then
        echo "[LL] no file name passed to reprocess_pm2"
        return
    elif [[ ! -f $1 ]]; then
        echo "[LL] file '${1}' passed to reprocess_pm2() appears to not exist."
        sleep 10
        return
    fi

    if [[ ! $2 ]]; then
        echo "[LL] no install path passed to reprocess_pm2 - exiting"
        exit 0
    fi

    LOG_DIR=$2/logs
    PID_DIR=$2/pids
    if [[ $3 ]]; then
        LOG_DIR=$3
    fi
    if [[ $4 ]]; then
        PID_DIR=$4
    fi

    sed -i "s?{INSTALL_DIR}?${2}?g" $1
    sed -i "s?{LOG_DIR}?${LOG_DIR}?g" $1
    sed -i "s?{PID_DIR}?${PID_DIR}?g" $1

}



#################################################################################
#                           DEBIAN / UBUNTU FUNCTIONS                           #
#################################################################################
function debian_install ()
{
    apt-get -y -qq install net-tools curl git python build-essential xvfb

    curl -sL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo -E bash -
    apt-get -y -qq install nodejs

    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    apt-get -qq update
    apt-get -y -qq install yarn
}


function debian_nginx ()
{
    if [[ ! -d $1 ]]; then
        echo "[LL] No install directory passed to debian_nginx(), should be impossible - exiting"
        exit 0
    fi

    while true; do
        echo
        echo "[LL] The next part of the install process will install nginx and remove any default configs - press 'y' to continue or 'n' to abort (press 'enter' for the default of 'y')"
        read n
        if [[ $n == "" ]]; then
            n="y"
        fi
        if [[ $n == "y" ]]; then
            break
        elif [[ $n == "n" ]]; then
            echo "[LL] Can't continue - you'll need to do this step by hand"
            sleep 5
            return
        fi
    done
    apt-get -y -qq install nginx

    if [[ ! -f ${1}/nginx.conf.example ]]; then
        echo "[LL] default learninglocker nginx config doesn't exist - can't continue. Press any key to continue"
        read n
        return
    fi

    rm /etc/nginx/sites-enabled/*
    # variable substitution from .env into nginx config - there's a carridge return we need to strip on this
    UI_PORT=`fgrep UI_PORT .env | sed 's/UI_PORT=//' | sed 's/\r//' `
    mv ${1}/nginx.conf.example /etc/nginx/sites-available/learninglocker.conf
    ln -s /etc/nginx/sites-available/learninglocker.conf /etc/nginx/sites-enabled/learninglocker.conf
    cat /etc/nginx/sites-available/learninglocker.conf | sed "s/UI_PORT/${UI_PORT}/" > ${1}/nginx.conf
    mv ${1}/nginx.conf /etc/nginx/sites-available/learninglocker.conf
    service nginx restart
}


function debian_mongo ()
{
    apt-get -y -qq install mongodb
}


function debian_redis ()
{
    apt-get -y -qq install redis-tools redis-server
}


#################################################################################
#                                REDHAT FUNCTIONS                               #
#################################################################################
REDHAT_EPEL_INSTALLED=false
function redhat_epel ()
{
    if [[ $REDHAT_EPEL_INSTALLED == true ]]; then
        return
    fi
    yum install epel-release
    REDHAT_EPEL_INSTALLED=true
}


function redhat_redis ()
{
    echo "[LL] installing redis"
    redhat_epel
    yum install redis
    service redis start
}


function redhat_mongo ()
{
    echo "[LL] installing mongodb"
    redhat_epel
    mkdir -r /data/db
    yum install mongodb-server
    semanage port -a -t mongod_port_t -p tcp 27017
    service mongod start
}


function redhat_install ()
{
    yum install curl git python make automake gcc gcc-c++ kernel-devel xorg-x11-server-Xvfb git-core

    curl --silent --location https://rpm.nodesource.com/setup_${NODE_VERSION} | sudo bash -
    yum -y install nodejs

    wget https://dl.yarnpkg.com/rpm/yarn.repo -O /etc/yum.repos.d/yarn.repo
    yum install yarn
}


#################################################################################
#                                CENTOS FUNCTIONS                               #
#################################################################################
function centos_nginx ()
{
    if [[ ! -d $1 ]]; then
        echo "[LL] No install directory passed to centos_nginx(), should be impossible - exiting"
        exit 0
    fi


    while true; do
        echo
        echo "[LL] The next part of the install process will install nginx and remove any default configs - press 'y' to continue or 'n' to abort (press 'enter' for the default of 'y')"
        read n
        if [[ $n == "" ]]; then
            n="y"
        fi
        if [[ $n == "y" ]]; then
            break
        elif [[ $n == "n" ]]; then
            echo "[LL] Can't continue - you'll need to do this step by hand"
            sleep 5
            return
        fi
    done

    # set up repo if needed
    if [[ ! -f /etc/yum.repos.d/nginx.repo ]]; then
        echo "[nginx]" > /etc/yum.repos.d/nginx.repo
        echo "name=nginx repo" >> /etc/yum.repos.d/nginx.repo
        echo "baseurl=http://nginx.org/packages/centos/$OS_VNO/$OS_ARCH/" >> /etc/yum.repos.d/nginx.repo
        echo "gpgcheck=0" >> /etc/yum.repos.d/nginx.repo
        echo "enabled=1" >> /etc/yum.repos.d/nginx.repo
    fi
    yum install nginx

    # remove default config if it exists
    if [[ -f /etc/nginx/conf.d/default.conf ]]; then
        rm /etc/nginx/conf.d/default.conf
    fi

    if [[ ! -f ${1}/nginx.conf.example ]]; then
        echo "[LL] default learninglocker nginx config doesn't exist - can't continue. Press any key to continue"
        read n
        return
    fi

    # variable substitution from .env into nginx config - there's a carridge return we need to strip on this
    UI_PORT=`fgrep UI_PORT .env | sed 's/UI_PORT=//' | sed 's/\r//' `
    mv ${1}/nginx.conf.example /etc/nginx/conf.d/learninglocker.conf
    sed -i "s/UI_PORT/${UI_PORT}/" /etc/nginx/conf.d/learninglocker.conf
    restorecon -v /etc/nginx/conf.d/learninglocker.conf

    echo "[LL] I need to punch a hole in selinux to continue. This is running the command:"
    echo "         setsebool -P httpd_can_network_connect 1"
    echo "     press 'y' to continue or 'n' to exit"
    while true; do
        read n
        if [[ $n == "n" ]]; then
            echo "not doing this, you'll have to run it by hand"
            sleep 5
            break
        elif [[ $n == "y" ]]; then
            setsebool -P httpd_can_network_connect 1
            break
        fi
    done

    service nginx restart

    echo "[LL] as you're on CentOS, this may be running with firewalld enabled - you'll either need to punch"
    echo "     a hole in the firewall rules or disable firewalld (not recommended) to allow inbound access to"
    echo "     learning locker. Press any key to continue"
    read n
}


#################################################################################
#                                FEDORA FUNCTIONS                               #
#################################################################################
function fedora_redis ()
{
    echo "[LL] installing redis"
    yum install redis
}


function fedora_mongo ()
{
    echo "[LL] installing mongodb"
    yum install mongodb-server
}


function fedora_nginx ()
{
    if [[ ! -d $1 ]]; then
        echo "[LL] No install directory passed to fedora_nginx(), should be impossible - exiting"
        exit 0
    fi
    while true; do
        echo
        echo "[LL] The next part of the install process will install nginx and remove any default configs - press 'y' to continue or 'n' to abort (press 'enter' for the default of 'y')"
        read n
        if [[ $n == "" ]]; then
            n="y"
        fi
        if [[ $n == "y" ]]; then
            break
        elif [[ $n == "n" ]]; then
            echo "[LL] Can't continue - you'll need to do this step by hand"
            sleep 5
            return
        fi
    done

    # repos from https://rpmfusion.org/Configuration
    if [[ $OS_VNO == "24" ]]; then
        rpm -Uvh https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-24.noarch.rpm
    elif [[ $OS_VNO == "25" ]]; then
        rpm -Uvh https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-25.noarch.rpm
    elif [[ $OS_VNO == "26" ]]; then
        rpm -Uvh
    elif [[ $OS_VNO == "27" ]]; then
        rpm -Uvh https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-27.noarch.rpm
    else
        echo "[LL] Unknown fedora release, exiting"
        exit 0
    fi
    yum install nginx

    echo "[LL] Default fedora nginx config needs the server block in /etc/nginx/nginx.conf removing"
    echo "     before learninglocker will work properly or it'll clash with the LL config"
    echo "     Press any key to continue"
    read n

    if [[ ! -f ${1}/nginx.conf.example ]]; then
        echo "[LL] default learninglocker nginx config doesn't exist - can't continue. Press any key to continue"
        read n
        return
    fi

    # variable substitution from .env into nginx config - there's a carridge return we need to strip on this
    UI_PORT=`fgrep UI_PORT .env | sed 's/UI_PORT=//' | sed 's/\r//' `
    mv ${1}/nginx.conf.example /etc/nginx/conf.d/learninglocker.conf
    sed -i "s/UI_PORT/${UI_PORT}/" /etc/nginx/conf.d/learninglocker.conf
    restorecon -v /etc/nginx/conf.d/learninglocker.conf

    echo "[LL] I need to punch a hole in selinux to continue. This is running the command:"
    echo "         setsebool -P httpd_can_network_connect 1"
    echo "     press 'y' to continue or 'n' to exit"
    while true; do
        read n
        if [[ $n == "n" ]]; then
            echo "not doing this, you'll have to run it by hand"
            sleep 5
            break
        elif [[ $n == "y" ]]; then
            setsebool -P httpd_can_network_connect 1
            break
        fi
    done


    service nginx restart

    echo "[LL] as you're on Fedora, this may be running with firewalld enabled - you'll either need to punch"
    echo "     a hole in the firewall rules or disable firewalld (not recommended) to allow inbound access to"
    echo "     learning locker. Press any key to continue"
    read n

}


#################################################################################
#################################################################################
#################################################################################
#                                                                               #
#                                END OF FUNCTIONS                               #
#                                                                               #
#################################################################################
#################################################################################
#################################################################################

# before anything, make sure the tmp dir is large enough of get the user to specify a new one
_TD=/tmp
MIN_DISK_SPACE=3000000

# check we have enough space available
FREESPACE=`df $_TD | awk '/[0-9]%/{print $(NF-2)}'`
if [[ $FREESPACE -lt $MIN_DISK_SPACE ]]; then
    echo "[LL] your temp dir isn't large enough to continue, please enter a new path (pressing enter will exit)"
    while true; do
        read n
        if [[ $n == "" ]]; then
            exit 0
        elif [[ ! -d $n ]]; then
            echo "[LL] Sorry but the directory '${n}' doesn't exist - please enter a valid one (press enter to exit)"
        else
            _TD=$n
            break
        fi
    done
fi



#################################################################################
#                                DEFAULT VALUES                                 #
#################################################################################
UPI=false
LOCAL_INSTALL=false
PACKAGE_INSTALL=false
DEFAULT_LOCAL_INSTALL_PATH=/home/node/learninglocker
DEFAULT_INSTALL_TYPE=l
LOCAL_PATH=false
LOCAL_USER=false
DEFAULT_USER=node
TMPDIR=$_TD/.tmpdist
GIT_BRANCH="release/v2.4.1"
BUILDDIR=$_TD
MONGO_INSTALLED=false
REDIS_INSTALLED=false
PM2_OVERRIDE=false
NODE_OVERRIDE=false
NODE_VERSION=8.x
GIT_ASK=false



#################################################################################
#                                 START CHECKS                                  #
#################################################################################

# cleanup, just in case
if [ -d $TMPDIR ]; then
    rm -R $TMPDIR
fi

if [ -d "${BUILDDIR}learninglocker_node" ]; then
    echo "clearing old tmp dir"
    rm -R ${BUILDDIR}learninglocker_node
fi

if [ -d $TMPDIR ]; then
    echo "[LL] tmp directory from prior install (${TMPDIR}) still exists - please clear by hand"
    exit 0
fi

# check if root user
if [[ `whoami` != "root" ]]; then
    echo "[LL] Sorry, you need to be root or sudo to run this script"
    exit 0
fi



#################################################################################
#                                 ASK QUESTIONS                                 #
#################################################################################
if [[ $UPI == false ]]; then
    if [[ $GIT_ASK == true ]]; then
        while true; do
            echo "[LL] What branch do you want to install ? Press 'enter' for the default of ${GIT_BRANCH}"
            read -r n
            if [[ $n == "" ]]; then
                break
            else
                while true; do
                    echo "[LL] are you sure the branch '${n}' is correct ? [y|n] (press enter for the default of 'y')"
                    read -r -s -n 1 c
                    if [[ $c == "" ]]; then
                        c="y"
                    fi
                    if [[ $c == "y" ]]; then
                        GIT_BRANCH=$n
                        break 2
                    elif [[ $c == "n" ]]; then
                        break
                    fi
                done
            fi
        done
    fi

    while true; do
        #echo "[LL] Do you want to install this locally(l) or create a package(p) ? [l|p] (enter for default of '${DEFAULT_INSTALL_TYPE}'"
        #read -r -s -n 1 n
        n="l"
        if [[ $n == "" ]]; then
            n=$DEFAULT_INSTALL_TYPE
        fi
        if [[ $n == "l" ]]; then
            LOCAL_INSTALL=true

            # determine user to install under
            if [[ $LOCAL_USER == false ]]; then
                # no CLI value
                while true; do
                    echo "[LL] I need a user to install the code under - what user would you like me to use ? (press enter for the default of '$DEFAULT_USER')"
                    read -r u
                    if [[ $u == "" ]]; then
                        u=$DEFAULT_USER
                    fi
                    USERDATA=`getent passwd $u`
                    if [[ $USERDATA == *"$u"* ]]; then
                        # user exists
                        while true; do
                            echo "[LL] User '$u' already exists - are you sure you want to continue? [y|n] (enter for default of 'y')"
                            read -r -s -n 1 c
                            if [[ $c == "" ]]; then
                                c="y"
                            fi
                            if [[ $c == "y" ]]; then
                                LOCAL_USER=$u
                                break
                            elif [[ $c == "n" ]]; then
                                echo "[LL] Selected to not continue, exiting"
                                exit 0
                            fi
                        done
                    else
                        while true; do
                            echo "[LL] User '$u' doesn't exist - do you want me to create them ? [y|n] (enter for default of 'y')"
                            read -r -s -n 1 c
                            if [[ $c == "" ]]; then
                                c="y"
                            fi
                            if [[ $c == "y" ]]; then
                                adduser $u
                                LOCAL_USER=$u
                                break
                            elif [[ $c == "n" ]]; then
                                echo "[LL] Can't create user - can't continue"
                                exit 0
                            fi
                        done
                    fi
                    break
                done
            else
                # user passed on CLI
                USERDATA=`getent passwd $LOCAL_USER`
                if [[ $USERDATA == *"$LOCAL_USER"* ]]; then
                    # user exists
                    while true; do
                        echo "[LL] User '$LOCAL_USER' already exists - are you sure you want to continue? [y|n]"
                        read -r -s -n 1 c
                        if [[ $c == "y" ]]; then
                            break
                        elif [[ $c == "n" ]]; then
                            echo "[LL] Selected to not continue, exiting"
                            exit 0
                        fi
                    done
                else
                    while true; do
                        echo "[LL] User '$LOCAL_USER' doesn't exist - do you want me to create them [y|n]?"
                        read -r -s -n 1 c
                        if [[ $c == "y" ]]; then
                            adduser $LOCAL_USER
                            break
                        elif [[ $c == "n" ]]; then
                            echo "[LL] Can't create user - can't continue"
                            exit 0
                        fi
                    done
                fi
            fi


            # determine local installation path
            if [[ $LOCAL_PATH != "false" ]]; then
                # path specified on CLI. Make sure it exists or offer to create it
                if [[ ! -f $LOCAL_PATH ]]; then
                    while true; do
                        echo "[LL] Directory '$p' doesn't exist, do you want to create it ? [y|n]"
                        read -r -s -n 1 c
                        if [[ $c == "y" ]]; then
                            mkdir -p $c
                        elif [[ $c == "n" ]]; then
                            echo "[LL] Specified install directory doesn't exist and you don't want to create it. Can't continue"
                            exit 0
                        fi
                    done
                fi
            else
                # no path passed on CLI
                while true; do
                    echo "[LL] What path do you want to install to ? (press enter for the default of $DEFAULT_LOCAL_INSTALL_PATH)"
                    read -r p
                    if [[ $p == "" ]]; then
                        p=$DEFAULT_LOCAL_INSTALL_PATH
                    fi
                    LOCAL_PATH=$p
                    if [[ -d $p ]]; then
                        while true; do
                            echo "[LL] Directory '$p' already exists - should we delete this before continuing ? [y|n] (press 'enter' for the default of 'y')"
                            read -r -s -n 1 b
                            if [[ $b == "" ]]; then
                                b="y"
                            fi
                            if [[ $b == "y" ]]; then
                                echo "[LL] deleting directory"
                                rm -R $p
                                break
                            elif [[ $b == "n" ]]; then
                                echo "[LL] ok, contuing without deleting - may not result in a clean install"
                                sleep 5
                                break
                            fi
                        done
                    else
                        while true; do
                            echo "[LL] Directory '$p' doesn't exist, do you want to create it ? [y|n] (press 'enter' for default of 'y')"
                            read -r -s -n 1 c
                            if [[ $c == "" ]]; then
                                c="y"
                            fi
                            if [[ $c == "y" ]]; then
                                mkdir -p $p
                                break
                            elif [[ $c == "n" ]]; then
                                echo "[LL] Specified install directory doesn't exist and you don't want to create it. Can't continue"
                                exit 0
                            fi
                        done
                    fi
                    break
                done
            fi

            # check mongo
            if [[ `command -v mongod` ]]; then
                echo "[LL] MongoDB is already installed, not installing"
                MONGO_INSTALLED=true
                sleep 5
            else
                while true; do
                    echo "[LL] MongoDB isn't installed - do you want to install it ? [y|n] (press 'enter' for default of 'y')"
                    read -r -s -n 1 c
                    if [[ $c == "" ]]; then
                        c="y"
                    fi
                    if [[ $c == "y" ]]; then
                        MONGO_INSTALL=true
                        MONGO_INSTALLED=true
                        break
                    elif [[ $c == "n" ]]; then
                        MONGO_INSTALL=false
                        break
                    fi
                done
            fi

            # check redis
            if [[ `command -v redis-server` ]]; then
                echo "[LL] Redis is already installed, not installing"
                REDIS_INSTALLED=true
                sleep 5
            else
                while true; do
                    echo "[LL] Redis isn't installed - do you want to install it ? [y|n] (press 'enter' for default of 'y')"
                    read -r -s -n 1 c
                    if [[ $c == "" ]]; then
                        c="y"
                    fi
                    if [[ $c == "y" ]]; then
                        REDIS_INSTALL=true
                        REDIS_INSTALLED=true
                        break
                    elif [[ $c == "n" ]]; then
                        REDIS_INSTALL=false
                        break
                    fi
                done
            fi

            break
        elif [[ $n == "p" ]]; then
            PACKAGE_INSTALL=true
            break
        fi
    done
fi


#################################################################################
#                          RUN BASE INSTALL TO TMPDIR                           #
#################################################################################
determine_os_version

if [[ $NODE_OVERRIDE != false ]]; then
    NODE_VERSION=$NODE_OVERRIDE
fi
echo "[LL] Installing node version: $NODE_VERSION"

if [[ $OS_VERSION == "Debian" ]]; then
    debian_install
elif [[ $OS_VERSION == "Ubuntu" ]]; then
    debian_install
elif [[ $OS_VERSION == "Redhat" ]]; then
    redhat_install
fi


nvm_install

# base install & build
echo "[LL] Running install step"
cd $BUILDDIR
base_install
xapi_install

# create tmp dir
echo "[LL] creating $TMPDIR"
mkdir -p $TMPDIR

# package.json
echo "[LL] copying modules"
if [[ ! -f ${BUILDDIR}/learninglocker_node/package.json ]]; then
    echo "can't copy file '${BUILDDIR}/learninglocker_node/package.json' as it doesn't exist- exiting"
    exit 0
fi
cp ${BUILDDIR}/learninglocker_node/package.json $TMPDIR/

# pm2 loader
if [[ ! -f ${BUILDDIR}/learninglocker_node/pm2/all.json ]]; then
    echo "can't copy file '${BUILDDIR}/learninglocker_node/pm2/all.json' as it doesn't exist- exiting"
    exit 0
fi
cp ${BUILDDIR}/learninglocker_node/pm2/all.json.dist $TMPDIR/all.json

# xapi config
if [[ ! -f ${BUILDDIR}/learninglocker_node/xapi/pm2/xapi.json.dist ]]; then
    echo "can't copy file '${BUILDDIR}/learninglocker_node/xapi/pm2/xapi.json.dist' as it doesn't exist- exiting"
    exit 0
fi
if [[ ! -d ${TMPDIR}/xapi ]]; then
    mkdir -p ${TMPDIR}/xapi
fi
cp ${BUILDDIR}/learninglocker_node/xapi/pm2/xapi.json.dist $TMPDIR/xapi/xapi.json

# node_modules
if [[ ! -d ${BUILDDIR}/learninglocker_node/node_modules ]]; then
    echo "can't copy directory '${BUILDDIR}/learninglocker_node/node_modules' as it doesn't exist- exiting"
    exit 0
fi
cp -R ${BUILDDIR}/learninglocker_node/node_modules $TMPDIR/

cp nginx.conf.example $TMPDIR/
cp ${BUILDDIR}/learninglocker_node/.env $TMPDIR/
cp ${BUILDDIR}/learninglocker_node/xapi/.env $TMPDIR/xapi/
checkCopyDir



if [[ $LOCAL_INSTALL == true ]]; then
    #################################################################################
    #                                 LOCAL INSTALL                                 #
    #################################################################################

    # DEBIAN
    if [[ $OS_VERSION == "Debian" ]]; then
        debian_nginx $TMPDIR
        if [[ $REDIS_INSTALL == true ]]; then
            debian_mongo
        fi
    # UBUNTU
    elif [[ $OS_VERSION == "Ubuntu" ]]; then
        debian_nginx $TMPDIR
        if [[ $REDIS_INSTALL == true ]]; then
            debian_redis
        fi
        if [[ $MONGO_INSTALL == true ]]; then
            debian_mongo
        fi
    elif [[ $OS_VERSION == "Redhat" ]]; then
    # FEDORA
        if [[ $OS_SUBVER == "Fedora" ]]; then
            fedora_nginx $TMPDIR
            if [[ $REDIS_INSTALL == true ]]; then
                fedora_redis
            fi
            if [[ $MONGO_INSTALL == true ]]; then
                fedora_mongo
            fi
    # CENTOS
        elif [[ $OS_SUBVER == "CentOS" ]]; then
            centos_nginx $TMPDIR
            if [[ $REDIS_INSTALL == true ]]; then
                redhat_redis
            fi
            if [[ $MONGO_INSTALL == true ]]; then
                redhat_mongo
            fi
        else
    # RHEL / GENERIC REDHAT
            redhat_nginx $TMPDIR
            if [[ $REDIS_INSTALL == true ]]; then
                redhat_redis
            fi
            if [[ $MONGO_INSTALL == true ]]; then
                redhat_mongo
            fi
        fi
    fi

    echo "[LL] Local install to $LOCAL_PATH"

    # set up the pid & log directories
    LOG_PATH=/var/log/learninglocker
    PID_PATH=/var/run
    if [[ ! -d $LOG_PATH ]]; then
        mkdir -p $LOG_PATH
    fi
    chown ${LOCAL_USER}:${LOCAL_USER} $LOG_PATH



    reprocess_pm2 $TMPDIR/all.json $LOCAL_PATH $LOG_PATH $PID_PATH
    reprocess_pm2 $TMPDIR/xapi/xapi.json ${LOCAL_PATH}/xapi $LOG_PATH $PID_PATH


    mkdir -p $LOCAL_PATH
    cp -R $TMPDIR/* $LOCAL_PATH/
    # above line doesn't copy the .env so have to do this manually
    cp $TMPDIR/.env $LOCAL_PATH/.env
    chown $LOCAL_USER:$LOCAL_USER $LOCAL_PATH -R


    # set up init script and run any reprocessing we need
    setup_init_script $LOCAL_PATH $LOCAL_USER

    service pm2-${LOCAL_USER} start

    if [ $MONGO_INSTALLED == true ] && [ $REDIS_INSTALLED == true ]; then
        RUN_INSTALL_CMD=false
        echo "[LL] do you want to set up the organisation now to complete the installation ? [y|n] (press enter for the default of 'y')"
        while true; do
            read n
            if [[ $n == "" ]]; then
                n="y"
            fi
            if [[ $n == "y" ]]; then
                while true; do
                    echo "[LL] please enter the organisation name"
                    read e
                    if [[ $e != "" ]]; then
                        INSTALL_ORG=$e
                        break
                    fi
                done
                while true; do
                    echo "[LL] please enter the email address for the administrator account"
                    read e
                    if [[ $e != "" ]]; then
                        INSTALL_EMAIL=$e
                        break
                    fi
                done
                while true; do
                    echo "[LL] please enter the password for the administrator account"
                    read e
                    if [[ $e != "" ]]; then
                        INSTALL_PASSWD=$e
                        break
                    fi
                done
                while true; do
                    echo "[LL] Is the following information correct ? [y|n]"
                    echo "     Organisation  : $INSTALL_ORG"
                    echo "     Email address : $INSTALL_EMAIL"
                    echo "     Password      : $INSTALL_PASSWD"
                    read e
                    if [[ $e == "y" ]]; then
                        break;
                    elif [[ $e == "n" ]]; then
                        continue 2
                    fi
                done

                RUN_INSTALL_CMD=true
                break;
            elif [[ $n == "n" ]]; then
                break;
            fi
        done

        if [[ $RUN_INSTALL_CMD == true ]]; then
            d=`pwd`
            cd $LOCAL_PATH
            node cli/dist/server createSiteAdmin $INSTALL_EMAIL $INSTALL_ORG $INSTALL_PASSWD
            cd $d
        fi

    else
        echo
        echo "[LL] Everything is installed but mongoDB & Redis are missing from the local installation. Please edit the .env file"
        echo "     in $LOCAL_PATH to point to your relevant servers then run this command:"
        echo "         cd ${LOCAL_PATH}; node cli/dist/server createSiteAdmin {your.email@address.com} {organisationName} {yourPassword}"
        echo
    fi


elif [[ $PACKAGE_INSTALL == true ]]; then
    #################################################################################
    #                                PACKAGE INSTALL                                #
    #################################################################################
    echo "[LL] Package install"

fi



#################################################################################
#                                    CLEANUP                                    #
#################################################################################
echo "[LL] cleaning up temp directories"
if [[ -d $TMPDIR ]]; then
    rm -R $TMPDIR
fi
if [[ -d ${BUILDDIR}/learninglocker_node ]]; then
    rm -R ${BUILDDIR}/learninglocker_node
fi