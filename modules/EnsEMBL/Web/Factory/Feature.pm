package EnsEMBL::Web::Factory::Feature;

### NAME: EnsEMBL::Web::Factory::Feature
### Creates a hash of API objects to be displayed on a karyotype or chromosome

### STATUS: Under development

### DESCRIPTION:
### This factory creates data for "featureview", i.e. a display of data over a 
### large region such as a whole chromosome or even the entire genome. 
### Unlike most Factories it does not create  a single domain object but a hash i
### of key-value pairs, e.g.:
### {'Gene' => Data::Bio::Gene, 'ProbeFeature' => Data::Bio::ProbeFeature};

use strict;
use warnings;
no warnings 'uninitialized';

use EnsEMBL::Web::Data::Bio::Slice;
use EnsEMBL::Web::Data::Bio::Gene;
use EnsEMBL::Web::Data::Bio::Transcript;
use EnsEMBL::Web::Data::Bio::Variation;
use EnsEMBL::Web::Data::Bio::ProbeFeature;
use EnsEMBL::Web::Data::Bio::AlignFeature;
use EnsEMBL::Web::Data::Bio::RegulatoryFeature;
use EnsEMBL::Web::Data::Bio::RegulatoryFactor;
use EnsEMBL::Web::Data::Bio::Xref;
use EnsEMBL::Web::Data::Bio::LRG;

use base qw(EnsEMBL::Web::Factory);

sub createObjects {  
  ### Identifies the type of API object(s) required, based on CGI parameters,
  ### and calls the relevant helper method to create them.
  ### Arguments: None
  ### Returns: undef (data is put into Factory->DataObjects, from where it can
  ### be retrieved by the Model)
  
  my $self     = shift;
  my $db       = $self->param('db') || 'core';
  my $features = {};
  my ($feature_type, $subtype);
  
  ## Are we inputting IDs or searching on a text term?
  if ($self->param('xref_term')) {
    my @exdb  = $self->param('xref_db');
    $features = $self->search_Xref($db, \@exdb, $self->param('xref_term'));
  } else {
    if ($self->type eq 'LRG') {
      $feature_type = 'LRG';
    } else {
      $feature_type = $self->param('ftype') || $self->param('type') || 'ProbeFeature';
    }
    
    if ($self->param('ftype') eq 'ProbeFeature') {
      $db      = 'funcgen';
      $subtype = $self->param('ptype') if $self->param('ptype');
    }
    
    ## deal with xrefs
    if ($feature_type =~ /^Xref_/) {
      ## Don't use split here - external DB name may include underscores!
      ($subtype = $feature_type) =~ s/Xref_//;
      $feature_type = 'Xref';
    }
    
    my $func  = "_create_$feature_type";
    $features = $self->can($func) ? $self->$func($db, $subtype) : [];
  }
  
  $self->DataObjects($self->new_object('Feature', $features, $self->__data)) if keys %$features;
}

sub _create_Domain {
  ### Fetches all the genes for a given domain
  ### Args: db
  ### Returns: hashref of API objects
  
  my ($self, $db) = @_;
  my $id          = $self->param('id');
  my $dbc         = $self->hub->database($db);
  my $a           = $dbc->get_adaptor('Gene');
  my $genes       = $a->fetch_all_by_domain($id);
  
  return unless $genes && ref($genes) eq 'ARRAY';
  return {'Gene' => EnsEMBL::Web::Data::Bio::Gene->new($self->hub, @$genes)};
}

sub _create_Phenotype {
  ### Fetches all the variation features associated with a phenotype
  ### Args: db 
  ### Returns: hashref of API objects
  
  my ($self, $db) = @_; 
  my $slice;
  my $features;
  my $array = [];
  my $id    = $self->param('id');
  my @chrs  = @{$self->hub->species_defs->ENSEMBL_CHROMOSOMES};

  foreach my $chr (@chrs) {
    $slice = $self->hub->database('core')->get_adaptor('Slice')->fetch_by_region("chromosome", $chr);
    my $array2 = $slice->get_all_VariationFeatures_with_annotation(undef, undef, $id);

    push @$array,@$array2 if @$array2;
  }
  return {'Variation' => EnsEMBL::Web::Data::Bio::Variation->new($self->hub, @$array)};
}

sub _create_ProbeFeature {
  ### Fetches Oligo hits plus corresponding transcripts
  ### Args: db, subtype (string)
  ### Returns: hashref of API objects
  
  my ($self, $db, $subtype)  = @_;
  my $probe;
  
  if ($subtype && $subtype eq 'pset') {
    $probe = $self->_generic_create('ProbeFeature', 'fetch_all_by_probeset', $db);
  } else {
    $probe = $self->_create_ProbeFeatures_by_probe_id;
  }
  
  my $probe_trans = $self->_create_ProbeFeatures_linked_transcripts($subtype);
  my $features    = { ProbeFeature => EnsEMBL::Web::Data::Bio::ProbeFeature->new($self->hub, @$probe) };
  
  $features->{'Transcript'} = EnsEMBL::Web::Data::Bio::Transcript->new($self->hub, @$probe_trans) if $probe_trans;
  
  return $features;
}

