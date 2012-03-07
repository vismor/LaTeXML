package LaTeXML::MathSemantics;
use Data::Dumper;
# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}

### OO Driver methods

sub new {
  my ($class,@args) = @_;
  print STDERR "\n\n\nConstructing: ".Dumper(@args),"\n\n\n\n";
  bless {steps=>[]}, $class;
}
sub record_step {
  my ($self,$lhs,$rhs) = @_;
  push @{$self->{steps}}, [$lhs,$rhs];
#  print STDERR Dumper "Step ".scalar(@{$self->{steps}}).": \n".Dumper($self->{steps})."\n";
}



### Actual semantic routines:

sub first_arg {
  return $_[1] if ref $_[1];
  my ($lex,$id) = split(/:/,$_[1]);
  Lookup($id);
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

sub parse_complete {
  my ($self,$parse) = @_;
  my @steps = @{$self->{steps}};
  my $count = scalar(@steps);
  print STDERR "Parse completed in ".$count." steps!\n";

  while ($count>0) {
    print STDERR "-----------------------\n";
    print STDERR "Step $count:\n";
    $count--;
    print STDERR "LHS: ".Dumper($steps[$count]->[0]);
    print STDERR "RHS: ".Dumper($steps[$count]->[1]);
    print STDERR "\n\n";
  }
  return $parse;
}

1;
