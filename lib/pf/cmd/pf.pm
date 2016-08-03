package pf::cmd::pf;
=head1 NAME

pf::cmd::pf

=head1 DESCRIPTION

Handles internal PacketFence CLI commands called using 'pfcmd'

=head1 SYNOPSIS

pfcmd <command> [options]

 Commands
  cache                       | manage the cache subsystem
  checkup                     | perform a sanity checkup and report any problems
  class                       | view violation classes
  configfiles                 | push or pull configfiles into/from database
  configreload                | reload the configution
  fingerbank                  | Fingerbank related commands
  floatingnetworkdeviceconfig | query/modify floating network devices configuration parameters
  help                        | show help for pfcmd commands
  ifoctetshistorymac          | accounting history
  ifoctetshistoryswitch       | accounting history
  ifoctetshistoryuser         | accounting history
  import                      | bulk import of information into the database
  ipmachistory                | IP/MAC history
  locationhistorymac          | Switch/Port history
  locationhistoryswitch       | Switch/Port history
  networkconfig               | query/modify network configuration parameters
  node                        | manipulate node entries
  pfconfig                    | interact with pfconfig
  portalprofileconfig         | query/modify portal profile configuration parameters
  reload                      | rebuild fingerprint or violations tables without restart
  service                     | start/stop/restart and get PF daemon status
  schedule                    | Nessus scan scheduling
  switchconfig                | query/modify switches.conf configuration parameters
  version                     | output version information
  violationconfig             | query/modify violations.conf configuration parameters

Please view "pfcmd help <command>" for details on each option


=head1 DESCRIPTION

pf::cmd::pf

=cut

use strict;
use warnings;
use pf::cmd::pf::help;
use base qw(pf::cmd::subcmd);

sub helpActionCmd { "pf::cmd::pf::help" }

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

Minor parts of this file may have been contributed. See CREDITS.

=head1 COPYRIGHT

Copyright (C) 2005-2016 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and::or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

