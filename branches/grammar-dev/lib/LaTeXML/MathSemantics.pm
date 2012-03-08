package LaTeXML::MathSemantics;
use Data::Dumper;

# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}

### OO Driver methods

sub new {
  my ($class,@args) = @_;
  bless {steps=>[]}, $class;
}
sub record_step {
  my ($self,$lhs,$rhs) = @_;
  push @{$self->{steps}}, [$lhs,$rhs];
#  print STDERR Dumper "Step ".scalar(@{$self->{steps}}).": \n".Dumper($self->{steps})."\n";
}

sub lhs {
  my $steps = $_[0]->{steps};
  $steps ? $steps->[-1]->[0] : {};
}
sub rhs {
  my $steps = $_[0]->{steps};
  $steps ? $steps->[-1]->[1] : {};
}

sub annotate_features {
  my ($state,$struct) = @_;
  if ($state) {
    my $lhs = $state->lhs();
    if ((ref $lhs) eq 'HASH') { #Feature vector case, set attributes
      if ($struct =~ /XML::/) { # LibXML object
	$struct->setAttribute($_,$lhs->{$_}) foreach (keys %$lhs);
      } else { #LaTeXML object
	my $attr = $struct->[1];
	$attr->{$_} = $lhs->{$_} foreach (keys %$lhs);
      }
    }
  }
  $struct;
}

###########################################
###########################################
### Actual semantic routines:
sub first_arg {
  my ($state,$parse) = @_;
  return $parse if ref $parse;
  my ($lex,$id) = split(/:/,$_[1]);
  my $xml = Lookup($id)->cloneNode(1);
  annotate_features($state,$xml);
}

sub infix_apply {
  my ( $state, $t1, $c, $op, $c2, $t2) = @_;
  $op = first_arg(undef,$op);
  annotate_features($state,ApplyNary($op,$t1,$t2));
}

sub concat_apply {
 my ( $state, $t1, $c, $t2) = @_;
 #print STDERR "ConcApply: ",Dumper($lhs)," <--- ",Dumper($rhs),"\n\n";
 annotate_features($state, ApplyNary(New('Concatenation'),$t1,$t2) );
}

sub set {
  my ( $state, undef, undef, $t, undef, undef, undef, $f ) = @_;
  annotate_features($state,   Apply(New('Set'),$t,$f) );
}

sub fenced {
  my ($state, $open, undef, $t, undef, $close) = @_;
  $open=~/^([^:]+)\:/; $open=$1;
  $close=~/^([^:]+)\:/; $close=$1;
  annotate_features($state,   Fence($open,$t,$close) );
}

sub fenced_empty {
  # TODO: Semantically figure out list/function/set context,
  # and place the correct OpenMath symbol instead!
 my ($state, $open, $c, $close) = @_;
 $open=~/^([^:]+)\:/; $open=$1;
 $close=~/^([^:]+)\:/; $close=$1;
  annotate_features($state,  Fence($open,New('Empty'),$close) );
}

sub parse_complete {
  my ($self,$parse) = @_;
  # local $Data::Dumper::Indent = 1;
  # my @steps = @{$self->{steps}};
  # my $count = scalar(@steps);
  # print STDERR "Parse completed in ".$count." steps!\n";

  # while ($count>0) {
  #   print STDERR "-----------------------\n";
  #   print STDERR "Step $count:\n";
  #   $count--;
  #   print STDERR "LHS: \n".Dumper($steps[$count]->[0]);
  #   print STDERR "\nRHS: \n".Dumper($steps[$count]->[1]);
  #   print STDERR "\n\n";
  # }
  return $parse;
}

1;
