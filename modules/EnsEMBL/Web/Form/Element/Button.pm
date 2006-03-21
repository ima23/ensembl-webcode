package EnsEMBL::Web::Form::Element::Button;

use EnsEMBL::Web::Form::Element;
use CGI qw(escapeHTML);
our @ISA = qw( EnsEMBL::Web::Form::Element );

sub new { 
    my $class = shift; 
    my %params = @_;
    my $self = $class->SUPER::new( @_ );
    $self->{'on_click'} = $params{'on_click'};
    return $self;
 }

sub on_click        :lvalue { $_[0]{'on_click'};   }

sub render { 
    return sprintf( '<input type="button" name="%s" value="%s" class="red-button" %s />', 
		    CGI::escapeHTML($_[0]->name) || 'submit', 
		    CGI::escapeHTML($_[0]->value), 
		    $_[0]->on_click ? sprintf("onClick=\"%s\"", $_[0]->on_click) : '');
}  
		

1;
