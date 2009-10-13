# $Id$

package EnsEMBL::Web::ZMenu::Oligo;

use strict;

use CGI qw(escapeHTML);

use base qw(EnsEMBL::Web::ZMenu);

sub content {
  my $self = shift;
  
  my $object       = $self->object;
  my $id           = $object->param('id');
  my $db           = $object->param('fdb') || $object->param('db') || 'core';
  my $object_type  = $object->param('ftype');
  my $array_name   = $object->param('array');
  my $db_adaptor   = $object->database(lc($db));
  my $adaptor_name = "get_${object_type}Adaptor";
  my $feat_adap    = $db_adaptor->$adaptor_name; 
  my $type         = 'Individual probes:';
  my $features     = [];

  # details of each probe within the probe set on the array that are found within the slice
  my ($r_name, $r_start, $r_end) = $object->param('r') =~ /(\w+):(\d+)-(\d+)/;
  my %probes;
  
  if ($object->param('ptype') ne 'probe') {
    $features = $feat_adap->can('fetch_all_by_hit_name') ? $feat_adap->fetch_all_by_hit_name($id) : 
          $feat_adap->can('fetch_all_by_probeset') ? $feat_adap->fetch_all_by_probeset($id) : [];
  }
  
  if (scalar @$features == 0 && $feat_adap->can('fetch_all_by_Probe')) {
    my $probe_obj = $db_adaptor->get_ProbeAdaptor->fetch_by_array_probe_probeset_name($object->param('array'), $id);
    
    $features = $feat_adap->fetch_all_by_Probe($probe_obj);
    
    $self->caption("Probe: $id");
  } else {
    $self->caption("Probe set: $id");
  }
  
  $self->add_entry({ 
    label => 'View all probe hits',
    link  => $object->_url({
      type   => 'Location',
      action => 'Genome',
      id     => $id,
      fdb    => 'funcgen',
      ftype  => $object_type,
      ptype  => $object->param('ptype'),
      db     => 'core'
    })
  });

  foreach (@$features){ 
    my $op         = $_->probe; 
    my $of_name    = $_->probe->get_probename($array_name);
    my $of_sr_name = $_->seq_region_name;
    
    next if $of_sr_name ne $r_name;
    
    my $of_start = $_->seq_region_start;
    my $of_end   = $_->seq_region_end;
    
    next if ($of_start > $r_end) || ($of_end < $r_start);
    
    $probes{$of_name}{'chr'}   = $of_sr_name;
    $probes{$of_name}{'start'} = $of_start;
    $probes{$of_name}{'end'}   = $of_end;
    $probes{$of_name}{'loc'}   = $of_start . 'bp-' . $of_end . 'bp';
  }
  
  foreach my $probe (sort {
    $probes{$a}->{'chr'}   <=> $probes{$b}->{'chr'} ||
    $probes{$a}->{'start'} <=> $probes{$b}->{'start'} ||
    $probes{$a}->{'stop'}  <=> $probes{$b}->{'stop'}
  } keys %probes) {
    $self->add_entry({
      type  => $type,
      label => "$probe ($probes{$probe}->{'loc'})",
    });
    
    $type = ' ';
  }
}

1;
