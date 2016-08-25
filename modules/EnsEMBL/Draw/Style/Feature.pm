=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

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

package EnsEMBL::Draw::Style::Feature;

=pod
Renders a track as a series of simple rectangular blocks

Also a parent module to most styles that render individual features
rather than graphs or other aggregate data.

This module expects data in the following format:

  $data = [
            {
            'metadata' => {},
            'features' => [
                {
                'start'         => 123456,
                'end'           => 123789,
                'colour'        => 'red',                             # mandatory unless bordercolour set
                'bordercolour'  => 'black',                           # optional
                'label'         => 'Feature 1',                       # optional
                'label_colour'  => 'red',                             # optional
                'join_colour'   => 'red',                             # optional
                'href'          => '/Location/View?r=123456-124789',  # optional  
                'title'         => 'Some text goes here',             # optional  
                },
              ],
            }
          ];
=cut

use strict;
use warnings;
no warnings 'uninitialized';

use List::Util qw(max);

use parent qw(EnsEMBL::Draw::Style);

sub create_glyphs {
### Create all the glyphs required by this style
### @return Array of EnsEMBL::Web::Glyph objects
  my $self = shift;

  my $data            = $self->data;
  my $image_config    = $self->image_config;
  my $track_config    = $self->track_config;
  ## Set some track-wide variables
  my $slice_width     = $image_config->container_width;
  my $bumped          = $track_config->get('bumped');
  my $vspacing        = defined($track_config->get('vspacing')) ? $track_config->get('vspacing') : 4;
  my $label_padding   = 10; ## Prevent labels from running into one another
  ## In case the file contains multiple tracks, start each subtrack below the previous one
  my $y_start         = $track_config->get('y_start') || 0;
  my $subtrack_start  = $y_start;
  my $label_height    = 0;
  my $total_height    = 0;

  ## Strand settings
  foreach my $subtrack (@$data) {
    ## Keep track of all the feature heights so we can calculate a correct total height
    my $heights = {};

    ## Draw title over track
    if ($track_config->get('show_subtitle')) {
      $self->track_config->set('subtitle_y', 0);
      my $subtitle_height = $self->draw_subtitle($subtrack->{'metadata'}, $total_height);
      $subtrack_start .= $subtitle_height + 2;
    }

    my @features = @{$subtrack->{'features'}||[]}; 
    my $label_height;

    ## FIRST LOOP - process features
    foreach my $feature (@features) {
      ## Are we drawing transcripts or just genes?
      #next if $feature->{'type'} && $feature->{'type'} eq 'gene'        && !$track_config->{'hide_transcripts'};
      #next if $feature->{'type'} && $feature->{'type'} eq 'transcript'  && $track_config->{'hide_transcripts'};

      my $text_info   = $self->get_text_info($feature->{'label'});
      my $show_label  = $track_config->get('show_labels') && $feature->{'label'} ? 1 : 0;
      my $overlay     = $track_config->get('label_overlay');

      ## Default colours, if none set in feature
      ## Note that a feature must have either a border colour or a fill colour,
      ## but doesn't need to have both. However we do set join and label colours,
      ## because other configuration options determine whether they are used
      if (!$feature->{'bordercolour'}) {
        $feature->{'colour'} ||= $track_config->get('default_colour') || $subtrack->{'metadata'}{'colour'} || 'black';
      }
      $feature->{'join_colour'}   ||= $feature->{'colour'} || $feature->{'bordercolour'};
      $feature->{'label_colour'}  ||= $feature->{'colour'} || $feature->{'bordercolour'};
      $feature->{'_bstart'} = $feature->{'start'};
      $feature->{'_bend'} = $feature->{'end'};
      if ($show_label && !$overlay) {
        my $lwidth_bp = ($text_info->{'width'} + $label_padding) / $self->{'pix_per_bp'};
        $feature->{'_bend'} = max($feature->{'_bend'},$feature->{'_bstart'}+$lwidth_bp);
        $label_height = max($label_height,$text_info->{'height'});
      }
    }
    EnsEMBL::Draw::GlyphSet::do_bump($self,\@features);

    ## SECOND LOOP - draw features
    foreach my $feature (@features) {
      my $new_y;
      my $feature_row = 0;
      my $label_row   = 0;
      my $text_info   = $self->get_text_info($feature->{'label'});
      ## Work out if we're bumping the whole feature or just the label
      if ($bumped) {
        my $bump = $feature->{'_bump'};
        $label_row   = $bump unless $bumped eq 'features_only';
        $feature_row = $bump unless $bumped eq 'labels_only';       
      }
      next if $feature_row < 0; ## Bumping code returns -1 if there's a problem 

      ## Work out where to place the feature
      my $feature_height  = $track_config->get('height') || $text_info->{'height'};
      my $feature_width   = $feature->{'end'} - $feature->{'start'} + 1;

      if ($feature_width == 0) {
        ## Fix for single base-pair features
        $feature_width = 1;
      }
      else {
        ## Truncate to viewport - but don't alter feature hash because we may need it
        my ($drawn_start, $drawn_end) = $feature->{'end'} - $feature->{'start'}
                                        ? ($feature->{'start'}, $feature->{'end'})
                                        : ($feature->{'end'}, $feature->{'start'});
        $drawn_start        = 0 if $drawn_start < 0;
        $drawn_end          = $slice_width if $drawn_end > $slice_width;
        $feature_width      = $drawn_end - $drawn_start + 1; 
      }

      my $labels_height   = $label_row * $label_height;
      ## Only "ordinary" bumping requires adding the label to the feature height
      my $add_labels      = ($bumped && $bumped eq '1') ? $labels_height : 0;
      my $y               = $subtrack_start + ($feature_row * ($feature_height + $vspacing)) + $add_labels;

      my $position  = {
                      'y'           => $y,
                      'width'       => $feature_width,
                      'height'      => $feature_height,
                      'image_width' => $slice_width,
                      };
      
      ## Get the real height of the feature e.g. if it includes any tags or extra glyphs
      $self->draw_feature($feature, $position);
      my $extra = $self->track_config->get('extra_height') || 0;
      my $approx_height = $feature_height + $extra;
      push @{$heights->{$feature_row}}, ($approx_height + $vspacing + $add_labels);
    
      ## Optional label
      my $show_label  = $track_config->get('show_labels') && $feature->{'label'} ? 1 : 0;
      my $overlay     = $track_config->get('label_overlay');
      my $font_size   = $self->{'font_size'};
      my $text_width  = $text_info->{'width'};
      my $text_height = $text_info->{'height'};

      ## Only overlay labels above a certain feature size
      if (($show_label && $overlay) || $bumped eq 'labels_alongside') {
        ## Reduce text size slightly for wider single-letter labels (A, M, V, W)
        my $bp_textwidth = $position->{'width'} / $self->{'pix_per_bp'};
        my $tmp_textwidth = $bp_textwidth;

        if (($bp_textwidth >= $position->{'width'} && length $feature->{'label'} == 1) || $bumped eq 'labels_alongside') {
          $font_size       *= 0.9;
          my $tmp_text_info = $self->get_text_info($feature->{'label'});
          $text_width       = $tmp_text_info->{'width'};
          $text_height      = $tmp_text_info->{'height'};
          $tmp_textwidth    = $text_width / $self->{'pix_per_bp'};
        }

        $show_label = 0 unless ($tmp_textwidth < $position->{'width'} || $bumped eq 'labels_alongside');
      }

      ## OK, we definitely want a label!
      if ($show_label) {
        my $new_x = $feature->{'start'};
        $new_x = 1 if $new_x < 1;
        if ($overlay) {
          $new_y = $position->{'y'} + $approx_height - $text_height;
        }
        elsif ($bumped eq 'labels_alongside') {
          $new_y = $position->{'y'} + $approx_height - $text_height;
          $new_x = $feature->{'end'} + 4 / $self->{'pix_per_bp'};
        }
        else {
          $new_y = $position->{'y'} + $approx_height;
          $new_y += $labels_height if ($bumped eq 'labels_only');
          ## Pad width to match bumped position
          $text_width += 10;
        }

        $position = {
                      'x'           => $new_x,
                      'y'           => $new_y,
                      'height'      => $text_info->{'height'},
                      'width'       => $position->{'width'},
                      'text_width'  => $text_width, 
                      'image_width' => $slice_width,
                      'font_size'   => $font_size,
                    };
        $self->add_label($feature, $position);
      }
    }

    ## Set the height of the track, in case we want anything in the lefthand margin
    my $subtrack_height = 0;
    while (my($row, $values) = each(%$heights)) {
      my $max = max(@$values);
      $subtrack_height += $max;
    }
    $subtrack_start += $subtrack_height;
    $total_height   += $subtrack_height;
    $track_config->set('real_feature_height', $subtrack_height);
    $self->add_messages($subtrack->{'metadata'}, $subtrack_height);
  }
  $self->draw_hidden_bgd($total_height);
  my $track_height = $track_config->get('total_height') || 0;
  $track_config->set('total_height', $track_height + $total_height);

  $track_config->set('y_start', $y_start + $total_height);
  return @{$self->glyphs||[]};
}

