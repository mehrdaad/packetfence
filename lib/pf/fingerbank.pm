package pf::fingerbank;

=head1 NAME

pf::fingerbank

=head1 DESCRIPTION

Methods to interact with Fingerbank librairy

=cut

use strict;
use warnings;

use JSON::MaybeXS;

use fingerbank::Model::DHCP_Fingerprint;
use fingerbank::Model::DHCP_Vendor;
use fingerbank::Model::MAC_Vendor;
use fingerbank::Model::User_Agent;
use fingerbank::Query;
use fingerbank::FilePath;
use fingerbank::Model::Endpoint;
use fingerbank::Util;
use fingerbank::DB_Factory;
use fingerbank::Constant qw($UPSTREAM_SCHEMA $MYSQL_DB_TYPE);
use pf::cluster;
use pf::constants;
use pf::constants::fingerbank qw($RATE_LIMIT);
use pf::error qw(is_success);

use pf::client;
use pf::error qw(is_error);
use pf::CHI;
use pf::log;
use pf::node qw(node_modify);
use pf::StatsD::Timer;
use fingerbank::Config;

our @fingerbank_based_violation_triggers = ('Device', 'DHCP_Fingerprint', 'DHCP_Vendor', 'MAC_Vendor', 'User_Agent');

our %ACTION_MAP = (
    "update-upstream-db" => sub {
        pf::fingerbank::_update_fingerbank_component("Upstream database", sub{
            my ($status, $status_msg) = fingerbank::DB::update_upstream();
            return ($status, $status_msg);
        });
    },
);

our %ACTION_MAP_CONDITION = (
    "update-upstream-db" => sub {
        return $TRUE;
    },
);

use fingerbank::Config;
$fingerbank::Config::CACHE = cache();

=head1 METHODS

=head2 process

=cut

sub process {
    my $timer = pf::StatsD::Timer->new();
    my ( $mac ) = @_;
    my $logger = pf::log::get_logger;

    my $cache = cache();
    # Rate limit the fingerbank requests based on the partial query params (the ones that are passed)
    # Querying for a resultset
    my $query_args = endpoint_attributes($mac);
    my $query_result = _query($query_args);

    unless(defined($query_result)) {
        $logger->warn("Unable to perform a Fingerbank lookup for device with MAC address '$mac'");
        return "unknown";
    }

    # Processing the device class based on it's parents
    my ( $class, $parents ) = _parse_parents($query_result);

    # Updating the node device type based on the result
    node_modify( $mac, (
        'device_type'   => $query_result->{'device'}{'name'},
        'device_class'  => $class,
        'device_version' => $query_result->{'version'},
        'device_score' => $query_result->{'score'},
    ) );

    _trigger_violations($query_args, $query_result, $parents);

    return $query_result->{'device'}{'name'};
}

=head2 endpoint_attributes

Given a MAC address, collect all the latest known data profiling attributes.

Currently done via a call to the Fingerbank collector

=cut

sub endpoint_attributes {
    my ($mac) = @_;

    # TODO: move the core of talking to the collector into the perl lib
    my $ua = LWP::UserAgent->new;
    $ua->timeout(1);
    
    my $url = URI->new("http://127.0.0.1:8080/endpoint_data/".$mac);

    my $req = HTTP::Request->new(GET => $url->as_string);
    $req->header(Authorization => "Token ".fingerbank::Config::get_config->{'upstream'}{'api_key'});

    my $res = $ua->request($req);
    if ($res->is_success) {
        return decode_json($res->decoded_content);
    }
    else {
        get_logger->error("Error while communicating with the Fingerbank collector. ".$res->status_line);
        return undef;
    }
}

=head2 _query

=cut

sub _query {
    my $timer = pf::StatsD::Timer->new({level => 7});
    my ( $args ) = @_;
    my $logger = pf::log::get_logger;

    my $fingerbank = fingerbank::Query->new(cache => cache());
    return $fingerbank->match($args);
}

=head2 _trigger_violations

=cut

sub _trigger_violations {
    my $timer = pf::StatsD::Timer->new({level => 7});
    my ( $query_args, $query_result, $parents ) = @_;
    my $logger = pf::log::get_logger;

    my $mac = $query_args->{'mac'};

    my $apiclient = pf::client::getClient;

    my %violation_data = (
        'mac'   => $mac,
        'tid'   => 'new_dhcp_info',
        'type'  => 'internal',
    );

    $apiclient->notify('trigger_violation', %violation_data);

}

=head2 _parse_parents

Parsing the parents into an array of IDs to be able to trigger violations based on them.

