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
# v6.0 2023-07-12 /schwupp - new feature: follow-mode, PR #6
# v6.1 2023-09-04 /schwupp - refactoring, bugfixes, PR #12
# v6.2 2023-11-15 /schwupp - refactoring, bugfixes, PR #14,15,17
####

## 0 - constants, variables, settings
# actual Version
VER="6.2_fix-rtt-avg"

## default values for user-controlled variables
# default for DNS-lookup when using a hostname instead of IP-address
# use 6 for using IPv6 lookup (AAAA-record) as default and falling back to IPv4
# use 4 for using IPv4 lookup (A-record) only
ipv=6
# enable(1)/disable(0) debug output
debug=0
# deadtime in seconds for ping binary
deadtime=1
# time between pings in seconds
# interval is handled by script after ping wait and various runtime executions
interval=1
# limit for fuzzy-dead detection, where 0 disables fuzzy detection
fuzzy_limit=0
# follow-function on(1)/off(0)
follow=1

## other default values and placeholders not controlled by parameters
# health stores tristate value meaning 0=dead, 1=alive, 2=ontime-startup-only-state (dead or alive)
health=2
# placeholder for ther target ip to be filled after format checks respectively dns lookup
ip=0
# interval of successfull pings to intermediately calculate the statistic values for better performance at the end
statint=10

## statistical values
# counter for total lost pings during all fuzzy detections
fuzzy_lost=0
# counter for total occurrences of fuzzy detections
fuzzy_total=0
# counter for current fuzzy detection
fuzzy_cnt=0
# total number of transmitted pings
transmitted=0
# total number of received pings
received=0
# total downtime in seconds, not including fuzzy pings
downtotal=0
# current downtime in seconds
downsec=0
# total uptime in seconds, including fuzzy pings
uptotal=0
# current uptime in seconds
upsec=0
# time at last flap to up, used to calulate upsec
lastuptime=0
# time at last flap to down, used to calulate downsec
lastdowntime=0
# total number of flaps between up and down
flap=0
# array to store all rtt times within statistics interval (statint)
rtt=()
rtt_min=""
rtt_max=0
rtt_avg=0

## constants for bash-coloring
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

## Functions
# print usage
usage () {
	echo -e "usage: $(basename "$0") [-vhd] [-W deadtime] [-i interval]
		\t[-f fuzzy-pings (# failed pings before marking down)]
		\t[-4 (use IPv4-only for DNS-lookup)]
		\t[-s (use legacy static mode without rtt live-updates)]
		\t<Traget IP or DNS-Name>"
}

# parse options
_options () {
	while getopts ":vhdW:i:f:s4" opt; do :
		case $opt in
			4 ) ipv=4 ;;
			W ) deadtime=$OPTARG ;;
			i ) interval=$OPTARG ;;
			f ) fuzzy_limit=$OPTARG ;;
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

# calc interval statistics
function calc_statistics() {
	# check if 'bc' is installed on system, if yes calc detailed (floating point) statistics
	if [[ -n $(which bc) ]] && [[ -n "${rtt[1]}" ]]; then

		[[ -z $rtt_min ]] && rtt_min=${rtt[1]}
		
		local stat_cycles=$((($received - 1) / $statint))
		rtt_avg=$(echo "scale=3;$rtt_avg * $statint * $stat_cycles" | bc -l)
		for t in "${rtt[@]}"; do
			rtt_avg=$(echo "scale=3;$rtt_avg + $t" | bc -l)
			if (($(echo "$t > $rtt_max" | bc -l))); then
				rtt_max=$t
			fi
			if (($(echo "$t < $rtt_min" | bc -l))); then
				rtt_min=$t
			fi
		done
		rtt_avg=$(echo "scale=3;$rtt_avg/$received" | bc -l)
		rtt=()
	fi
}

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

	# if fuzzy detection is enabled and was detected before, print counters
	if [ $fuzzy_limit -gt 0 ] && [ $fuzzy_total -gt 0 ]; then
		echo "fuzzy detection was used $fuzzy_total times, with a total of $fuzzy_lost lost pings"
	fi

	# check if 'bc' is installed on system, if yes calc & print detailed (floating point) statistics
	if [[ -n $(which bc) ]]; then
		local loss
		loss=$(echo "scale=2;100-$received/$transmitted*100" | bc -l)
		echo "$transmitted packets transmitted, $received packets received, $loss% packet loss"

		calc_statistics
		echo "round-trip min/avg/max = $rtt_min/$rtt_avg/$rtt_max ms"
	# if no 'bc' is there, print hint
	else
		echo -e "$transmitted packets transmitted, $received packets received\n"
		echo "info: basic statistics only, please install 'bc' to get extended rtt-stats."
	fi

	exit 0
}
trap print_statistics INT

