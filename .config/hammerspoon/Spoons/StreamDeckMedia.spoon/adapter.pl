# Host for adapter.dylib. See the comment at the top of adapter.m for why this
# runs under /usr/bin/perl and not under Hammerspoon: perl is an Apple platform
# binary, which is what MediaRemote checks before answering.
#
# dl_install_xsub is the way in without writing XS glue -- mr_run ignores the two
# arguments perl passes an XSUB.
use strict;
use warnings;
require DynaLoader;

my $dylib = $ARGV[0] or die "usage: adapter.pl <path to adapter.dylib>\n";
my $lib = DynaLoader::dl_load_file($dylib, 0x01)
    or die "dl_load_file: " . (DynaLoader::dl_error() // 'unknown') . "\n";
my $sym = DynaLoader::dl_find_symbol($lib, 'mr_run')
    or die "dl_find_symbol(mr_run): " . (DynaLoader::dl_error() // 'unknown') . "\n";
DynaLoader::dl_install_xsub('main::mr_run', $sym);
mr_run();
