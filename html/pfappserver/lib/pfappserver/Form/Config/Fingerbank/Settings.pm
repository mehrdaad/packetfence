package pfappserver::Form::Config::Fingerbank::Settings;

=head1 NAME

pfappserver::Form::Config::Fingerbank::Settings

=head1 DESCRIPTION

Form definition to modify Fingerbank configuration

=cut

use HTML::FormHandler::Moose;

use fingerbank::Config;
use pf::log;

extends 'pfappserver::Base::Form';
with 'pfappserver::Base::Form::Role::Help';

sub field_list {
    my ( $self ) = @_;

    my $list = [];

    my $config = fingerbank::Config::get_config;
    my $config_doc = fingerbank::Config::get_documentation;



    foreach my $section ( keys %$config ) {
        push @$list, $section => {id => $section, type => 'Compound'};
        foreach my $parameter ( keys %{$config->{$section}} ) {
            my $field_name = $section . "." . $parameter;
            my $field_doc = $config_doc->{$field_name};
            $field_doc->{description} =~ s/\n//sg;

            my $field = {
                id      => $field_name,
                label   => $field_name,
#                element_attr => { 'placeholder' => $config_defaults->{$field_name} },
                tags => {
                    after_element   => \&help,
                    help            => $field_doc->{description},
                },
            };

            my $type = $field_doc->{type};
            if ($type eq 'toggle') {
                $field->{type}            = 'Toggle';
                $field->{checkbox_value}  = 'enabled';
                $field->{unchecked_value} = 'disabled';
            } 
            elsif ($type eq 'numeric') {
                $field->{type} = 'PosInteger';
            }
            else {
                $field->{type} = 'Text';
                $field->{element_class} = ['input-xxlarge'];
            }

            push ( @$list, $field_name => $field );
        }
    }

    return $list;
}

=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

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

__PACKAGE__->meta->make_immutable unless $ENV{"PF_SKIP_MAKE_IMMUTABLE"};
1;
