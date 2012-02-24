package LaTeXML::MathSemantics;

# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}

sub first_arg {
  return $_[1] if ref $_[1];
  my ($lex,$id) = split(/:/,$_[1]);
  Lookup($id);
}

sub infix_apply {
  my ( undef, $t1, $c, $op, $c2, $t2 , $lhs , $rhs) = @_;
  ApplyNary($op,$t1,$t2);
}

sub concat_apply {
 my ( undef, $t1, $c, $t2 , $lhs , $rhs) = @_;
  ApplyNary(New('Concatenation'),$t1,$t2);
}

sub set {
  my ( undef, undef, undef, $t, undef, undef, undef, $f ) = @_;
  Apply(New('Set'),$t,$f);
}

sub fenced {
  my (undef, undef, undef, $t, undef, undef) = @_;
  return $t;
}

#sub infix_op {
# my (undef,$c,$op,$c2)=@_;
# return $op;
#}

# sub sequence_base {
#  my  (undef,$args,$op,$endarg,$lhs,$rhs) = @_;
#  ["Apply",$op,@$args,$endarg];
# }

# sub sequence_op {
#  my  (undef,@all) = @_;
#  pop @all; pop @all; # Remove trailing lhs and rhs information
#  [@all];
# }


1;