sub _create_ProbeFeatures_by_probe_id {
  ### Helper method called by _create_ProbeFeature
  ### Fetches the probe features for a given probe id
  ### Args: none
  ### Returns: arrayref of Bio::EnsEMBL::ProbeFeature objects
  
  my $self                  = shift;
  my $db_adaptor            = $self->_get_funcgen_db_adaptor; 
  my $probe_adaptor         = $db_adaptor->get_ProbeAdaptor;  
  my @probe_objs            = @{$probe_adaptor->fetch_all_by_name($self->param('id'))};
  my $probe_obj             = $probe_objs[0];
  my $probe_feature_adaptor = $db_adaptor->get_ProbeFeatureAdaptor;
  my @probe_features        = @{$probe_feature_adaptor->fetch_all_by_Probe($probe_obj)};
  
  return \@probe_features;
}

sub _create_ProbeFeatures_linked_transcripts {
  ### Helper method called by _create_ProbeFeature
  ### Fetches the transcript(s) linked to a probeset
  ### Args: $ptype (string)
  ### Returns: arrayref of Bio::EnsEMBL::Transcript objects
  
  my ($self, $ptype) = @_;
  my $db_adaptor     = $self->_get_funcgen_db_adaptor;
  
  my (@probe_objs, @transcripts, %seen);

  if ($ptype eq 'pset') {
    my $probe_feature_adaptor = $db_adaptor->get_ProbeFeatureAdaptor;
    @probe_objs = @{$probe_feature_adaptor->fetch_all_by_probeset($self->param('id'))};
  } else {
    my $probe_adaptor = $db_adaptor->get_ProbeAdaptor;
    @probe_objs = @{$probe_adaptor->fetch_all_by_name($self->param('id'))};
  }
  
  ## Now retrieve transcript ID and create transcript Objects 
  foreach my $probe (@probe_objs) {
    foreach my $entry (@{$probe->get_all_Transcript_DBEntries}) {
      my $core_db_adaptor    = $self->_get_core_adaptor;
      my $transcript_adaptor = $core_db_adaptor->get_TranscriptAdaptor;
      
      if (!exists $seen{$entry->primary_id}) {
        my $transcript = $transcript_adaptor->fetch_by_stable_id($entry->primary_id);
        push @transcripts, $transcript;
        $seen{$entry->primary_id} = 1;
      }
    }
  }

  return \@transcripts;
}

sub _get_funcgen_db_adaptor {
  ### Helper method used by _create_ProbeFeatures_linked_transcripts
  ### Args: none
  ### Returns: database adaptor
  
  my $self        = shift;
  my $db          = $self->param('fdb') || $self->param('db');
  my $db_adaptor  = $self->database(lc $db);
  
  if (!$db_adaptor) {
    $self->problem('fatal', 'Database Error', "Could not connect to the $db database.");
    return undef;
  }
  
  return $db_adaptor;
}

sub _get_core_adaptor {
  ### Helper method used by _create_ProbeFeatures_linked_transcripts
  ### Args: none
  ### Returns: database adaptor
  
  my $self       = shift;
  my $db_adaptor = $self->hub->database('core');
  
  if (!$db_adaptor) {
    $self->problem('fatal', 'Database Error', 'Could not connect to the core database.');
    return undef;
  }
  
  return $db_adaptor;
}

sub _create_DnaAlignFeature {
  ### Fetches all the DnaAlignFeatures with a given ID, and associated genes
  ### Args: db
  ### Returns: hashref of API objects
  
  my ($self, $db) = @_;
  my $daf         = $self->_generic_create('DnaAlignFeature', 'fetch_all_by_hit_name', $db);
  my $genes       = $self->_generic_create('Gene', 'fetch_all_by_external_name', $db, undef, 'no_errors');
  my $features    = { DnaAlignFeature => EnsEMBL::Web::Data::Bio::AlignFeature->new($self->hub, @$daf) };
  
  $features->{'Gene'} = EnsEMBL::Web::Data::Bio::Gene->new($self->hub, @$genes) if $genes;
  
  return $features;
}

