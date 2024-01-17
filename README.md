# tping.sh
simple bash script, known as "timestamp-ping", pinging continously in background, only showing status-change (up/down) of destination host

## Motivation
As a network engineer, i needed a simple tool, to monitor an availability of a target IP-address. When using "ping xyz", you get a new line entry, every ping-interval, showing the actual RTT

    schwupp@linux:~$ ping HOST1
    PING HOST1(host1.domain.name (192.168.0.1)) 56 data bytes
    64 bytes from host1.domain.name (192.168.0.1): icmp_seq=1 ttl=64 time=0.047 ms
    64 bytes from host1.domain.name (192.168.0.1): icmp_seq=2 ttl=64 time=0.035 ms
    64 bytes from host1.domain.name (192.168.0.1): icmp_seq=3 ttl=64 time=0.042 ms
    64 bytes from host1.domain.name (192.168.0.1): icmp_seq=4 ttl=64 time=0.047 ms

In most cases, you only need to know, if the target host is reachable or not, and when a state change between up and down has happened. For this usecase, the quite bloating every-second-newline-characteristic of the original ping-tool is not very useful, so i ended up in creating a simple wrapper for it, using bash.

## Example
If you use tping script, you only get one line per status-change. You have to rely on the script, that it is pinging in the background for you. This is the main difference when using it, compared to original ping (which notifies you every ping-intervall, that is it still pinging, but you only get an indirect notice, if host is down). 

    schwupp@linux:~$ tping.sh HOST1
    2022-03-23 14:40:30 | host 192.168.0.1 (host1.domain.name) is ok | RTT 2.13ms
    2022-03-23 14:41:00 | host 192.168.0.1 (host1.domain.name) is down [ok for 30 sec]
    2022-03-23 14:41:21 | host 192.168.0.1 (host1.domain.name) is ok [down for 21 sec] | RTT 1.42ms
    --- host1.domain.name (192.168.0.1) tping statistics ---
    flapped 0 times, was up for 51 sec and down for 0 sec
    51 packets transmitted, 30 packets received, 61% packet loss
    round-trip min/avg/max = 0.616/1.861/5.02 ms


- ~~What you lose, is the continous reading of the RTT (you only get the first one)~~ integrated since tping 6.1
- What you win is a clear, timestamped view when and how long a target host went off or online

## Installation
- download latest release
- copy tping.sh to your linux machine
- make script executable

        schwupp@linux:~$ chmod +x tping.sh

- take a look at the parameters

        schwupp@linux:~$ tping.sh -h

- ping your first target with IP or Hostname

        schwupp@linux:~$ tping.sh 8.8.8.8
        
## Additional Parameters/Features
#### debug/verbose output (-d)
print some verbose output with -d switch
#### deadtime (-W \<seconds\>)
Specify timeout of ping in seconds, simply passed to wrapped ping command
#### interval (-i \<seconds\>)
Specify interval of backgroung-pings. **Not** depending on wrapped ping command. Default 1 second.
#### fuzzy-logic (-f \<# of pings\>)
Number of pings that may fail, but still keep target status "up". Target will go "down" after #+1 failed pings. Useful to set >0 on unrealiable networks like cellular, where packetloss is expected. Default 0, so target goes "down" after the 0+1 = first failed ping.
#### static legacy mode (-s)
Version 6.0 introduced a dynamic "follow-mode" as default, which allows to see rtt of every single ping command. Before 6.0 you could only see the rtt when state changes occured. Those working with tping sice the beginning might got used to the fact, that the tping-output-line is always completely frozen and if you see something change, it means that your ping-host got lost and your adrenalin-level will rise immediately. For preventing network-admin heart-attacks because of the new dynamic output - use this parameter.
#### AAAA DNS Support
Since v3.1 tping defaults to IPv6 (AAAA) records when resolving DNS. When AAAA-record is unavailable, tping falls back to IPv4 A-record. If you want to disable this (i.e. IPv6 is not running, script should not waste time with it), you can temporarily use "-4" switch with each command or permanently set "ipv=4" instead of "ipv=6" in preamble of the script.