Also, looking at the top-level parent to determine the device class

=cut

sub _parse_parents {
    my ( $args ) = @_;
    my $logger = pf::log::get_logger;

    my $class;
    my @parents = ();

    # It is possible that a device doesn't have any parent. We need to handle that case first
    if ( !defined($args->{'device'}{'parents'}) || !@{ $args->{'device'}{'parents'} } ) {
        $class = $args->{'device'}{'name'};
        $logger->debug("Device doesn't have any parent. We use the device name '$class' as class.");
        return ( $class, \@parents );
    }

    foreach my $parent ( @{ $args->{'device'}{'parents'} } ) {
        push @parents, $parent->{'id'};
        next if $parent->{'parent_id'};
        $class = $parent->{'name'};
        $logger->debug("Device does have parent(s). Returning top-level parent name '$class' as class");
    }

    return ( $class, \@parents );
}

=head2 is_a

Testing which "kind" of device a specific type is.

Currently handled "kind" of device (based on Fingerbank device classes):
- Windows
- Macintosh
- Generic Android
- Apple iPod, iPhone or iPad

=cut

sub is_a {
    my ( $device_type ) = @_;
    my $logger = pf::log::get_logger;

    if ( !defined($device_type) || $device_type eq '' ) {
        $logger->debug("Undefined / invalid device type passed");
        return "unknown";
    }

    $logger->debug("Trying to determine the kind of device for '$device_type' device type");

    my $endpoint = fingerbank::Model::Endpoint->new(name => $device_type, version => undef, score => undef);

    return "Windows" if ( $endpoint->isWindows($device_type) );
    # Macintosh / Mac OS
    return "Macintosh" if ( $endpoint->isMacOS($device_type) );
    # Android
    return "Generic Android" if ( $endpoint->isAndroid($device_type) );
    # Apple IOS
    return "Apple iPod, iPhone or iPad" if ( $endpoint->isIOS($device_type) );

    # Unknown (we were not able to match)
    return "unknown";
}

sub sync_configuration {
    pf::cluster::sync_files([$fingerbank::FilePath::CONF_FILE]);
}

sub sync_local_db {
    pf::cluster::sync_files([$fingerbank::FilePath::LOCAL_DB_FILE]);
    pf::cluster::notify_each_server('chi_cache_clear', 'fingerbank');
}

sub sync_upstream_db {
    pf::cluster::sync_files([$fingerbank::FilePath::UPSTREAM_DB_FILE], async => $TRUE);
    pf::cluster::notify_each_server('chi_cache_clear', 'fingerbank');
}

=head2 mac_vendor_from_mac

=cut

sub mac_vendor_from_mac {
    my $timer = pf::StatsD::Timer->new({level => 8});
    my ($mac) = @_;
    my $mac_oui = $mac;
    $mac_oui =~ s/[:|\s|-]//g;          # Removing separators
    $mac_oui = lc($mac_oui);            # Lowercasing
    $mac_oui = substr($mac_oui, 0, 6);  # Only keep first 6 characters (OUI)
    my $trigger_query;
    $trigger_query->{'mac'} = $mac_oui;
    my ( $status, $result ) = "fingerbank::Model::MAC_Vendor"->find([$trigger_query, { columns => ['id'] }]);
    return undef if is_error($status);

    ( $status, $result ) = "fingerbank::Model::MAC_Vendor"->read($result->id);
    return $result;
}

=head2 _update_fingerbank_component

Update a Fingerbank component and validate that it succeeds

=cut

sub _update_fingerbank_component {
    my ($name, $sub) = @_;
    my $logger = get_logger;

    my ($status, $status_msg) = $sub->();

    if(fingerbank::Util::is_success($status)){
        $logger->info("Successfully updated $name");
    }
    else {
        my $msg = "Couldn't update $name, code : $status";
        $msg .= ", msg : $status_msg" if(defined($status_msg));
        $logger->error($msg);
    }
    return ($status, $status_msg);
}

sub cache {
    return pf::CHI->new( namespace => 'fingerbank' );
}

=head2 device_name_to_device_id

Find the device ID given its name
Also makes use of the cache

=cut

sub device_name_to_device_id {
    my ($device_name) = @_;
    my $id = cache()->compute_with_undef("device_name_to_device_id-$device_name", sub {
        my ($status, $fbdevice) = fingerbank::Model::Device->find([{name => $device_name}]);
        if(is_success($status)) {
            return $fbdevice->id;
        }
        else {
            return undef;
        }
    });
    return $id;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

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
