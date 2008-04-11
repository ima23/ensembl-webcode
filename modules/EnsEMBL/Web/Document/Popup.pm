package EnsEMBL::Web::Document::Popup;

use strict;
use EnsEMBL::Web::Document::Common;

our @ISA = qw(EnsEMBL::Web::Document::Common);

use Data::Dumper qw(Dumper);

sub _initialize_HTML {
  my $self = shift;

## General layout for popup pages...

  $self->add_head_elements qw(
    title      EnsEMBL::Web::Document::HTML::Title
    stylesheet EnsEMBL::Web::Document::HTML::Stylesheet
    javascript EnsEMBL::Web::Document::HTML::Javascript
    rss        EnsEMBL::Web::Document::HTML::RSS
    meta       EnsEMBL::Web::Document::HTML::Meta
  );

  $self->add_body_elements qw(
    javascript_div EnsEMBL::Web::Document::HTML::JavascriptDiv
    masthead   EnsEMBL::Web::Document::HTML::NoMastHead
    release    EnsEMBL::Web::Document::HTML::NoRelease
    helplink   EnsEMBL::Web::Document::HTML::NoHelpLink
    html_start EnsEMBL::Web::Document::HTML::HTML_Block
    menu       EnsEMBL::Web::Document::HTML::NoMenu
    content    EnsEMBL::Web::Document::HTML::PopupContent
    html_end   EnsEMBL::Web::Document::HTML::HTML_Block
  );
  $self->call_child_functions( 'common_page_elements' );

  $self->_common_HTML;
  $self->_script_HTML;
  $self->helplink->kw = $ENV{'ENSEMBL_SCRIPT'}.';se=1';
  $self->rss->add( '/common/rss.xml', 'Ensembl website news feed', 'rss' );
  $self->call_child_functions( 'extra_configuration' );
}

1;
