package LaTeXML::PureMathSemantics;

# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}

### OO Driver methods

sub new {
  my ($class,@args) = @_;
  bless {steps=>[]}, $class;
}

sub first_arg {
  my ($state,$parse) = @_;
  return $parse if ref $parse;
  my ($lex,$id) = split(/:/,$_[1]);
  my $xml = Lookup($id);
  $xml = $xml ? ($xml->cloneNode(1)) : undef;
  $xml;
}

sub chain_apply {
  my ( $state, $t1, $c, $op, $c2, $t2) = @_;
  $op = first_arg(undef,$op);
  ApplyNary($op,$t1,$t2);
}


sub infix_apply {
  my ( $state, $t1, $c, $op, $c2, $t2) = @_;
  $op = first_arg(undef,$op);
  ApplyNary($op,$t1,$t2);
}

sub concat_apply {
 my ( $state, $t1, $c, $t2) = @_;
 #print STDERR "ConcApply: ",Dumper($lhs)," <--- ",Dumper($rhs),"\n\n";
 ApplyNary(New('Concatenation'),$t1,$t2);
}

sub set {
  my ( $state, undef, undef, $t, undef, undef, undef, $f ) = @_;
  Apply(New('Set'),$t,$f);
}

sub fenced {
  my ($state, $open, undef, $t, undef, $close) = @_;
  $open=~/^([^:]+)\:/; $open=$1;
  $close=~/^([^:]+)\:/; $close=$1;
  Fence($open,$t,$close);
}

sub fenced_empty {
  # TODO: Semantically figure out list/function/set context,
  # and place the correct OpenMath symbol instead!
 my ($state, $open, $c, $close) = @_;
 $open=~/^([^:]+)\:/; $open=$1;
 $close=~/^([^:]+)\:/; $close=$1;
  Fence($open,New('Empty'),$close);
}

1;
