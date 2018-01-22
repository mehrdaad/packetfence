#!/usr/bin/perl

=head1 NAME

Locationlog

=cut

=head1 DESCRIPTION

unit test for Locationlog

=cut

use strict;
use warnings;
#
use lib '/usr/local/pf/lib';
use Date::Parse;
use pf::dal::node;
use pf::dal::locationlog;

BEGIN {
    #include test libs
    use lib qw(/usr/local/pf/t);
    #Module for overriding configuration paths
    use setup_test_config;
}

#truncate the locationlog table
pf::dal::locationlog->remove_items();

#insert known data
my %values = (
    mac                 => '00:01:02:03:04:05',
    switch              => '0.0.0.1',
    switch_ip           => '0.0.0.2',
    switch_mac          => '06:07:08:09:0a:0b',
    port                => '1234',
    vlan                => '99',
    role                => 'test role',
    connection_sub_type => 'test connection_sub_type',
    connection_type     => 'Inline',
    dot1x_username      => 'test dot1x_username',
    ssid                => 'test ssid',
    stripped_user_name  => 'test stripped_user_name',
    realm               => 'test realm',
    ifDesc              => 'test ifDesc',
    start_time          => '1970-01-01 00:00:01',
    end_time            => '0000-00-00 00:00:00',
);
my $status = pf::dal::locationlog->create(\%values);

#run tests
use Test::More tests => 39;
use Test::Mojo;
use Test::NoWarnings;
my $t = Test::Mojo->new('pf::UnifiedApi');

$t->get_ok('/api/v1/node/00:01:02:03:04:05/locationlog' => json => { })
  ->json_is('/items/0/mac','00:01:02:03:04:05')
  ->json_is('/items/0/switch','0.0.0.1')
  ->json_is('/items/0/switch_ip','0.0.0.2')
  ->json_is('/items/0/switch_mac','06:07:08:09:0a:0b')
  ->json_is('/items/0/port','1234')
  ->json_is('/items/0/vlan','99')
  ->json_is('/items/0/role','test role')
  ->json_is('/items/0/connection_sub_type','test connection_sub_type')
  ->json_is('/items/0/connection_type','Inline')
  ->json_is('/items/0/dot1x_username','test dot1x_username')
  ->json_is('/items/0/ssid','test ssid')
  ->json_is('/items/0/stripped_user_name','test stripped_user_name')
  ->json_is('/items/0/realm','test realm')
  ->json_is('/items/0/ifDesc','test ifDesc')
  ->json_is('/items/0/start_time','1970-01-01 00:00:01')
  ->json_is('/items/0/start_timestamp',str2time('1970-01-01 00:00:01'))
  ->json_is('/items/0/end_time','0000-00-00 00:00:00')
  ->json_is('/items/0/end_timestamp',str2time('0000-00-00 00:00:00'))
  ->status_is(200);

$t->get_ok('/api/v1/node/00:01:02:03:04:05/latest_locationlog' => json => { })
  ->json_is('/mac','00:01:02:03:04:05')
  ->json_is('/switch','0.0.0.1')
  ->json_is('/switch_ip','0.0.0.2')
  ->json_is('/switch_mac','06:07:08:09:0a:0b')
  ->json_is('/port','1234')
  ->json_is('/vlan','99')
  ->json_is('/role','test role')
  ->json_is('/connection_sub_type','test connection_sub_type')
  ->json_is('/connection_type','Inline')
  ->json_is('/dot1x_username','test dot1x_username')
  ->json_is('/ssid','test ssid')
  ->json_is('/stripped_user_name','test stripped_user_name')
  ->json_is('/realm','test realm')
  ->json_is('/ifDesc','test ifDesc')
  ->json_is('/start_time','1970-01-01 00:00:01')
  ->json_is('/end_time','0000-00-00 00:00:00')
  ->status_is(200);

#truncate the locationlog table
pf::dal::locationlog->remove_items();
  
  
=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2018 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
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