### runtime execution 
## 0 - handle arguments 
# check for options 
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
		hostdig=$(dig AAAA +search +short +nocookie "$host"  | grep -v '\.$')
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
	echo -e "\tfuzzy = [ $fuzzy_limit ]"
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

if [[ "$fuzzy_limit" -gt 0 ]]; then
	echo -e "\nNote: fuzzy dead-detection in effect, will ignore up to $fuzzy_limit failed pings (you will see a --FUZZY-- indicator if in action). Use for unreliable connections only.\n"
fi

## 3 - do the ping in loop
tput sc
while :; do
	transmitted=$((transmitted + 1))
	result=$($ping | grep 'icmp_seq=.*time=')
	rv=$?
	# ping failed
	if [[ $rv -gt 0 ]]; then
		fuzzy_cnt=$((fuzzy_cnt + 1))
		if [[ $fuzzy_cnt -gt "$fuzzy_limit" ]]; then
			# start to down
			if [[ $health -eq 2 ]]; then
				lastdowntime=$(date +%s)
				tput rc; tput el
				if [ $debug -eq 1 ]; then
					echo -en "debug:STD;result=$result;rv=$rv;health=$health "
				fi
				echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET}"
				tput sc
				health=0
			# up to down
			elif [[ $health -eq 1 ]]; then
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
			# down to down
			elif [ $health -eq 0 ] && [ $follow -eq 1 ]; then
				downsec=$(date +%s)-$lastdowntime
				tput rc; tput el
				if [ $debug -eq 1 ]; then
					echo -en "debug:DTU;result=$result;rv=$rv;health=$health "
				fi
				echo -en "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${RED}down${RESET} for $(displaytime "$downsec")"
			fi
		# we're in fuzzy-detection now. pings fail, but will not consider down
		else
			# only on 1st fuzzy-ping, show hint, next successful ping will clear whole line
			if [ $fuzzy_cnt -eq 1 ]; then
				echo -n " --FUZZY--"
			fi
			# NOP - for the user it's like pausing output what we tried to eliminate. this is the only point where tping behaves like that, but may be ok in this cornercase.
		fi
	# ping successful
	else
		received=$((received + 1))
		stat_cnt=$(($received % $statint))
		rtt[$stat_cnt]=$(echo "$result" | cut -d "=" -f 4  | cut -d ' ' -f 1)
		# start to up
		if [[ $health -eq 2 ]]; then
			lastuptime=$(date +%s)
			tput rc; tput el
			if [ $debug -eq 1 ]; then
				echo -en "debug:STU;result=$result;rv=$rv;health=$health "
			fi
			echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} | RTT ${rtt[$stat_cnt]}ms"
			tput sc
			health=1
		# down to up
		elif [[ $health -eq 0 ]]; then
			tput rc; tput el
			downsec=$(date +%s)-$lastdowntime
			downtotal=$((downtotal + downsec))
			flap=$((flap + 1))
			if [ $debug -eq 1 ]; then
				echo -en "debug:DTU;result=$result;rv=$rv;health=$health "
			fi
			echo -e "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} [down for $(displaytime "$downsec")] | RTT ${rtt[$stat_cnt]}ms"
			tput sc
			lastuptime=$(date +%s)
			health=1
		# up to up
		elif [ $health -eq 1 ] && [ $follow -eq 1 ]; then
			upsec=$(date +%s)-$lastuptime
			tput rc; tput el
			if [ $debug -eq 1 ]; then
				echo -en "debug:UTU;result=$result;rv=$rv;health=$health "
			fi
			echo -en "$(date +'%Y-%m-%d %H:%M:%S') | host $host ($hostdig) is ${GREEN}ok${RESET} for $(displaytime "$upsec") | RTT ${rtt[$stat_cnt]}ms"
		fi

		# update rtt stats
		if [[ $stat_cnt -eq 0 ]]; then
			calc_statistics
		fi

		# update fuzzy stats if fuzzy detection is enabled and was detected
		if [[ $fuzzy_limit -gt 0 ]] && [[ $fuzzy_cnt -gt 0 ]]; then
			fuzzy_total=$((fuzzy_total + 1))
			fuzzy_lost=$((fuzzy_lost + fuzzy_cnt))
		fi
		fuzzy_cnt=0

		# delay between pings
		sleep "$interval"
	fi
done
