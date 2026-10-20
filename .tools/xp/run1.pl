#!/usr/bin/perl
# run1.pl SECONDS STDOUT STDERR cmd args...  -> prints "<status> <seconds>"
# status: the exit code, "signalN", or "timeout" (the process group is killed).
# macOS has no timeout(1); this is the same on both platforms.
use strict; use Time::HiRes qw(time);
my ($limit, $out, $err, @cmd) = @ARGV;
my $t0 = time; my $pid = fork;
if ($pid == 0) { setpgrp(0,0); open STDOUT, '>', $out; open STDERR, '>', $err; exec @cmd or exit 127; }
my $timedout = 0;
local $SIG{ALRM} = sub { $timedout = 1; kill 'KILL', -$pid; };
alarm $limit; waitpid $pid, 0; my $st = $?; alarm 0;
my $dt = sprintf "%.2f", time - $t0;
if ($timedout) { print "timeout $dt\n" }
elsif ($st & 127) { printf "signal%d %s\n", $st & 127, $dt }
else { printf "%d %s\n", $st >> 8, $dt }
