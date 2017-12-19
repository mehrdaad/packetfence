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
use fingerbank::Constant qw($UPSTREAM_SCHEMA);
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
use fingerbank::Collector;
use POSIX::AtFork;
use DateTime;
use DateTime::Format::RFC3339;

# Do not remove, even if its not explicitely used. When taking collector requests out of the cache, this must be imported.
use URI::http;

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

my $collector;
my $collector_ua;

=head1 METHODS

=head2 process

=cut

sub process {
    my $timer = pf::StatsD::Timer->new();
    my ( $mac ) = @_;
    my $logger = pf::log::get_logger;

    my $cache = cache();
    my $cache_key = "pf::fingerbank::process($mac)";

    my $process_timestamp = $cache->compute($cache_key, sub {
        return DateTime->now(); 
    });

    # Querying for a resultset
    my $query_args = endpoint_attributes($mac);

    unless(defined($query_args)) {
        $logger->error("Unable to fetch query arguments for Fingerbank query. Aborting.");
        return $FALSE;
    }

    $query_args->{mac} = $mac;

    if($query_args->{last_updated}->compare($process_timestamp) <= 0) {
        $logger->info("No recent data found for $mac, will not trigger device profiling");
        return $TRUE;
    }
    else {
        $cache->set($cache_key, DateTime->now());

        my $query_result = _query($query_args);

        unless(defined($query_result)) {
            $logger->warn("Unable to perform a Fingerbank lookup for device with MAC address '$mac'");
            return $FALSE;
        }

        # Processing the device class based on it's parents
        my ( $top_level_parent, $parents ) = _parse_parents($query_result);
        $query_result->{device_class} = find_device_class($top_level_parent, $query_result->{'device'}{'name'});
        $query_result->{parents} = $parents;

        record_result($mac, $query_args, $query_result);

        _trigger_violations($query_args, $query_result, $parents);
        return $TRUE;
    }
}

=head2 endpoint_attributes

Given a MAC address, collect all the latest known data profiling attributes.

Currently done via a call to the Fingerbank collector

=cut

sub endpoint_attributes {
    my ($mac) = @_;

    $collector //= fingerbank::Collector->new_from_config;
    $collector_ua //= $collector->get_lwp_client();
    
    my $req = cache()->compute("pf::fingerbank::endpoint_attributes::request::$mac", sub {
        $collector->build_request("GET", "/endpoint_data/$mac");
    });

    my $res = $collector_ua->request($req);
    if ($res->is_success) {
        my $data = decode_json($res->decoded_content);
        # Change the last_updated into a DateTime
        my $f = DateTime::Format::RFC3339->new();
        $data->{last_updated} = $f->parse_datetime( $data->{last_updated} );
        return $data;
    }
    else {
        get_logger->error("Error while communicating with the Fingerbank collector. ".$res->status_line);
        return undef;
    }
}

=head2 record_result

Given a MAC address, the endpoint attributes (from the collector) and the Fingerbank result, record the necessary attributes in the database.

=cut

sub record_result {
    my ($mac, $attributes, $query_result) = @_;

    my %attr_map = (
        most_accurate_user_agent => "user_agent",
        map { $_ => $_ } qw(dhcp_fingerprint dhcp_vendor dhcp6_fingerprint dhcp6_enterprise),
    );

    node_modify( $mac, (
        'device_type'   => $query_result->{'device'}{'name'},
        'device_class'  => $query_result->{device_class},
        'device_version' => $query_result->{'version'},
        'device_score' => $query_result->{'score'},
        map { $attr_map{$_} => $attributes->{$_} } keys(%attr_map),
    ) );

}

=head2 update_collector_endpoint_data

Updates the endpoint data in the collector for a specific MAC address

=cut

sub update_collector_endpoint_data {
    my ($mac, $data) = @_;

    $collector //= fingerbank::Collector->new_from_config;
    $collector_ua //= $collector->get_lwp_client();
    
    my $req = cache()->compute("pf::fingerbank::update_collector_endpoint_data::request::$mac", sub {
        $collector->build_request("PATCH", "/endpoint_data/$mac");
    });
    $req->content(encode_json($data));

    my $res = $collector_ua->request($req);
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

=head2 find_device_class

Given a device, find its device class

If the device is one of %fingerbank::Constant::DEVICE_CLASS_IDS, then that will be the device class.

Otherwise, the top level parent will be the device class

=cut

sub find_device_class {
    my ($top_level_parent, $device_name) = @_;
    my $logger = get_logger;
    my $result = cache()->compute("pf::fingerbank::find_device_class($top_level_parent,$device_name)", sub {
        while (my ($k, $other_device_id) = each(%fingerbank::Constant::DEVICE_CLASS_IDS)) {
            $logger->debug("Checking if device $device_name is a $other_device_id");
            if(fingerbank::Model::Device->is_a($device_name, $other_device_id)) {
                my $other_device_name = fingerbank::Model::Device->read($other_device_id)->name; 
                $logger->info("Device $device_name is a $other_device_name");
                return $other_device_name;
            }
        }
        $logger->debug("Device $device_name is not part of any special OS class, taking top level parent $top_level_parent");
        return $top_level_parent;
    });
    return $result;
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

=head2 CLONE

Clear the cache in a thread environment

=cut

sub CLONE {
    $collector_ua = undef;
    $collector = undef;
}

POSIX::AtFork->add_to_child(\&CLONE);

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
