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
   type => {
            default=>'tp',
            tp=>{
                 e=>{term=>{additive=>{factor=>undef}},
                     formula=>undef},
                 ee=>['unary_operator',# tt
                      'unary_relation',# tf
                      'unary_modifier',# ft
                      'unary_metarelation', #ff
		      #'unary_separator', #ee???
                     ],
                 eee=>['binary_operator',# ttt
		       'binary_separator',# eee??? seems about right...
                       'binary_modifier',# tft ftt
                       'binary_relation',# ttf ftf,
                       'binary_metarelation',# fff,
                       'binary_other',# fft
                      ]
                }
           },
   struct => {
              default=>'any',
	      any => {
		      expression=>{
				   argument=>[qw(atom fenced)],
				   unfenced=>undef
				  },
		      sequence => [ 'list', 'element' ]
		     }
	      }
};

#Gramar categories can now be n-dimensional feature vectors,
#  but also classical atommic categories, e.g. in the case of some terminals

# Any grammar rule contains a lhs and rhs, just as in Marpa:
our $RULES = [ #        LHS                          RHS
              # 1.0 Concatenation - Generic Arguments
              ['concat_argument', [{type=>"factor",struct=>"unfenced"}],'first_arg'], #ab+cd
              ['concat_argument', [{type=>"additive",struct=>"argument"}],'first_arg'], #a,f,c, (...)

              [{type=>"factor",struct=>"unfenced"},
	                                           ['concat_argument',
						    'CONCAT',
						    'concat_argument',
						   ],  # 2xy (left-to-right)
                                                       # f g(x) (right-to-left)
                                                       # 2af(x) (mixed)
               'concat_apply'],

              # 2.1 Infix Operator - Factors
              [{type=>"factor",struct=>"unfenced"}, [{type=>"factor",struct=>"unfenced"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"}
                                                  ],               'infix_apply'], #ACTION

              [{type=>"factor",struct=>"unfenced"}, [{type=>"term",struct=>"argument"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"},
                                                  ],               'infix_apply'], #ACTION
	      # 2.2 Infix Operator - Additives
              [{type=>"additive",struct=>"unfenced"}, [{type=>"additive",struct=>"expression"},
                                                   'CONCAT',
                                                   'ADDOP',
                                                   'CONCAT',
                                                   'concat_argument'
                                                  ],               'infix_apply'], #ACTION

              # Infix Relation - Generic
              [{type=>"formula",struct=>"unfenced"}, [{type=>"term",struct=>"expression"},
                                                      'CONCAT',
                                                      {type=>'binary_relation',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"expression"}
                                                     ],               'infix_apply'], #ACTION
              [{type=>"formula",struct=>"unfenced"}, [{type=>"formula",struct=>"expression"},
                                                      'CONCAT',
                                                      {type=>'binary_relation',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"expression"}
                                                     ],               'infix_apply'], #ACTION


              # Set constructor
              [{type=>"term",struct=>"fenced"}, ['OPENBRACE', 'CONCAT',
                                                 {type=>"term",struct=>'expression'}, 'CONCAT', 'such_that', 'CONCAT',
                                                 {type=>'formula',struct=>'expression'}, 'CONCAT', 'CLOSEBRACE'],
               'set'], #ACTION


              # Fences - type preserving
              [{type=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {type=>"[1]",struct=>'expression'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION
	      # Fences - cast lists to expressions, preserve type
              [{type=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {type=>"[1]",struct=>'list'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION
	      # Fences - empty
              [{type=>"[e]",struct=>"fenced"}, ['OPEN', 'CONCAT', 'CLOSE'],
               'fenced_empty'], #ACTION




	      # Elementhood - cast expressions into elements, preserve type:
	      [{type=>"[e]",struct=>"element"}, [{type=>"[1]",struct=>'expression'}]],

	      # TODO: Groups (*,S)
	      # TODO: Prevent this from overgenerating (what is happening ?!?!)
	      # e.g. 1,2,,,,;,;,,;3 definitely shouldn't parse
	      # Lists - composition:
	      [{type=>"[tp]",struct=>"list"}, [{type=>"[1]",struct=>"sequence"},
	      					     'CONCAT',
	      					     {type=>"binary_separator",struct=>"atom"},
	      					     'CONCAT',
	      					     {type=>"[1]",struct=>'element'}],
               'infix_apply'], #ACTION,

              # Lexicon:
              # TODO: New feature intuitions, consider rewriting here!!!
              [{type=>"factor", struct=>"atom"},['NUMBER']],
              [{type=>"factor", struct=>"atom"},['UNKNOWN']],
	      [{type=>"formula", struct=>"atom"},['UNKNOWN']], # TODO: Do we really need formulas here????
	      # It seems we do e.g. (x \wedge y), but then things like '(a)' have two parses that are the same tree
	      # where one parse means 'term' , the other 'formula'... But then, that's ok,
	      # the CDLF processing can weed out equivalent parses in any case! So leaving formulas in.

              [{type=>"binary_operator", struct=>"atom"},['ADDOP']],
              [{type=>"binary_operator", struct=>"atom"},['MULOP']],
              [{type=>"binary_relation", struct=>"atom"},['RELOP']],
              [{type=>"binary_metarelation", struct=>"atom"},['METARELOP']],
	      [{type=>"binary_separator", struct=>"atom"},['PUNCT']],
	      [ 'such_that', [qw/BAR/]],
	      [ 'such_that', [qw/COLON/]],

	      # Start category:
	      ['start',[{type=>"e", struct=>"expression"}],'parse_complete'], # If expression - real math only
	      ['start',[{type=>"tp", struct=>"list"}],'parse_complete'], # If list, anything goes
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
