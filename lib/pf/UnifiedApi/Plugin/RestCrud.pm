package pf::UnifiedApi::Plugin::RestCrud;

=head1 NAME

pf::UnifiedApi::Plugin::RestCrud -

=cut

=head1 DESCRIPTION

pf::UnifiedApi::Plugins::RestCrud

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw(camelize);

sub register {
    my ($self, $app, $config) = @_;
    my $controller = $config->{controller};
    my $name_prefix = $config->{name} // camelize($controller);
    my $path = $config->{path} // "/$controller";
    my $id_key = $config->{id_key} // 'id';
    my $routes = $app->routes;
    my $r = $routes->any($path)->name($name_prefix);
    $r->get()->to("$controller#list")->name("$name_prefix.list");
    $r->post()->to("$controller#create")->name("$name_prefix.create");
    my $item_path = "/:$id_key";
    $r->get($item_path)->to("$controller#get")->name("$name_prefix.get");
    $r->delete($item_path)->to("$controller#remove")->name("$name_prefix.remove");
    $r->patch($item_path)->to("$controller#update")->name("$name_prefix.update");
    $r->put($item_path)->to("$controller#update")->name("$name_prefix.replace");
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

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

1;
