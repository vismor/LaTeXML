# /=====================================================================\ #
# | LaTeXML::MarpaGrammar                                               | #
# | A Marpa::Attributed grammar for mathematical expressions            | #
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


use LaTeXML::Util::MarpaAttributed;
use LaTeXML::MathSemantics;
use LaTeXML::Global;
use base (qw(Exporter));

### A Grammar for Mathematical Expressions:
our $FEATURES = {
   role => {
            default=>'tp',
            tp=>{
                 e=>{term=>{additive=>{factor=>undef}},
                     formula=>['relative']},
                 ee=>['unary_operator',# tt
                      'unary_relation',# tf
                      'unary_modifier',# ft
                      'unary_metarelation', #ff
		      #'unary_separator', #ee???
                     ],
                 eee=>{'binary_operator'=>[qw(binary_addop binary_mulop binary_typeop)],# ttt
		       'binary_separator'=>undef,# eee??? seems about right...
                       'binary_modifier'=>undef,# tft ftt
                       'binary_relation'=>undef,# ttf ftf,
                       'binary_metarelation'=>undef,# fff,
                       'binary_other'=>undef,# fft
                      }
                }
           },
   struct => {
              default=>'any',
	      any => {
		      expression=>{
				   argument=>[qw(atom fenced)],
				   unfenced=>undef
				  },
		      sequence => [ 'list', 'element' ],
                      function_type => undef
		     }
	      }
};

#Gramar categories can now be n-dimensional feature vectors,
#  but also classical atommic categories, e.g. in the case of some terminals