sub draw_feature {
### Create a glyph that's a simple filled rectangle
### @param feature Hashref - data for a single feature
### @param position Hashref - information about the feature's size and position
  my ($self, $feature, $position) = @_;

  return unless ($feature->{'colour'} || $feature->{'bordercolour'});

  ## Set parameters
  my $x = $feature->{'start'};
  $x    = 1 if $x < 1;
  my $params = {
                  x            => $x-1,
                  y            => $position->{'y'},
                  width        => $position->{'width'},
                  height       => $position->{'height'},
                  href         => $feature->{'href'},
                  title        => $feature->{'title'},
                  absolutey    => 1,
                };
  $params->{'colour'}       = $feature->{'colour'} if $feature->{'colour'};
  $params->{'bordercolour'} = $feature->{'bordercolour'} if $feature->{'bordercolour'};

  push @{$self->glyphs}, $self->Rect($params);
}

sub add_label {
### Create a text label
### @param feature Hashref - data for a single feature
### @param position Hashref - information about the label's size and position
  my ($self, $feature, $position) = @_;
  my $start = $feature->{'start'};  

  ## Only show labels if they're shorter than the visible portion of the feature
  if ($start < 0) {
    my $feature_visible = $feature->{'end'} * $self->{'pix_per_bp'};
    return unless $feature_visible > $position->{'width'};
  }

  my $colour = $feature->{'label_colour'} || $feature->{'colour'};
  if ($colour) {
    $colour = $self->make_readable($colour);
  }
  else {
    $colour = 'black';
  }

  my $halign = $self->track_config->get('centre_labels') ? 'center' : 'left';

  my $label = {
                x         => $position->{'x'} - 1,
                y         => $position->{'y'},
                height    => $position->{'height'},
                width     => $position->{'width'},
                textwidth => $position->{'text_width'},
                text      => $feature->{'label'},
                font      => $self->{'font_name'},
                colour    => $colour,
                ptsize    => $position->{'font_size'} || $self->{'font_size'},
                halign    => $halign,
                valign    => 'center',
                href      => $feature->{'href'},
                title     => $feature->{'title'},
                absolutey => 1,
              };

  push @{$self->glyphs}, $self->Text($label);
}


1;
