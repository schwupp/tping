#!/bin/bash
#
####
# - Timestamp-Ping -
# log ping-timestamps of a target host
#
# versions prior to git control
# v0.9 2015-08-19 /schwupp
# v1.0 2015-09-17 /schwupp - Final Release, added 'displaytime' to get convenient display of seconds
# v2.1 2017-01-02 /schwupp - added -d debug-option
# v2.2 2017-01-25 /schwupp - added -f fuzzy dead-detection option
# v3.0 2020-08-10 /schwupp - added support for IPv6 (switch -6)
#
# git version control
# v3.1 2021-08-18 /schwupp - added fallback to IPv4 if no IPv6 found in DNS
# v4.0 2022-03-27 /lippl - added support for macos, PR #1
# v5.0 2023-02-04 /lippl - stats-on-exit, PR #4
# v5.1 2023-05-26 /schwupp - fix match/grep of ping-cmd in linux/macos
####

## 0 - constants, variables, settings
# actual Version
VER="5.1"

# user-controlled variables
# default for DNS-lookup when using a hostname instead of IP-address
# use "6" for using IPv6 lookup (AAAA-record) as default and falling back to IPv4
# use 4 for using IPv4 lookup (A-record) only
# 
ipv=6
# enable(1)/disable(0) debug output
debug=0

# some other default values, mostly controlled by parameters
#health stores tristate value meaning 0=dead, 1=alive, 2=ontime-startup-only-state (dead or alive)
health=2
#parameter for ping binary
deadtime=1
#time between pings. as we doing only single pings this is use as internal delay parameter 
interval=1
#paramter for fuzzy-dead detection
fuzzy=0
myfuzzy=0
#version of ip-protocol to be used (4/6)
ip=0
#follow-function (on/off)
follow=1

# some constants for bash-coloring
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# some statistical values
lastuptime=0
lastdowntime=0
transmitted=0
received=0
downtotal=0
downsec=0
uptotal=0
upsec=0
flap=0
rtt=()

# Functions
# print final statistics on exit
function print_statistics() {
	echo -e "\n--- $host ($hostdig) tping statistics ---"

	if [[ $health -eq 1 ]]; then
		upsec=$(date +%s)-$lastuptime
		uptotal=$((uptotal + upsec))
	elif [[ $health -eq 0 ]] ;then
		downsec=$(date +%s)-$lastdowntime
		downtotal=$((downtotal + downsec))
	fi
	echo "flapped $flap times, was up for $(displaytime $uptotal) and down for $(displaytime $downtotal)"

	# check if 'bc' is installed on system, if yes print detailed (floating point) statistics
	if [[ -n $(which bc) ]]; then

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

	# if no 'bc' is there, print hint
	else
		echo -e "$transmitted packets transmitted, $received packets received\n"
		echo "info: basic statistics only, please install 'bc' to get extended rtt-stats."
	fi

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
	echo -e "usage: $(basename "$0") [-vhd4] [-W deadtime] [-i interval]
		\t[-f fuzzy-pings (# failed pings before marking down)]
		\t[-4 (use IPv4-only for DNS-lookup)]
		\t[-s (use legacy static mode without rtt live-updates)]
		\t<Traget IP or DNS-Name>"
}

_options () {
	while getopts ":vhdW:i:f:s4" opt; do :
		case $opt in
			4 ) ipv=4 ;;
			W ) deadtime=$OPTARG ;;
			i ) interval=$OPTARG ;;
			f ) fuzzy=$OPTARG ;;
			s ) follow=0 ;;
			d ) debug=1 ;;
			h ) usage
				exit 0;;
			v ) echo "$(basename "$0") v$VER"
				exit 0;;
			\? )
				echo "Invalid option: -$OPTARG" >&2
				usage
				exit 1;;
			: )
				echo "Option -$OPTARG requires an argument." >&2
				usage
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
	hostdig=$(dig +short -x "$host" | head -1 | sed 's/\.$//')
	ip=$host
	ipv=4