# Any grammar rule contains a lhs and rhs, just as in Marpa:
our $RULES = [ #        LHS                          RHS
              # 1.0 Concatenation - Generic Arguments
              ['concat_argument', [{role=>"factor",struct=>"unfenced"}],'first_arg'], #ab+cd
              ['concat_argument', [{role=>"additive",struct=>"argument"}],'first_arg'], #a,f,c, (...)

              [{role=>"factor",struct=>"unfenced"},
	                                           ['concat_argument',
						    'CONCAT',
						    'concat_argument',
						   ],  # 2xy (left-to-right)
                                                       # f g(x) (right-to-left)
                                                       # 2af(x) (mixed)
               'concat_apply'],

              # 2.1 Infix Operator - Factors
              [{role=>"factor",struct=>"unfenced"}, [{role=>"factor",struct=>"unfenced"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {role=>"term",struct=>"argument"}
                                                  ],               'infix_apply'], #ACTION

              [{role=>"factor",struct=>"unfenced"}, [{role=>"term",struct=>"argument"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {role=>"term",struct=>"argument"},
                                                  ],               'infix_apply'], #ACTION
	      # 2.2 Infix Operator - Additives
              [{role=>"additive",struct=>"unfenced"}, [{role=>"additive",struct=>"expression"},
                                                   'CONCAT',
                                                   {role=>"binary_addop",struct=>"atom"},
                                                   'CONCAT',
                                                   'concat_argument'
                                                  ],               'infix_apply'], #ACTION
              # 2.3. Infix Operator - Type Constructors
              [{role=>"factor",struct=>"function_type"}, [{role=>"factor",struct=>"argument"},
                                                   'CONCAT',
                                                   {role=>"binary_typeop",struct=>"atom"},
                                                   'CONCAT',
                                                   {role=>"factor",struct=>"argument"}
                                                  ],               'infix_apply'], #ACTION
              [{role=>"factor",struct=>"function_type"}, [{role=>"factor",struct=>"function_type"},
                                                   'CONCAT',
                                                   {role=>"binary_typeop",struct=>"atom"},
                                                   'CONCAT',
                                                   {role=>"factor",struct=>"argument"}
                                                  ],               'infix_apply'], #ACTION

              # 3. Infix Relation - Generic
              ['relation_argument', [{role=>"term",struct=>"expression"}]],
              ['relation_argument', [{role=>"term",struct=>"list"}]],
              [{role=>"relative",struct=>"unfenced"}, ['relation_argument',
                                                      'CONCAT',
                                                      {role=>'binary_relation',struct=>'atom'},
                                                      'CONCAT',
                                                      'relation_argument'
                                                     ],               'infix_apply'], #ACTION
              [{role=>"relative",struct=>"unfenced"}, [{role=>"relative",struct=>"unfenced"}, # chain unfenced relations
                                                      'CONCAT',
                                                      {role=>'binary_relation',struct=>'atom'},
                                                      'CONCAT',
                                                      'relation_argument'
                                                     ],               'infix_apply'], #ACTION

              # 4. Infix MetaRelation - Generic
              [{role=>"formula",struct=>"unfenced"}, [{role=>"formula",struct=>"expression"},
                                                      'CONCAT',
                                                      {role=>'binary_metarelation',struct=>'atom'},
                                                      'CONCAT',
                                                      {role=>"formula",struct=>"argument"}
                                                     ],               'infix_apply'], #ACTION
              # 4.1. Infix MetaRelation - Equality
              [{role=>"formula",struct=>"unfenced"}, [{role=>"formula",struct=>"expression"},
                                                      'CONCAT',
                                                      'EQUALS',
                                                      'CONCAT',
                                                      {role=>"formula",struct=>"expression"}
                                                     ],               'infix_apply'], #ACTION

	      # 5. Infix Modifier - Generic
              [{role=>"[term]",struct=>"unfenced"}, [{role=>"[1]",struct=>"atom"},
                                                      'CONCAT',
                                                      {role=>'binary_modifier',struct=>'atom'},
                                                      'CONCAT',
                                                      {role=>"relative",struct=>"fenced"} # TODO: Think this through
                                                     ],               'infix_apply'], #ACTION
	      # 5.2 Infix Modifier - Typing
              [{role=>"[term]",struct=>"unfenced"}, [{role=>"[1]",struct=>"atom"},
                                                      'CONCAT',
                                                      {role=>'binary_modifier',struct=>'atom'},
                                                      'CONCAT',
                                                      {role=>"factor",struct=>"function_type"}
                                                     ],               'infix_apply'], #ACTION



              # # 4. Set constructor
              # [{role=>"term",struct=>"fenced"}, ['OPENBRACE', 'CONCAT',
              #                                    {role=>"term",struct=>'expression'}, 'CONCAT', 'such_that', 'CONCAT',
              #                                    {role=>'formula',struct=>'expression'}, 'CONCAT', 'CLOSEBRACE'],
              #  'set'], #ACTION


              # Fences - role preserving
              [{role=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {role=>"[1]",struct=>'expression'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION
	      # Fences - cast lists to expressions, preserve role
              [{role=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {role=>"[1]",struct=>'list'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION
	      # Fences - empty
              [{role=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT', 'CLOSE'],
               'fenced_empty'], #ACTION




	      # Elementhood - cast expressions into elements, preserve role:
	      [{role=>"[e]",struct=>"element"}, [{role=>"[1]",struct=>'expression'}]],

	      # TODO: Groups (*,S)
	      # TODO: Prevent this from overgenerating (what is happening ?!?!)
	      # e.g. 1,2,,,,;,;,,;3 definitely shouldn't parse
	      # Lists - composition:
	      [{role=>"[tp]",struct=>"list"}, [{role=>"[1]",struct=>"sequence"},
	      					     'CONCAT',
	      					     {role=>"binary_separator",struct=>"atom"},
	      					     'CONCAT',
	      					     {role=>"[1]",struct=>'element'}],
               'infix_apply'], #ACTION,

              # Lexicon:
              # TODO: New feature intuitions, consider rewriting here!!!
              [{role=>"factor", struct=>"atom"},['NUMBER']],
              [{role=>"factor", struct=>"atom"},['UNKNOWN']],
	      [{role=>"formula", struct=>"atom"},['UNKNOWN']], # TODO: Do we really need formulas here????
	      # It seems we do e.g. (x \wedge y), but then things like '(a)' have two parses that are the same tree
	      # where one parse means 'term' , the other 'formula'... But then, that's ok,
	      # the CDLF processing can weed out equivalent parses in any case! So leaving formulas in.

              [{role=>"binary_addop", struct=>"atom"},['ADDOP']],
              [{role=>"binary_mulop", struct=>"atom"},['MULOP']],
	      [{role=>'binary_typeop', struct=>'atom'}, ['ARROW']],
              [{role=>"binary_relation", struct=>"atom"},['RELOP']],
              [{role=>"binary_metarelation", struct=>"atom"},['METARELOP']],
              [{role=>"binary_modifier", struct=>"atom"},['MODIFIER']],
	      [{role=>"binary_separator", struct=>"atom"},['PUNCT']],
	      [ 'such_that', [qw/BAR/]],
	      [ 'such_that', [qw/COLON/]],
	      [ {role=>'binary_modifier', struct=>'atom'}, [qw/COLON/]],
	      [ {role=>'binary_mulop', struct=>'atom'}, [qw/COLON/]], #division, ratios
	      [ {role=>'binary_modifier', struct=>'atom'}, [qw/EQUALS/]],
	      [ {role=>'binary_relation', struct=>'atom'}, [qw/EQUALS/]],
	      [ {role=>'binary_metarelation', struct=>'atom'}, [qw/EQUALS/]],
              # Recursive input (ATOM??)
              [ {role=>'[e]',struct=>'atom'}, ['ATOM']],
	      # Start category:
	      ['start',[{role=>"e", struct=>"expression"}],'parse_complete'], # If expression - real math only
	      ['start',[{role=>"tp", struct=>"list"}],'parse_complete'], # If list, anything goes
	     ];

sub new {
  my($class,%options)=@_;
  my $grammar = Marpa::Attributed->new(
  {   start   => 'start',
      actions => 'LaTeXML::MathSemantics',
      action_object => 'LaTeXML::MathSemantics',
      features=>$FEATURES,rules=>$RULES,
      default_action=>'first_arg',
      default_null_value=>'no nullables in this grammar'});

  $grammar->precompute();

  my $self = bless {grammar=>$grammar,%options},$class;
  $self; }

sub parse {
  my ($self,$rule,$unparsed) = @_;
  my $rec = Marpa::XS::Recognizer->new( { grammar => $self->{grammar}, ranking_method => 'high_rule_only', max_parses=>50} );

  # Insert concatenation
  @$unparsed = map (($_, 'CONCAT::'), @$unparsed);
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
    print STDERR "$category:$lexeme\n";

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
