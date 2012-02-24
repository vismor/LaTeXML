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
   type => {default=>'anytype',
            anytype=>{e=>[qw(term formula)],
                      ee=>[qw(tt tf ft ff)], 
                      eee =>{operator=>[qw( ttt )],
                             modifier=>[qw(tft ftt)],
                             relation=>[qw(ttf ftf)],
                             metarelation=>[qw(fff)],
                             other=>[qw(fft)]}}},
#   domain => {default=>'arithmetic',anydomain=>[qw(arithmetic algebra relation geometry setth cattheory)]},
   struct => {default=>'any',
              any=>{atom=>undef,
                    expression=>{'fenced'=>undef,
                                 'unfenced'=>['conc_apply','op_apply']},
                    argument=>[qw(fenced atom conc_apply)]}}
};


#Gramar categories can now be n-dimensional feature vectors,
#  but also classical atomic categories, e.g. in the case of some terminals

# Any grammar rule contains a lhs and rhs, just as in Marpa:
our $RULES = [ #        LHS                          RHS
              # Concatenation - Generic
              [{type=>"term",struct=>"conc_apply"}, [{type=>"term",struct=>"argument"},
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"}
                                                  ],  # 2xy (left-to-right)
                                                      # f g(x) (right-to-left)
               'concat_apply'],
              # Infix Operator - Generic
              [{type=>"term",struct=>"op_apply"}, [{type=>"term",struct=>"any"},
                                                   'CONCAT',
                                                   {type=>"operator", struct=>"atom"},
                                                   'CONCAT',
                                                   {type=>"term",struct=>"argument"} # Constrain struct to assure left-associative
                                                  ],
               'infix_apply'], #ACTION

              # Infix Relation - Generic
              [{type=>"formula",struct=>"op_apply"}, [{type=>"term",struct=>"any"},
                                                      'CONCAT',
                                                      {type=>'ttf',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"any"}
                                                      # Type change, no need to constrain struct
                                                     ],
               'infix_apply'], #ACTION
              [{type=>"formula",struct=>"op_apply"}, [{type=>"formula",struct=>"any"},
                                                      'CONCAT',
                                                      {type=>'ftf',struct=>'atom'},
                                                      'CONCAT',
                                                      {type=>"term",struct=>"any"} 
                                                      # Type change, no need to constrain struct
                                                     ],
               'infix_apply'], #ACTION


              # Set constructor
              [{type=>"term",struct=>"fenced"}, ['OpenBrace', 'CONCAT',
                                                 {type=>"term",struct=>'any'}, 'CONCAT', 'SuchThat', 'CONCAT',
                                                 {type=>'f',struct=>'expression'}, 'CONCAT', 'CloseBrace'],
               'set'], #ACTION

              # Fences
              [{type=>"term",struct=>"fenced"}, ['OPEN', 'CONCAT',
                                                 {type=>"term",struct=>'any'}, 'CONCAT', 'CLOSE'],
               'fenced'], #ACTION
              [{type=>"term",struct=>"fenced"}, ['OpenParen', 'CONCAT',
                                                 {type=>"term",struct=>'any'}, 'CONCAT', 'CloseParen'],
               'fenced'], #ACTION

              # Lexicon:
              [{type=>"operator", struct=>"atom"}, ['ADDOP']],
              [{type=>"operator", struct=>"atom"}, ['MULOP']],
              [{type=>"e", struct=>"atom"},['Atom']],
              [{type=>"term", struct=>"atom"},['NUMBER']],
              [{type=>"any", struct=>"atom"},['UNKNOWN']],
              [{type=>"relation", struct=>"atom"},['RELOP']],
              [{type=>"fff", struct=>"atom"},['METARELOP']],
             [ 'SuchThat', [qw/Bar/]],
             [ 'SuchThat', [qw/Colon/]],
             ['Atom', [qw/UNKNOWN/]],
             ['Term',[{type=>"term",struct=>"any"}]]
            ];



sub new {
  my($class,%options)=@_;
  my $grammar = Marpa::Attributed->new(
  {   start   => {type=>"e", struct=>"any"},
      actions => 'LaTeXML::MathSemantics',
      features=>$FEATURES,rules=>$RULES,
     default_action=>'first_arg'});

  $grammar->precompute();

  my $self = bless {grammar=>$grammar,%options},$class;
  $self; }

sub parse {
  my ($self,$rule,$unparsed) = @_;
  my $rec = Marpa::XS::Recognizer->new( { grammar => $self->{grammar} } );

  # Insert concatenation
  @$unparsed = map (($_, 'CONCAT::'), @$unparsed);
  pop @$unparsed;
  print STDERR "\n\n";
  foreach (@$unparsed) {
    my ($category,$lexeme,$id) = split(':',$_);
    # Issues: 
    # 1. More specific categories for fences
    # if (($category eq 'ADDOP') && ($lexeme eq 'plus')) {
    #   $category = 'Plus';
    # }
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