sub _create_ProteinAlignFeature {
  ### Fetches all the DnaAlignFeatures with a given ID, and associated genes
  ### Args: db
  ### Returns: hashref of API objects
  my ($self, $db) = @_;
  my $paf         = $self->_generic_create('ProteinAlignFeature', 'fetch_all_by_hit_name', $db);
  my $genes       = $self->_generic_create('Gene', 'fetch_all_by_external_name', $db, undef, 'no_errors');
  my $features    = { ProteinAlignFeature => EnsEMBL::Web::Data::Bio::AlignFeature->new($self->hub, @$paf) };
  
  $features->{'Gene'} = EnsEMBL::Web::Data::Bio::Gene->new($self->hub, @$genes) if $genes;
  
  return $features;
}

sub create_UserDataFeature {
  my ($self, $logic_name) = @_;
  my $dbs                 = EnsEMBL::Web::DBSQL::DBConnection->new( $self->species );
  my $dba                 = $dbs->get_DBAdaptor('userdata');
  my $features            = [];
  
  return [] unless $dba;

  $dba->dnadb($self->database('core'));

  ## Have to do the fetch per-chromosome, since API doesn't have suitable call
  my $chrs = $self->species_defs->ENSEMBL_CHROMOSOMES;
  
  foreach my $chr (@$chrs) {
    my $slice = $self->database('core')->get_SliceAdaptor->fetch_by_region(undef, $chr);
    push @$features, @{$dba->get_adaptor('DnaAlignFeature')->fetch_all_by_Slice($slice, $logic_name)} if $slice;
  }
  
  return { UserDataAlignFeature => EnsEMBL::Web::Data::Bio::AlignFeature->new($self->hub, @$features) };
}

sub _create_Gene {
  ### Fetches all the genes for a given identifier (usually only one, but could be multiple
  ### Args: db
  ### Returns: hashref containing a Data::Bio::Gene object
  
  my ($self, $db) = @_;
  my $genes       = $self->_generic_create('Gene', $self->param('id') =~ /^ENS/ ? 'fetch_by_stable_id' : 'fetch_all_by_external_name', $db);
  
  return { Gene => EnsEMBL::Web::Data::Bio::Gene->new($self->hub, @$genes) };
}

sub _create_RegulatoryFactor {
  ### Fetches all the regulatory features for a given regulatory factor ID 
  ### Args: db, id (optional)
  ### Returns: hashref containing a Data::Bio::RegulatoryFeature object
  
  my ($self, $db, $id) = @_;
  my $fg_db            = $self->hub->database('funcgen');
  
  if (!$fg_db) {
     warn('Cannot connect to funcgen db');
     return undef;
  }
  
  $id ||= $self->param('id');
  
  if ($id =~ /miR/) {
    my ($transcript_id, $feature_id) = split ':', $id;
    $id = $feature_id;  
  } 

  my $features = $fg_db->get_ExternalFeatureAdaptor->fetch_all_by_display_label($id) || [];

  if (!@$features) {
    my $fset  = $fg_db->get_featureSetAdaptor->fetch_by_name($self->param('fset'));
    my $ftype = $fg_db->get_FeatureTypeAdaptor->fetch_by_name($id);
    $features = $fset->get_Features_by_FeatureType($ftype);
  }

  if (@$features) {
    return { RegulatoryFeature => EnsEMBL::Web::Data::Bio::RegulatoryFeature->new($self->hub, @$features) }
  } else {
    # We have no features so return an error
    $self->problem('no_match', 'Invalid Identifier', "Regulatory Factor $id was not found");
    return undef;
  }
}

sub _create_Xref {
  ### Fetches Xrefs plus corresponding genes
  ### Args: db, subtype (string)
  ### Returns: hashref of API objects
  
  my ($self, $db, $subtype) = @_;
  my $t_features            = [];
  my ($xrefs, $genes); 

  if ($subtype eq 'MIM') {
    my $mim_g    = $self->_generic_create('DBEntry', 'fetch_by_db_accession', [ $db, 'MIM_GENE'   ]);
    my $mim_m    = $self->_generic_create('DBEntry', 'fetch_by_db_accession', [ $db, 'MIM_MORBID' ]);
    @$t_features = (@$mim_g, @$mim_m);
  }  else {
    $t_features = $self->_generic_create('DBEntry', 'fetch_by_db_accession', [ $db, $subtype ]);
  }
  
  ($xrefs, $genes) = $self->_create_XrefArray($t_features, $db, $subtype) if $t_features && ref $t_features eq 'ARRAY';
  
  my $features = { Xref => EnsEMBL::Web::Data::Bio::Xref->new($self->hub, @$xrefs) };
  $features->{'Gene'} = EnsEMBL::Web::Data::Bio::Gene->new($self->hub, @$genes) if $genes;
  
  return $features;
}

