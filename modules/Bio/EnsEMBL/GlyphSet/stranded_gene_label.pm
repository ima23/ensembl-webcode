#########
# stranded_gene_label replacement for gene_label for image dumping
#
# Author: rmp@sanger.ac.uk
#
#
package Bio::EnsEMBL::GlyphSet::stranded_gene_label;
use strict;
use vars qw(@ISA);
use Bio::EnsEMBL::GlyphSet;
use Bio::EnsEMBL::Glyph::Rect;
use Bio::EnsEMBL::Glyph::Text;
use Bio::EnsEMBL::Glyph::Composite;
use Bump;

@ISA = qw(Bio::EnsEMBL::GlyphSet);

sub init_label {
    my ($self) = @_;
	return if( defined $self->{'config'}->{'_no_label'} );
    my $label = new Bio::EnsEMBL::Glyph::Text({
        'text'      => 'Genes',
        'font'      => 'Small',
        'absolutey' => 1,
    });
    $self->label($label);
}

sub _init {
    my $self = shift;

    my $VirtualContig  = $self->{'container'};
    my $Config         = $self->{'config'};
    my $y              = 0;
    my @bitmap         = undef;
    my $im_width       = $Config->image_width();
    my $type           = $Config->get('stranded_gene_label','src');
    my @allgenes       = $VirtualContig->get_all_Genes_exononly();
    my %highlights;
    @highlights{$self->highlights()} = ();    # build hashkeys of highlight list

    if ($type eq 'all'){
	foreach my $vg ($VirtualContig->get_all_ExternalGenes()){
	    $vg->{'_is_external'} = 1;
	    push (@allgenes, $vg);
	}
    }

    my $ext_col        = $Config->get('stranded_gene_label','ext');
    my $known_col      = $Config->get('stranded_gene_label','known');
    my $unknown_col    = $Config->get('stranded_gene_label','unknown');
    my $pix_per_bp     = $Config->transform->{'scalex'};
    my $bitmap_length  = int($VirtualContig->length * $pix_per_bp);
    my $fontname       = "Tiny";
    my ($font_w_bp,$h) = $Config->texthelper->px2bp($fontname);
    my $w              = $Config->texthelper->width($fontname);
    my %db_names = ( 'HUGO'=>1,'SP'=>1, 'SPTREMBL'=>1, 'SCOP'=>1 );
    for my $vg (@allgenes) {
	
	my ($start, $end, $colour, $label, $hi_colour);
	
	my @coords = ();
	for my $trans ($vg->each_Transcript()) {
	    for my $exon ( $trans->each_Exon_in_context($VirtualContig->id()) ) {
		push @coords, $exon->start();
		push @coords, $exon->end();
	    }
	}
	@coords = sort {$a <=> $b} @coords;
	$start = $coords[0];
	$end   = $coords[-1];   

	unless(defined $vg->{'_is_external'}) {

	    #########
	    # skip if this one isn't on the strand we're drawing
	    #
	    next if(($vg->each_Transcript())[0]->strand_in_context($VirtualContig->id()) != $self->strand());

	    if($vg->is_known()) {
                # this is duplicated  from gene_label.pm, so needs refactoring ...
		$colour = $known_col;
                my @temp_geneDBlinks = $vg->gene->each_DBLink();
	 	
                # find a decent label:
		foreach my $DB_link ( @temp_geneDBlinks ) {
            my $db = $DB_link->database();
                    # check in order of preference:
            $label = $DB_link->display_id() if ($db_names{$db} );
            last if($db eq 'HUGO');
		}

		if( ! defined $label ) {
                    $label = $vg->id(); # fallback on ENSG
                } 

                # check for highlighting
		if (exists $highlights{$label}){
		    $hi_colour = $Config->get( 'gene', 'hi');
		}
	    } else {
		$colour = $unknown_col;
		$label	= "NOVEL";
	    }
	} else {
	    #########
	    # skip if it's not on the strand we're drawing
	    #
	    next if(($vg->each_Transcript())[0]->strand_in_context($VirtualContig->id()) != $self->strand());
	    
	    $colour = $ext_col;
	    $label  = $vg->id;
	    $label  =~ s/gene\.//;
	}

	my $Composite = new Bio::EnsEMBL::Glyph::Composite({});
	
	######################
	# Make and bump label
	######################
	my $bp_textwidth = $w * length(" $label");
	my $tglyph = new Bio::EnsEMBL::Glyph::Text({
	    'x'	        => $start + $font_w_bp,
	    'y'	        => $y,
	    'height'    => $Config->texthelper->height($fontname),
	    'width'     => $font_w_bp * length($label),
	    'font'	=> $fontname,
	    'colour'    => $colour,
	    'text'	=> $label,
	    'absolutey' => 1,
	});

	$Composite->push($tglyph);
	$Composite->colour($hi_colour) if(defined $hi_colour);

	##################################################
	# Draw little taggy bit to indicate start of gene
	##################################################
	my $taggy;

	if($self->strand() == -1) {
	    $taggy = new Bio::EnsEMBL::Glyph::Rect({
		'x'            => $start,
		'y'	       => $tglyph->y(),
		'width'        => 1,
		'height'       => 4,
		'bordercolour' => $colour,
		'absolutey'    => 1,
	    });
	} elsif($self->strand() == 1) {
	    $taggy = new Bio::EnsEMBL::Glyph::Rect({
		'x'	       => $start,
		'y'	       => $tglyph->y() + 3,
		'width'        => 1,
		'height'       => 4,
		'bordercolour' => $colour,
		'absolutey'    => 1,
	    });
	}
	
	$Composite->push($taggy);
	$taggy = new Bio::EnsEMBL::Glyph::Rect({
	    'x'	           => $start,
	    'y'	           => $tglyph->y - 1 + 4,
	    'width'        => $font_w_bp * 0.5,
	    'height'       => 0,
	    'bordercolour' => $colour,
	    'absolutey'    => 1,
	});
	
    	$Composite->push($taggy);


	#########
	# bump it baby, yeah!
	#
        my $bump_start = int($Composite->x * $pix_per_bp);
        $bump_start = 0 if ($bump_start < 0);

        my $bump_end = $bump_start + int($Composite->width * $pix_per_bp);
        if ($bump_end > $bitmap_length){$bump_end = $bitmap_length};

        my $row = &Bump::bump_row(
            $bump_start,
            $bump_end,
            $bitmap_length,
            \@bitmap
        );

        #########
        # shift the composite container by however much we're bumped
        #
        $Composite->y($Composite->y() + (1.5 * $row * $h * -$self->strand()));
        $self->push($Composite);
    }
}

1;
