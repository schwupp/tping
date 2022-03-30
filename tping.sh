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
# v4.0 2022-03-27 /lippl - added support for macos
####

## 0 - constants, variables, settings
# actual Version
VER="4.0"

# user-controlled variables
# default for DNS-lookup when using a hostname instead of IP-address
# use "6" for using IPv6 lookup (AAAA-record) as default and falling back to IPv4
# use 4 for using IPv4 lookup (A-record) only
# 
ipv=6
# enable(1)/disable(0) debug output
debug=0

# some other default values, mostly controlled by parameters
health=2
mytime=$(date +%s)
deadtime=1
interval=1
fuzzy=0
myfuzzy=0
ip=0

# some constants for bash-coloring
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# some statistical values
transmitted=0
received=0
down=0
downsec=0
up=0
upsec=0
flap=0
rtt=()

# print final statistics on exit
function print_statistics() {
    echo -e "\n--- $host ($hostdig) tping statistics ---"

    if [[ $health -eq 1 ]]; then
        upsec=$(date +%s)-$mytime
        up=$((up + upsec))
    elif [[ $health -eq 0 ]] ;then
        downsec=$(date +%s)-$mytime
        down=$((down + downsec))
    fi
    echo "flapped $flap times, was up for $(displaytime $up) and down for $(displaytime $down)"

    local loss
    loss=$(echo "scale=2;100-$received/$transmitted*100" | bc -l)
    echo "$transmitted packets transmitted, $received packets received, $loss% packet loss"

    local rtt_min=0
    local rtt_max=0
    local rtt_avg=0
    [[ -n "${rtt[1]}" ]] && rtt_min=${rtt[1]}
    for t in "${rtt[@]}"; do
        rtt_avg=$(echo "scale=3;$rtt_avg + $t" | bc -l)
        if (($(echo "$t > $rtt_max" | bc -l))); then
            rtt_max=$t
        fi
        if (($(echo "$t < $rtt_min" | bc -l))); then
            rtt_min=$t
        fi
    done
    rtt_avg=$(echo "scale=3;$rtt_avg/$transmitted" | bc -l)
    echo "round-trip min/avg/max = $rtt_min/$rtt_avg/$rtt_max ms"

    exit 0
}
trap print_statistics INT

# time-converter
function displaytime {
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    [[ $D -gt 0 ]] && printf '%d d ' $D
    [[ $H -gt 0 ]] && printf '%d h ' $H
    [[ $M -gt 0 ]] && printf '%d min ' $M
    [[ $D -gt 0 || $H -gt 0 || $M -gt 0 ]] && printf 'and '
    printf '%d sec\n' $S
}

usage () {
    echo -e "\tusage: $(basename "$0") [-vhd4] [-W deadtime] [-i interval] [-f fuzzy-pings (# failed pings before marking down)] [-4 use IPv4-only for DNS-lookup] <Traget IP or DNS-Name>"
}

_options () {
    while getopts ":vhdW:i:f:4" opt; do :
        case $opt in
            4 ) ipv=4 ;;
            W ) deadtime=$OPTARG ;;
            i ) interval=$OPTARG ;;
            f ) fuzzy=$OPTARG ;;
            d ) debug=1 ;;
            h ) usage
                exit 0;;
            v ) echo "$(basename "$0") v$VER by schwupp"
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

    if [[ -z "$1" ]];then
        usage
        exit 1
    else
        host=$1;
    fi
}

shift $((OPTIND -1))
if [[ -z "$1" ]] ;then
    usage
    exit 0
else
    _options "$@";
fi

## 1 - get DNS-resolution if parameter is a hostname
# it's an ipv4-addr-parameter
if [[ $host =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    hostdig=$(dig +short -x "$host")
    ip=$host
    ipv=4
# it's an ipv6-addr-parameter        
elif [[ $host =~ (([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])) ]]; then
    hostdig=$(dig +short -x "$host")
    ip=$host
    ipv=6
# it's a name-parameter
else
    if [[ $ipv -eq 6 ]]; then
        hostdig=$(dig AAAA +search +short "$host"  | grep -v '\.$')
        if [[ -z "$hostdig" ]]; then
            echo -e "${YELLOW}Warning: No v6 DNS for $host - trying v4 DNS...${RESET}"
            ipv=4
        fi
    fi
    if [[ $ipv -eq 4 ]]; then
        hostdig=$(dig A +search +short "$host" | grep -v '\.$')
        if [[ -z "$hostdig" ]]; then
            echo -e "${RED}Error: No v4 DNS for $host - exiting now.${RESET}"
            exit 1
        fi
    fi
    ip=$hostdig
fi

## 2 - build ping-cmd
# it's macos were we running, ping binary is different especially for ipv6
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $ipv -eq 6 ]]; then
        if [ "$deadtime" != 1 ]; then
            echo -e "${YELLOW}Warning: Option -W is not supported on macOS for IPv6 and defaults to 10 seconds.${RESET}"
        fi
        ping="ping6 -c 1 $ip"
    else
        deadtime=$((deadtime*1000))
        ping="ping -W $deadtime -c 1 $ip"
    fi
# it's linux, ping binary supports both ipv4 and ipv6 parameter
else
    ping="ping -W $deadtime -c 1 $ip"
fi

# output some debug, we got so far
if [[ $debug -eq 1 ]]; then
    echo -e "\t####### DEBUG #######"
    echo -e "\tos = [ $OSTYPE ]"
    echo -e "\targs = [ $# ]"
    echo -e "\tdeadtime  = [ $deadtime ]"
    echo -e "\tinterval = [ $interval ]"
    echo -e "\tfuzzy = [ $fuzzy ]"
    echo -e "\thost = [ $host ]"
    echo -e "\tip = [ $ip ]"
    echo -e "\tping command = [ $ping ]"
    echo -e "\t####### DEBUG #######"
fi

if [[ -z "$host" ]]; then
    echo "Usage: $(basename "$0") [HOST]"
    exit 1
fi

if [[ "$fuzzy" -gt 0 ]]; then
    echo -e "\nNote: fuzzy dead-detection in effect, will ignore up to $fuzzy failed pings. Use for unreliable connections only.\n"
fi

## 3 - do the ping in loop
while :; do
    transmitted=$((transmitted + 1))
    result=$($ping | grep 'bytes from ')
    if [[ $? -gt 0 ]]; then
        myfuzzy=$((myfuzzy + 1))
        if [[ $myfuzzy -gt "$fuzzy" ]]; then
            if [[ $health -eq 2 ]]; then
                echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET}"
            elif [[ $health -eq 1 ]]; then
                upsec=$(date +%s)-$mytime
                up=$((up + upsec))
                flap=$((flap + 1))
                echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET} [ok for $(displaytime "$upsec")]"
                mytime=$(date +%s)
            fi
            health=0
        fi
    else
        received=$((received + 1))
        rtt[$transmitted]=$(echo "$result" | cut -d ':' -f 2 | cut -d ' ' -f 4 | cut -d "=" -f 2)
        myfuzzy=0
        if [[ $health -eq 2 ]] ;then
            echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} | RTT ${rtt[$transmitted]}ms"
        elif [[ $health -eq 0 ]] ;then
            downsec=$(date +%s)-$mytime
            down=$((down + downsec))
            flap=$((flap + 1))
            echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} [down for $(displaytime "$downsec")] | RTT ${rtt[$transmitted]}ms"
            mytime=$(date +%s)
        fi
        health=1
        # delay between pings
        sleep "$interval"
    fi
done
