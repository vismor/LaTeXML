# /=====================================================================\ #
# | LaTeXML::MarpaGrammar                                               | #
# | A Marpa::R2 grammar for mathematical expressions                    | #
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

package LaTeXML::MarpaGrammar;
use strict;

# Startup actions: import the constructors
{ BEGIN{ use LaTeXML::MathParser qw(:constructors); 
#### $::RD_TRACE=1;
}}


use Marpa::R2;
use LaTeXML::MathSemantics;
use LaTeXML::Global;
use base (qw(Exporter));

our $RULES = [
              # 1.0. Concatenation - Left and Right
              ['Factor', [qw/Factor _ Factor/],'concat_apply_factor'],

              # 2.1. Infix Operator - Factors
              ['Factor',['FactorArgument']],
              ['Factor',[qw/Factor _ MULOP _ FactorArgument/],'infix_apply_factor'],

              # 2.1. Infix Operator - Additives
              ['Term',['Factor']],
              ['Term',['TermArgument']],
              ['Term',[qw/Term _ ADDOP _ Factor/],'infix_apply_term'],
              ['Term',[qw/Term _ ADDOP _ TermArgument/],'infix_apply_term'],

              # 2.3. Infix Operator - Type Constructors
              ['Type',[qw/FactorArgument _ ARROW _ FactorArgument/],'infix_apply_type'],
              ['Type',[qw/Type _ ARROW _ FactorArgument/],'infix_apply_type'],

              # 3. Infix Relation
              # TODO: How do we deal with term sequences, 1,2,3\in N ?
              ['Termlike',['Term']],
              ['Termlike',['TermSequence']],
              ['Relative',[qw/Termlike _ RELOP _ Termlike/],'infix_apply_relation'],
              ['Relative',[qw/Relative _ RELOP _ Termlike/],'chain_apply_relation'],

              # 4.1. Infix Logical Operators
	      ['Formula',['FormulaArgument']],
	      ['Formula',['Relative']],
              ['Formula',[qw/Formula _ LOGICOP _ Relative/],'infix_apply_formula'],
              ['Formula',[qw/Formula _ LOGICOP _ FormulaArgument/],'infix_apply_formula'],
              # 4.2. Infix Metarelations
	      ['RelativeFormula',[qw/'RelativeFormulaArgument'/]],
              ['RelativeFormula',[qw/Formula _ METARELOP _ Formula/],'infix_apply_formula'],
              ['RelativeFormula',[qw/RelativeFormula _ METARELOP _ Formula/],'chain_apply'],

	      # 5.1. Infix Modifier - Generic
	      # Modified terms should only appear in sequences, hence entries
	      # Hm, not really, they can appear anywhere with ease, as long as 
	      #      the relation ops are from different domains, so that there is a unique reading
              #['Entry',[qw/FactorArgument _ RELOP _ Term/],'infix_apply_entry'],
	      # So, allow them everywhere and let them explode:
              ['FactorArgument',[qw/FactorArgument _ RELOP _ Term/],'infix_apply_term'],
              ['TermArgument',[qw/TermArgument _ RELOP _ Term/],'infix_apply_term'],
              ['FormulaArgument',[qw/FormulaArgument _ RELOP _ Term/],'infix_apply_formula'],
	      # 5.2 Infix Modifier - Typing
              #['Entry',[qw/FactorArgument _ COLON _ Type/],'infix_apply'],
              ['FactorArgument',[qw/FactorArgument _ COLON _ Type/],'infix_apply_term'],
              ['TermArgument',[qw/TermArgument _ COLON _ Type/],'infix_apply_term'],
              ['FormulaArgument',[qw/FormulaArgument _ COLON _ Type/],'infix_apply_formula'],

              # 6. Fences
              ['FactorArgument',[qw/OPEN _ Term _ CLOSE/],'fenced'],
	      ['FormulaArgument',[qw/OPEN _ Formula _ CLOSE/],'fenced'],
	      ['RelativeFormulaArgument',[qw/OPEN _ RelativeFormula _ CLOSE/],'fenced'], # Examples???
              ['ADDOP',[qw/OPEN _ ADDOP _ CLOSE/],'fenced'], # (-) ?? TODO: what about the other ops?
              ['FactorArgument',[qw/OPEN _ Vector _ CLOSE/],'fenced'], # vectors are factors
              ['TermArgument',[qw/OPEN _ Sequence _ CLOSE/],'fenced'], # objects are terms

              # 7. Sequence structures
              # 7.1. Vectors:
              ['Entry', ['Term']],
              ['Vector',[qw/Entry _ PUNCT _ Entry/],'infix_apply'],
              ['Vector',[qw/Vector _ PUNCT _ Entry/],'infix_apply'],
              # 7.2. General sequences:
              # 7.2.1 Base case: elements
              ['Element',['Formula']],
              ['Element',['ADDOP']], # implicitly includes logicop
              ['Element',['MULOP']],
              ['Element',['RELOP']],
              ['Element',['METARELOP']],
              # 7.2.1 Recursive case: sequences
	      ['Sequence',[qw/Vector _ PUNCT _ Element/],'infix_apply'],
	      ['Sequence',[qw/Entry _ PUNCT _ Element/],'infix_apply'],
	      ['Sequence',[qw/Element _ PUNCT _ Entry/],'infix_apply'],
	      ['Sequence',[qw/Sequence _ PUNCT _ Entry/],'infix_apply'],
	      # Yuck! Vector adjustments to avoid multiple parses

              ['Sequence',[qw/Element _ PUNCT _ Element/],'infix_apply'],
              ['Sequence',[qw/Sequence _ PUNCT _ Element/],'infix_apply'],

              # 7.3. Term sequences - TODO: what are these really? progressions?
              ['TermSequence',[qw/Term _ PUNCT _ Term/],'infix_apply'],
              ['TermSequence',[qw/TermSequence _ PUNCT _ Term/],'infix_apply'],

	      # 8. Scripts
	      # 8.1. Post scripts
	      (map { my $script=$_;
		    map { my $op=$_; {lhs=>$op, rhs=>[$op,'_',$script],action=>'postscript_apply',rank=>2} }
		      qw/FactorArgument TermArgument FormulaArgument RelativeFormulaArgument
			 ADDOP LOGICOP MULOP RELOP METARELOP ARROW/;
		  } qw/POSTSUPERSCRIPT POSTSUBSCRIPT/),
	      # 8.2. Pre/Float scripts
	      (map { my $script=$_;
		    map { my $op=$_; [$op, [$script,'_',$op],'prescript_apply'] }
		      qw/FactorArgument TermArgument FormulaArgument RelativeFormulaArgument
			 ADDOP LOGICOP MULOP RELOP METARELOP ARROW/;
		  } qw/FLOATSUPERSCRIPT FLOATSUBSCRIPT/),


              # 9. Lexicon
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
  my $grammar = Marpa::R2::Grammar->new(
  {   start   => 'Start',
      actions => 'LaTeXML::MathSemantics',
      action_object => 'LaTeXML::MathSemantics',
      rules=>$RULES,
      default_action=>'first_arg'});
     # default_null_value=>'no nullables in this grammar'});

  $grammar->precompute();

  my $self = bless {grammar=>$grammar,%options},$class;
  $self; }

sub parse {
  my ($self,$rule,$unparsed) = @_;
  my $rec = Marpa::R2::Recognizer->new( { grammar => $self->{grammar},
                                          ranking_method => 'high_rule_only'} );

  # Insert concatenation
  @$unparsed = map (($_, '_::'), @$unparsed);
  pop @$unparsed;
  print STDERR "\n\n";
  foreach (@$unparsed) {
    my ($category,$lexeme,$id) = split(':',$_);
    # Issues: 
    # 1. More specific lexical roles for fences, =, :, others...?
    if ($category eq 'METARELOP') {
      $category = 'COLON' if ($lexeme eq 'colon');
    } elsif ($category eq 'RELOP') {
      $category = 'EQUALS' if ($lexeme eq 'equals');
    }
    print STDERR "$category:$lexeme:$id\n";

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

# Grobner bases (lookup!)
# a := ( 3 > 1)
# a \neq 2 > 1
