#!/usr/bin/perl

=head1 NAME

radius

=head1 DESCRIPTION

unit test for radius

=cut

use strict;
use warnings;
#
use lib '/usr/local/pf/lib';

our @tests;

BEGIN {
    #include test libs
    use lib qw(/usr/local/pf/t);

    #Module for overriding configuration paths
    use setup_test_config;
    @tests = (
        {
            name           => 'reply:Packetfence-Raw',
            value          => 'Name=bob',
            expected_reply => {
                'reply:Name' => 'bob',
            },
        },
        {
            name           => 'Packetfence-Raw',
            value          => 'Name:bob',
            expected_reply => {
                'reply:Name' => 'bob',
            },
        },
        {
            name           => 'reply:Packetfence-Raw',
            value          => 'Name=bob',
            expected_reply => {
                'reply:Name' => 'bob',
            },
        },
        {
            name           => 'reply:Packetfence-Raw',
            value          => 'Name = bob',
            expected_reply => {
                'reply:Name' => 'bob',
            },
        },
        {
            name           => 'reply:Packetfence-Raw',
            value          => 'Name:bob=hope',
            expected_reply => {
                'reply:Name:bob' => 'hope',
            },
        },
        {
            name           => 'reply:Id',
            value          => 'Name:bob',
            expected_reply => { },
        },
        {
            name           => 'Id',
            value          => 'Name:bob',
            expected_reply => { },
        },
        {
            name           => 'reply:Packetfence-Raw',
            value          => ['Name1=bob', 'Name2=bob'],
            expected_reply => {
                'reply:Name1' => 'bob',
                'reply:Name2' => 'bob',
            },
        },
    );
}

use pf::access_filter::radius;
use Test::More tests => 1 + (scalar @tests * 1);

#This test will running last
use Test::NoWarnings;
my $filter = pf::access_filter::radius->new;


my $i  = 1;
for my $test (@tests) {
    my %reply;
    $filter->updateAnswerNameValue($test->{name}, $test->{value}, \%reply);
    is_deeply(\%reply, $test->{expected_reply}, "Test $i");
    $i++;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2020 Inverse inc.

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