sub _create_XrefArray {
  ### Helper method used by _create_Xref
  
  my ($self, $t_features, $db, $subtype) = @_;
  my (@features, @genes);

  foreach my $t (@$t_features) { 
    my @matches = ($t); ## we need to keep each xref and its matching genes together
    my $id      = $t->primary_id;
    my $t_genes = $self->_generic_create('Gene', 'fetch_all_by_external_name', $db, $id, 'no_errors', $subtype); ## get genes for each xref
    
    if ($t_genes && @$t_genes) { 
      push @matches, @$t_genes;
      push @genes, @$t_genes;
    }
    
    push @features, \@matches;
  }

  return (\@features, \@genes);
}

sub _create_LRG {
  ### Fetches LRG region(s)
  ### Args: none
  ### Returns: hashref containing Bio::EnsEMBL::Slice objects
  my $self       = shift;
  my $hub        = $self->hub;
  my $db_adaptor = $hub->database('core');
  
  if (!$db_adaptor) {
    $self->problem('fatal', 'Database Error', 'Could not connect to the core database.');
    return undef;
  }
  
  ## Get LRG slices
  my $sa     = $db_adaptor->get_SliceAdaptor;
  my $slices = [];
  my @ids    = $self->param('id');
  
  if (@ids) {
    push @$slices, $sa->fetch_by_region('lrg', $_) for @ids;
  } else {
    $slices = $sa->fetch_all('lrg', '', 1);
  }
 
  ## Map slices to chromosomal coordinates
  my $mapped_slices = [];
  my $csa           = $hub->database('core',$hub->species)->get_CoordSystemAdaptor;
  my $ama           = $hub->database('core', $hub->species)->get_AssemblyMapperAdaptor;
  my $old_cs        = $csa->fetch_by_name('lrg');
  my $new_cs        = $csa->fetch_by_name('chromosome', $hub->species_defs->ASSEMBLY_NAME);
  my $mapper        = $ama->fetch_by_CoordSystems($old_cs, $new_cs);

  foreach my $s (@$slices) {
    my @coords = $mapper->map($s->seq_region_name, $s->start, $s->end, $s->strand, $old_cs);
    
    push @$mapped_slices, { lrg => $s, chr => $sa->fetch_by_seq_region_id($_->id, $_->start, $_->end) } for @coords;
  }
 
  return { LRG => EnsEMBL::Web::Data::Bio::LRG->new($self->hub, @$mapped_slices) };
}

sub _generic_create {
  ### Helper method used by various _create_ methods to get API objects from the database
  
  my ($self, $object_type, $accessor, $db, $id, $flag, $subtype) = @_;  
  $db ||= 'core';
  
  if (!$id) {
    my @ids = $self->param('id');
    $id = join ' ', @ids;
  } elsif (ref $id eq 'ARRAY') {
    $id = join ' ', @$id;
  }
  
  ## deal with xrefs
  my $xref_db;
  
  if ($object_type eq 'DBEntry') {
    my @A    = @$db;
    $db      = $A[0];
    $xref_db = $A[1];
  }

  if( !$id) {
    return undef; # return empty object if no id
  } else {
    # Get the 'central' database (core, est, vega)
    my $db_adaptor = $self->database(lc $db);
    
    if (!$db_adaptor) {
      $self->problem('fatal', 'Database Error', "Could not connect to the $db database.");
      return undef;
    }
    
    my $adaptor_name = "get_${object_type}Adaptor";
    my $features     = [];
    
    $id =~ s/\s+/ /g;
    $id =~ s/^ //;
    $id =~ s/ $//;
    
    foreach my $fid (split /\s+/, $id) { 
      my $t_features;
      
      if ($xref_db) { 
        eval {
         $t_features = [$db_adaptor->$adaptor_name->$accessor($xref_db, $fid)];
        };
      } elsif ($accessor eq 'fetch_by_stable_id') { ## Hack to get gene stable IDs to work
        eval {
         $t_features = [ $db_adaptor->$adaptor_name->$accessor($fid) ];
        };
      } elsif ($subtype) {
         eval {
         $t_features = $db_adaptor->$adaptor_name->$accessor($fid, $subtype);
        };
      } else { 
        eval {
         $t_features = $db_adaptor->$adaptor_name->$accessor($fid);
        };
      }
      
      ## if no result, check for unmapped features
      if ($t_features && ref($t_features) eq 'ARRAY') {
        if (!@$t_features) {
          my $uoa = $db_adaptor->get_UnmappedObjectAdaptor;
          $t_features = $uoa->fetch_by_identifier($fid);
        } else {
          foreach my $f (@$t_features) {
            next unless $f;
            
            $f->{'_id_'} = $fid;
            push @$features, $f;
          }
        }
      }
    }
    
    return $features if $features && @$features; # Return if we have at least one feature

    # We have no features so return an error
    $self->problem('no_match', 'Invalid Identifier', "$object_type $id was not found") unless $flag eq 'no_errors';
    
    return undef;
  }
}

1;