# it's an ipv6-addr-parameter        
elif [[ $host =~ (([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])) ]]; then
	hostdig=$(dig +short -x "$host" | head -1 | sed 's/\.$//')
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
	echo -e "\tfollow = [ $follow ]"
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
	echo -e "\nNote: fuzzy dead-detection in effect, will ignore up to $fuzzy failed pings (you will see a --FUZZY-- indicator if in action). Use for unreliable connections only.\n"
fi

## 3 - do the ping in loop
tput sc
while :; do
	transmitted=$((transmitted + 1))
	result=$($ping | grep 'icmp_seq=.*time=')
	rv=$?
	if [[ $rv -gt 0 ]]; then
		myfuzzy=$((myfuzzy + 1))
		if [[ $myfuzzy -gt "$fuzzy" ]]; then
			if [[ $health -eq 2 ]]; then #start to down
				lastdowntime=$(date +%s)
				if [ $debug -eq 1 ]; then
					echo -en "debug:STD;result=$result;rv=$rv;health=$health "
				fi
				echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET}"
				health=0
			elif [[ $health -eq 1 ]]; then #up to down
				lastdowntime=$(date +%s)
				upsec=$(date +%s)-$lastuptime
				uptotal=$((uptotal + upsec))
				flap=$((flap + 1))
				tput rc; tput el
				if [ $debug -eq 1 ]; then
					echo -en "debug:UTD;result=$result;rv=$rv;health=$health "
				fi
				echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET} [ok for $(displaytime "$upsec")]"
				tput sc
				health=0
			elif [ $health -eq 0 ] && [ $follow -eq 1 ]; then #down to down
				downsec=$(date +%s)-$lastdowntime
				tput rc; tput el
				if [ $debug -eq 1 ]; then
					echo -en "debug:DTU;result=$result;rv=$rv;health=$health "
				fi
				echo -en "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET} for $(displaytime "$downsec")"
			fi
		else #we're in fuzzy-detection now. pings fail, but will not consider down
			if [ $myfuzzy -eq 1 ]; then #only on 1st fuzzy-ping, show hint, next successful ping will clear whole line
				echo -n " --FUZZY--"
			fi
			#NOP - for the user it's like pausing output what we tried to eliminate. this is the only point where tping behaves like that, but may be ok in this cornercase.
		fi
	else #ping successful
		received=$((received + 1))
		rtt[$transmitted]=$(echo "$result" | cut -d "=" -f 4  | cut -d ' ' -f 1)
		myfuzzy=0
		if [[ $health -eq 2 ]]; then #start to up
			lastuptime=$(date +%s)
			if [ $debug -eq 1 ]; then
				echo -en "debug:STU;result=$result;rv=$rv;health=$health "
			fi
			echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} | RTT ${rtt[$transmitted]}ms"
			health=1
		elif [[ $health -eq 0 ]]; then #down to up
			tput rc; tput el
			downsec=$(date +%s)-$lastdowntime
			downtotal=$((downtotal + downsec))
			flap=$((flap + 1))
			if [ $debug -eq 1 ]; then
				echo -en "debug:DTU;result=$result;rv=$rv;health=$health "
			fi
			echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} [down for $(displaytime "$downsec")] | RTT ${rtt[$transmitted]}ms"
			tput sc
			lastuptime=$(date +%s)
			health=1
		elif [ $health -eq 1 ] && [ $follow -eq 1 ]; then #up to up
			upsec=$(date +%s)-$lastuptime
			tput rc; tput el
			if [ $debug -eq 1 ]; then
				echo -en "debug:UTU;result=$result;rv=$rv;health=$health "
			fi
			echo -en "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} for $(displaytime "$upsec") | RTT ${rtt[$transmitted]}ms"
		fi
		# delay between pings
		sleep "$interval"
	fi
done
