#!/bin/bash
#
####
# - Timestamp-Ping -
# log ping-timestamps of a target host
# versions prior to git control
# v0.9 2015-08-19 /schwupp
# v1.0 2015-09-17 /schwupp - Final Release, added 'displaytime' to get convenient display of seconds
# v2.1 2017-01-02 /schwupp - added -d debug-option
# v2.2 2017-01-25 /schwupp - added -f fuzzy dead-detection option
# v3.0 2020-08-10 /schwupp - added support for IPv6 (switch -6)
# v3.1 2021-08-18 /schwupp - added fallback to IPv4 if no IPv6 found in DNS
####

#actual Version
VER="3.1"

#user-controlled variables
# default for DNS-lookup when using a hostname instead of IP-address
# use "6" for using IPv6 lookup (AAAA-record) as default and falling back to IPv4
# use 4 for using IPv4 lookup (A-record) only
# 
ipv=6
# enable(1)/disable(0) debug output
debug=0

#some other default values, mostly controlled by parameters
health=2
mytime=`date +%s`
deadtime=1
interval=1
fuzzy=0
myfuzzy=0
ip=0

#some constants for bash-coloring
RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
BLUE="\e[0;34m"
PURPLE="\e[0;35m"
CYAN="\e[0;36m"
WHITE="\e[0;37m"
EXPAND_BG="\e[K"
BLUE_BG="\e[0;44m${expand_bg}"
RED_BG="\e[0;41m${expand_bg}"
GREEN_BG="\e[0;42m${expand_bg}"
BOLD="\e[1m"
ULINE="\e[4m"
RESET="\e[0m"

#Time-Converter
function displaytime {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  [[ $D > 0 ]] && printf '%d d ' $D
  [[ $H > 0 ]] && printf '%d h ' $H
  [[ $M > 0 ]] && printf '%d min ' $M
  [[ $D > 0 || $H > 0 || $M > 0 ]] && printf 'and '
  printf '%d sec\n' $S
}

usage () {
echo -e "\tusage: $(basename $0) [-vhd4] [-W deadtime] [-i interval] [-f fuzzy-pings (# failed pings before marking down)] [-4 use IPv4-only for DNS-lookup] <Traget IP or DNS-Name>"
}

_options ()
{
        while getopts ":vhdW:i:f:4" opt; do :
                case $opt in
                        4 ) ipv=4 ;;
                        W ) deadtime=$OPTARG ;;
                        i ) interval=$OPTARG ;;
                        f ) fuzzy=$OPTARG ;;
                        d ) debug=1 ;;
                        h ) usage
                                exit 0;;
                        v ) echo -e "$(basename $0) v$VER by schwupp"
                                exit 0;;
                        \? )
                                echo "Invalid option: -$OPTARG" >&2
                                exit 1;;
                        : )
                                echo "Option -$OPTARG requires an argument." >&2
                                exit 1
                esac
        done
shift $((OPTIND -1))

if [ -z "$1" ];then
        usage
        exit 1
else
        host=$1;
fi
}

shift $((OPTIND -1))
if [ -z "$1" ] ;then
        usage
        exit 0
else
        _options $*;
fi


#the script begins!
if [[ $host =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        hostdig=`dig +short -x $host`
        ip=$host
elif [[ $host =~ (([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])) ]]; then
        hostdig=`dig +short -x $host`
        ip=$host
else
        if [ $ipv == 6 ]; then
                hostdig=`dig AAAA +search +short $host  | grep -v '\.$'`
                if [ -z $hostdig ]; then
                        echo -e "${YELLOW}No v6 DNS for $host - trying v4 DNS...${RESET}"
                        ipv=4
                fi
        fi
        if [ $ipv == 4 ]; then
                hostdig=`dig A +search +short $host | grep -v '\.$'`
                if [ -z $hostdig ]; then
                        echo -e "${RED}No v4 DNS for $host - exiting now.${RESET}"
                        exit 1
                fi
        fi
#       hostdig=`dig +search +short $host`
#       if [ -z $hostdig ]; then
#               echo "No DNS for $host - exiting now."
#               exit 1
#       fi

        ip=$hostdig
fi

if [ $debug -eq 1 ]; then
        echo -e "\t####### DEBUG #######"
        echo -e "\targs = [ $# ]"
        echo -e "\tdeadtime  = [ $deadtime ]"
        echo -e "\tinterval = [ $interval ]"
        echo -e "\tfuzzy = [ $fuzzy ]"
        echo -e "\thost = [ $host ]"
        echo -e "\tip = [ $ip ]"
        echo -e "\t####### DEBUG #######"
fi

if [ -z $host ]; then
    echo "Usage: `basename $0` [HOST]"
    exit 1
fi

if [ $fuzzy -gt 0 ]; then
    echo -e "\nNote: fuzzy dead-detection in effect, will ignore up to $fuzzy failed pings. Use for unreliable connections only.\n"
fi

while :; do
    result=`ping -W $deadtime -c 1 $ip | grep 'bytes from '`
    if [ $? -gt 0 ]; then
        myfuzzy=$((myfuzzy + 1))
        if [ $myfuzzy -gt $fuzzy ]; then
                if [ $health -eq 2 ]; then
                        echo -e "`date +'%Y-%m-%d %H:%M:%S'` | host $host ($hostdig) is \033[0;31mdown\033[0m"
                elif [ $health -eq 1 ]; then
                        deadsec=`date +%s`-$mytime
                        echo -e "`date +'%Y-%m-%d %H:%M:%S'` | host $host ($hostdig) is \033[0;31mdown\033[0m [ok for $(displaytime $deadsec)]"
                mytime=`date +%s`
                fi
                health=0
        fi
    else
        myfuzzy=0
        if [ $health -eq 2 ] ;then
                echo -e "`date +'%Y-%m-%d %H:%M:%S'` | host $host ($hostdig) is \033[0;32mok\033[0m | RTT `echo $result | cut -d ':' -f 2 | cut -d ' ' -f 4 | cut -d "=" -f 2`ms"
        elif [ $health -eq 0 ] ;then
                deadsec=`date +%s`-$mytime
                echo -e "`date +'%Y-%m-%d %H:%M:%S'` | host $host ($hostdig) is \033[0;32mok\033[0m [down for $(displaytime $deadsec)] | RTT `echo $result | cut -d ':' -f 2 | cut -d ' ' -f 4 | cut -d "=" -f 2`ms"
        mytime=`date +%s`
        fi
        health=1
        sleep $interval # delay between pings
    fi
done
