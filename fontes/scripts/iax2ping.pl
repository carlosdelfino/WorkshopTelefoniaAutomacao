#!/usr/bin/perl -w
use IO::Socket;
$target = shift; #"192.168.0.255";
$target_port = 4569;

socket(PING, PF_INET, SOCK_DGRAM, getprotobyname("udp"));


$src_call = "8000"; #8000 most siginificant bit is IAX packet type full ... required for a poke etc...
$dst_call = "0000";
$timestamp = "00000000";
$outbound_seq = "00";
$inbound_seq = "00";
$type = "06"; #IAX_Control
$iax_type = "1e"; #POKE
$msg = pack "H24", $src_call . $dst_call . $timestamp . $outbound_seq . $inbound_seq . $type . $iax_type;

$ipaddr = inet_aton($target);
$sendto = sockaddr_in($target_port,$ipaddr);

send(PING, $msg, 0, $sendto) == length($msg) or die "cannot send to $target : $target_port : $!\n";

$MAXLEN = 1024;
$TIMEOUT = 5;

eval {
	local $SIG{ALRM} = sub { die "alarm time out"; };
	alarm $TIMEOUT;

	while (1) {
		$recvfrom = recv(PING, $msg, $MAXLEN, 0) or die "recv: $!";
		($port, $ipaddr) = sockaddr_in($recvfrom);
		$respaddr = inet_ntoa($ipaddr);
		print "Response from $respaddr : $port\n";
	}

};
