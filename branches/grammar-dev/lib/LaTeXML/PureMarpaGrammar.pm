# /=====================================================================\ #
# | LaTeXML::PureMarpaGrammar                                           | #
# | A Marpa::XS grammar for mathematical expressions                    | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <deyan.ginev@nist.gov>                          #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

## Mantra in Programming: Premature optimisation is the root of all evil
##         =>
## In Grammar Design: Premature disambiguation is the root of all evil

package LaTeXML::PureMarpaGrammar;
use strict;

# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}


use Marpa::XS;
use LaTeXML::PureMathSemantics;
use LaTeXML::Global;
use base (qw(Exporter));

our $RULES = [
              # 1.0. Concatenation - Left and Right
              ['Factor', [qw/Factor _ Factor/],'concat_apply'],

              # 2.1. Infix Operator - Factors
              ['Factor',[qw/Factor _ MULOP _ FactorArgument/],'infix_apply'],
              ['Factor',['FactorArgument']],

              # 2.1. Infix Operator - Additives
              ['Term',[qw/Term _ ADDOP _ TermArgument/],'infix_apply'],
              ['Term',['TermArgument']],
              ['TermArgument',['Factor']],

              # 2.3. Infix Operator - Type Constructors
              ['Type',[qw/FactorArgument _ ARROW _ FactorArgument/],'infix_apply'],
              ['Type',[qw/Type _ ARROW _ FactorArgument/],'infix_apply'],

              # 3. Infix Relation
              # TODO: How do we deal with term sequences, 1,2,3\in N ?
              ['Termlike',['Term']],
              ['Termlike',['TermSequence']],
              ['Relative',[qw/Termlike _ RELOP _ Termlike/],'infix_apply'],
              ['Relative',[qw/Relative _ RELOP _ Termlike/],'chain_apply'],

              # 4.1. Infix Logical Operators
              ['FormulaArgument',['Relative']], # Needs the distinction to avoid chaining parse for "x>y"
              ['Formula',['FormulaArgument']],
              ['Formula',[qw/Formula _ LOGICOP _ FormulaArgument/],'infix_apply'],
              # 4.2. Infix Metarelations
              ['RelativeFormula',[qw/Formula _ METARELOP _ Formula/],'infix_apply'],
              ['RelativeFormula',[qw/RelativeFormula _ METARELOP _ Formula/],'chain_apply'],

	      # 5.1. Infix Modifier - Generic
              #['Term',[qw/FactorArgument _ RELOP _ Term/],'infix_apply'],
	      # 5.2 Infix Modifier - Typing
              ['Term',[qw/FactorArgument _ COLON _ Type/],'infix_apply'],

              # 6. Fences
              ['FactorArgument',[qw/OPEN _ Term _ CLOSE/],'fenced'],
              ['Relative',[qw/OPEN _ Relative _ CLOSE/],'fenced'],
              ['ADDOP',[qw/OPEN _ ADDOP _ CLOSE/],'fenced'], # (-) ??
              ['FactorArgument',[qw/OPEN _ Vector _ CLOSE/],'fenced'], # vectors are factors
              ['TermArgument',[qw/OPEN _ Sequence _ CLOSE/],'fenced'], # objects are terms

              # 7. Sequence structures
              # 7.1. Vectors:
              ['Entry', ['Term']],
              ['Vector',[qw/Entry _ PUNCT _ Entry/],'infix_apply'],
              ['Vector',[qw/Vector _ PUNCT _ Entry/],'infix_apply'],
              # 7.2. General sequences:
              # 7.2.1 Base case: elements
              ['Element',['Term']],
              ['Element',['Formula']],
              ['Element',['ADDOP']], # implicitly includes logicop
              ['Element',['MULOP']],
              ['Element',['RELOP']],
              ['Element',['METARELOP']],
              # 7.2.1 Recursive case: sequences
              ['Sequence',[qw/Element _ PUNCT _ Element/],'infix_apply'],
              ['Sequence',[qw/Sequence _ PUNCT _ Element/],'infix_apply'],

              # 7.3. Term sequences - TODO: what are these really?
              ['TermSequence',[qw/Term _ PUNCT _ Term/],'infix_apply'],
              ['TermSequence',[qw/TermSequence _ PUNCT _ Term/],'infix_apply'],

              # 8. Lexicon
              ['FactorArgument',['ATOM'],'first_arg_term'],
              ['FormulaArgument',['ATOM'],'first_arg_formula'],
              ['FactorArgument',['UNKNOWN'],'first_arg_term'],
              ['FormulaArgument',['UNKNOWN'],'first_arg_formula'],
              ['FactorArgument',['NUMBER'],'first_arg_term'],
              ['RELOP',['EQUALS']],
              ['METARELOP',['EQUALS']],
              ['ADDOP',['LOGICOP']], # Boolean algebra, lattices
              # Start:
              ['Start',['Term']],
              ['Start',['Formula']],
              ['Start',['RelativeFormula']],
              ['Start',['Sequence']]
];


sub new {
  my($class,%options)=@_;
  my $grammar = Marpa::XS::Grammar->new(
  {   start   => 'Start',
      actions => 'LaTeXML::PureMathSemantics',
      action_object => 'LaTeXML::PureMathSemantics',
      rules=>$RULES,
      default_action=>'first_arg',
      default_null_value=>'no nullables in this grammar'});

  $grammar->precompute();

  my $self = bless {grammar=>$grammar,%options},$class;
  $self; }

sub parse {
  my ($self,$rule,$unparsed) = @_;
  my $rec = Marpa::XS::Recognizer->new( { grammar => $self->{grammar}});
                                          #ranking_method => 'high_rule_only', max_parses=>50} );

  # Insert concatenation
  @$unparsed = map (($_, '_::'), @$unparsed);
  pop @$unparsed;
  #  print STDERR "\n\n";
  foreach (@$unparsed) {
    my ($category,$lexeme,$id) = split(':',$_);
    # Issues: 
    # 1. More specific lexical roles for fences, =, :, others...?
    if ($category eq 'METARELOP') {
      $category = 'COLON' if ($lexeme eq 'colon');
    } elsif ($category eq 'RELOP') {
      $category = 'EQUALS' if ($lexeme eq 'equals');
    }
    #print STDERR "$category:$lexeme\n";

    last unless $rec->read($category,$lexeme.':'.$id);
  }

  my @values = ();
  while ( defined( my $value_ref = $rec->value() ) ) {
    push @values, ${$value_ref};
  }

  # TODO: Support multiple parses!
  (@values>1) ? (['ltx:XMApp',{},New('Set'),@values]) : (shift @values);
}

1;

# DLMF:
# (-)^n for (-1)^n
# f^n (x) = [ f (x) ] ^ n usually
# also f ( f ( ... f x ) ) 
# f^-1 (x) = [inv(f)] (x)
# (d/dx) ^ n, (-)^n is compositional
# (z \frac{d}{dx})^n  and also (\frac{d}{dz} z)^n
