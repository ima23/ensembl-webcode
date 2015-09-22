=head1 sLICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Web::NewTable::Column;

use strict;
use warnings;

sub new {
  my ($class,$table,$key) = @_;

  my $self = {
    table => $table,
    key => $key,
    conf => {},
  };

  bless $self, $class;
  return $self;
}

sub key { return $_[0]->{'key'}; }

sub value {
  my ($self,$plugin_name,$value) = @_;

  $value ||= '*';
  my $plugin = $self->{'table'}->get_plugin($plugin_name);
  return $plugin->value($self,$value);
}

sub decorate {
  my ($self,$type) = @_;

  $self->{'conf'}{'decorate'} = $type;
}

sub set_type {
  my ($self,$key,$value) = @_;

  $self->{'conf'}{'type'} ||= {};
  $self->{'conf'}{'type'}{$key} = $value;
}

sub set_helptip {
  my ($self,$help) = @_;

  $self->{'conf'}{'help'} = $help;
}

sub colconf { return $_[0]->{'conf'}; }

1;