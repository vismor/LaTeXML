# /=====================================================================\ #
# | LaTeXML::MarpaGrammar                                               | #
# | A Marpa::Attributed grammar for mathematical expressions        :)    | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <deyan.ginev@nist.gov>                          #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

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
   type => {default=>'tp',
            tp=>{
		      e=>{term=>[qw(additive factor)],
			  formula=>undef},
                      ee=>[qw(tt tf ft ff)], 
                      eee =>{operator=>[qw( ttt )],
                             modifier=>[qw(tft ftt)],
                             relation=>[qw(ttf ftf)],
                             metarelation=>[qw(fff)],
                             other=>[qw(fft)]}}},
   struct => {default=>'expression',
              expression=>{argument=>[qw(atom fenced)],
                           unfenced=>undef}
             }
};

#Gramar categories can now be n-dimensional feature vectors,
#  but also classical atomic categories, e.g. in the case of some terminals

# Any grammar rule contains a lhs and rhs, just as in Marpa:
our $RULES = [ #        LHS                          RHS
              # 1.0 Concatenation - Generic Arguments
              [{type=>"factor",struct=>"unfenced"},
	                                           [{type=>"term",struct=>"argument"},
						    'CONCAT',
						    {type=>"term",struct=>"argument"},
						   ],  # 2xy (left-to-right)
                                                       # f g(x) (right-to-left)
               'concat_apply'],
              # 1.1. Concatenation - Factors
              [{type=>"factor",struct=>"unfenced"},
	                                           [{type=>"factor",struct=>"unfenced"},
						    'CONCAT',
						    {type=>"term",struct=>"argument"},
						   ],  # 2xy (left-to-right)
               'concat_apply'],
              [{type=>"factor",struct=>"unfenced"},
	                                           [{type=>"term",struct=>"argument"},
						    'CONCAT',
						    {type=>"factor",struct=>"unfenced"},
						   ],  # f g(x) (right-to-left)
               'concat_apply'],

              # 2.1 Infix Operator - Factors
              [{type=>"factor",struct=>"unfenced"}, [{type=>"factor",struct=>"expression"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"}
                                                  ],               'infix_apply'], #ACTION

              [{type=>"factor",struct=>"unfenced"}, [{type=>"additive",struct=>"argument"},
                                                   'CONCAT',
                                                   'MULOP',
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"},
                                                  ],               'infix_apply'], #ACTION
	      # 2.2 Infix Operator - Additives
              [{type=>"additive",struct=>"unfenced"}, [{type=>"term",struct=>"expression"},
                                                   'CONCAT',
                                                   {type=>'ttt',struct=>'atom'},
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"},
                                                  ],               'infix_apply'], #ACTION

              # Infix Relation - Generic
              [{type=>"formula",struct=>"unfenced"}, [{type=>"term",struct=>"expression"},
                                                      'CONCAT',
                                                      {type=>'ttf',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"expression"}
                                                     ],               'infix_apply'], #ACTION
              [{type=>"formula",struct=>"unfenced"}, [{type=>"formula",struct=>"expression"},
                                                      'CONCAT',
                                                      {type=>'ftf',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"expression"}
                                                     ],               'infix_apply'], #ACTION


              # Set constructor
              [{type=>"term",struct=>"fenced"}, ['OpenBrace', 'CONCAT',
                                                 {type=>"term",struct=>'expression'}, 'CONCAT', 'SuchThat', 'CONCAT',
                                                 {type=>'f',struct=>'expression'}, 'CONCAT', 'CloseBrace'],
               'set'], #ACTION

              # Fences
              [{type=>"term",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {type=>"term",struct=>'expression'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION

              # Lexicon:
              # TODO: New feature intuitions, require rewriting here!!!
              [{type=>"term", struct=>"atom"},['Atom']],
              [{type=>"formula", struct=>"atom"},['Atom']],
              [{type=>"term", struct=>"atom"},['NUMBER']],
              [{type=>"term", struct=>"atom"},['UNKNOWN']], #TODO: Hm...
              [{type=>"ttt", struct=>"atom"},['ADDOP']],
              [{type=>"ttf", struct=>"atom"},['RELOP']],
              [{type=>"ftf", struct=>"atom"},['RELOP']],
              [{type=>"fff", struct=>"atom"},['METARELOP']],
	      [ 'SuchThat', [qw/Bar/]],
	      [ 'SuchThat', [qw/Colon/]],
	      ['Atom', [qw/UNKNOWN/]],
	      ['Term',[{type=>"term",struct=>"expression"}]]
	     ];

sub new {
  my($class,%options)=@_;
  my $grammar = Marpa::Attributed->new(
  {   start   => {type=>"e", struct=>"expression"},
      actions => 'LaTeXML::MathSemantics',
      features=>$FEATURES,rules=>$RULES,
     default_action=>'first_arg'});

  $grammar->precompute();

  my $self = bless {grammar=>$grammar,%options},$class;
  $self; }

sub parse {
  my ($self,$rule,$unparsed) = @_;
  my $rec = Marpa::XS::Recognizer->new( { grammar => $self->{grammar}, ranking_method => 'high_rule_only'} );

  # Insert concatenation
  @$unparsed = map (($_, 'CONCAT::'), @$unparsed);
  pop @$unparsed;
  print STDERR "\n\n";
  foreach (@$unparsed) {
    my ($category,$lexeme,$id) = split(':',$_);
    # Issues: 
    # 1. More specific categories for fences
    print STDERR "$category:$lexeme\n";

    $rec->read($category,$lexeme.':'.$id);
  }

  my @values = ();
  while ( defined( my $value_ref = $rec->value() ) ) {
    push @values, ${$value_ref};
  }

#  my $pcount=0;
#  print STDERR "\n############################################\n\nParse ",++$pcount,":\n\n",
#    Dumper($_) foreach @values;

  # TODO: Support multiple parses!
  (@values>1) ? (['ltx:XMApp',{},New('Set'),@values]) : (shift @values);
}

1;
