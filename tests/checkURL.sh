#!/bin/bash

# $1 is the url to check
function check_url ()
{
    CODE=$(curl -I $1 2>>/dev/null | grep HTTP | awk '{print $2}')
    if [[ $CODE != 200 ]]; then
        echo "url : $1 failed with HTTP code: $CODE"
        exit 1
    else
        echo "url : $1 passed with HTTP 200"
    fi
}

while getopts ":u:" OPT; do
    case "$OPT" in
        u)
            URL=$OPTARG
        ;;
        *)
            echo "unknown option ($OPT) passed in with value $OPTARG"
        ;;
    esac
done

if [[ $URL == "" ]]; then
    echo "no url passed in"
    exit 1
fi

check_url $URL
