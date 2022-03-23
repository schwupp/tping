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

- What you lose, is the continous reading of the RTT (you only get the first one)
- What you win is a clear, timestamped view when and how long a target host went off or online
