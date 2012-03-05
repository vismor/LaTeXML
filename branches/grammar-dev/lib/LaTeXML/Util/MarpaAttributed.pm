# /=====================================================================\ #
# |  LaMaPuN Extensions to Marpa                                        | #
# | Attributed-Value Syntax Compiler                                    | #
# |=====================================================================| #
# | Part of the LaMaPUn project: http://kwarc.info/projects/lamapun/    | #
# |  Research software, produced as part of work done by the            | #
# |  KWARC group at Jacobs University,                                  | #
# | Copyright (c) 2011 LaMaPUn group                                    | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #

use Marpa::XS;
package Marpa::Attributed;

sub new {
 my ($class,$opts) = @_;

 my $compiler = Marpa::Attributed::Compiler->new($opts);
 $compiler->compile_grammar;

 my $grammar = $compiler->grammar;

 delete $grammar->{features};
 delete $grammar->{flatmap};
 delete $grammar->{featmap};
 delete $grammar->{mode};
 Marpa::XS::Grammar->new($grammar);
}


package Marpa::Attributed::Compiler;
use Data::Dumper;
sub new {
 my ($class,$opts) = @_;
 my $startcat = $opts->{start};
 $opts->{start} = 'InternalStartCategory';
 push @{$opts->{rules}}, ['InternalStartCategory', [$startcat]];
 bless {opts => $opts}, $class;
}

sub grammar {my $self = shift; $self->{opts};}

sub compile_grammar {
  my ($self) = @_;
  my $opts = $self->{opts};

  my ($features,$rules,$actions) = ($opts->{features},$opts->{rules},$opts->{actions});
  my @featset = sort keys %$features;
  my ($flatmap,$featmap) = ({},{});
  # Caution: Assuming unique feature names for now
  foreach my $featname(@featset) {
    foreach (keys %{$features->{$featname}}) {
      mkflatmap($_,$features->{$featname}->{$_},$flatmap);
    }
    mkfeatmap($featname,$features->{$featname},$featmap);
  }
  delete $flatmap->{default}; #Default is reserved!

  $opts->{flatmap} = $flatmap;
  $opts->{featmap} = $featmap;
  print STDERR "Flattening ".scalar(@$rules)." rules...\n";

  my $newrules = [];
  # Add rules for the feature tree:
  my $featrules = $self->mkfeatrules;
  print STDERR " Flattened features into ".scalar(@$featrules)." rules...\n";
  print STDERR " Feat rules: \n",Dumper($featrules),"\n\n";
  # Convert given grammar rules to Marpa syntax:
   foreach my $r(@$rules) {
     if ((ref $r) eq 'ARRAY') {
       # Simple declaration:
       push @$newrules,  $self->mksimplerule($self->mkcategories([$r->[0]]),
                                             $self->mkcategories($r->[1]),
                                             $r->[2]);
     }
     elsif ((ref $r) eq 'HASH') {
       # Structured declaration:
       push @$newrules, $self->mkcomplexrule(
                                             $self->mkcategories([$r->{lhs}]),
                                             $self->mkcategories($r->{rhs}),
                                             $r);
     }
   }

  print STDERR "Created ".scalar(@$newrules)." flat rules!\n";
  push @$newrules, @$featrules;
  print STDERR " Final grammar has ".scalar(@$newrules)." rules!\n";
  $opts->{rules}=$newrules;

}

# Generate a flattened map for each feature class, to be used for rule generation
sub mkflatmap {
 my ($name,$someref,$store) = @_;
 my @flatfeats;
 # Recurs inside, two cases:
 # I. Array ref
 if (ref $someref eq 'ARRAY') {
   @flatfeats = @$someref;
 # II. Hash ref
 } elsif (ref $someref eq 'HASH') {
   @flatfeats = keys %$someref;
   foreach my $subfeat(@flatfeats) {
     if ($someref->{$subfeat}) {
       # This is a subfeature definition, process recursively:
       mkflatmap($subfeat,$someref->{$subfeat},$store);
     } else {
       # No definition, hence base category or already defined, do nothing.
     }
   }
 } # III. Base category, do nothing
 else {return;}

 # Add flatfeats to store:
 $store->{$name} = {};
 $store->{$name}->{$_} = 1 foreach @flatfeats;
}

# Generate a flattened map between each terminal feature value (resp. category) and its feature name
sub mkfeatmap {
 my ($featname,$hashref,$store) = @_;
 foreach my $key(keys %$hashref) {
   next if $key eq 'default'; #default is reserved
   $store->{$key} = $featname;
   if ((ref $hashref->{$key}) eq 'ARRAY') {
     $store->{$_} = $featname foreach @{$hashref->{$key}};
   } elsif ((ref $hashref->{$key}) eq 'HASH') {
     $store->{$_} = $featname foreach (keys %{$hashref->{$key}});
     mkfeatmap($featname,$hashref->{$key},$store);
   }
 }
}


sub mkcategories {
 my ($self,$itemlist) = @_;
 my $opts = $self->{opts};
 my $features = $opts->{features};
 my $flatmap = $opts->{flatmap};
 my @featset = sort keys %$features;
 my $catlist = [];

 foreach $featstruct(@$itemlist) {
   my $resultcats = [];
   if (! ref $featstruct) { push @$catlist, $featstruct; next;}
   my @feats = map {$featstruct->{$_}||$features->{$_}->{default}} @featset;
   push @$catlist, join('', map (ccase($_), @feats));
 }
 $catlist;
}


# Convert array reference entries into Camel case fragments
sub ccase {
  my ($word) = @_;
  $word =~ s/^(\w)(.+)$/uc($1).lc($2)/e;
  $word;
}

sub deccase {
 my ($self,$labels) = @_;
 my $featmap = $self->{opts}->{featmap};
 my $lstructs = [];
 foreach my $label(@$labels) {
   my $lstruct;
   while ($label=~/([A-Z]([a-z]*))/g) {
     my $feat = lc ($1);
     if ($featmap->{$feat}) { #Feature:
       $lstruct->{$featmap->{$feat}} = $feat;
     } else { #Standard:
       $lstruct = $feat;
     }
   }
   push @$lstructs,$lstruct;
 }
 $lstructs;
}


sub mkfeatrules {
 my ($self) = @_;
 my $opts = $self->{opts};
 my $features = $opts->{features};
 my $flatmap = $opts->{flatmap};
 my $featmap = $opts->{featmap};
 my @featsets = sort keys %$features;
 my $keysets = [];
 foreach my $featset (@featsets) {
   my @set = grep {$featmap->{$_} eq $featset} (keys %$featmap);
   push @$keysets, \@set;
 }

 my $final_rules = [];

 foreach my $keysetid(0..(scalar(@$keysets)-1)) {
   my $base_rules = [];
   my $expanded_rules = [];

   foreach my $innerid(0..(scalar(@$keysets)-1)) {
     my $keyset = $$keysets[$innerid]; #inner key set
     # If not $keysetid, we need identity:
     my @new;
     if ($innerid != $keysetid) {
       @new = map {[$_,$_]} map {ccase($_)} @$keyset;
     } else {
       foreach $key(@$keyset) {
         # $key is LHS and each of (keys %{$flatmap->{$key}}) is a separate RHS
         my $Key = ccase("$key");
         push @new, map { [$Key,ccase($_)] } (keys %{$flatmap->{$key}});
       }
     }

     if (@$base_rules) {
       # Multiply out with @new on all existing base rules:
       foreach (@$base_rules) {
         my $lhs = $$_[0];
         my $rhs = $$_[1];
         push @$expanded_rules, (map {[$lhs.($_->[0]),$rhs.($_->[1])]} @new);
       }
     } else { # First feature, just push in:
       push @$expanded_rules, @new;
     }

     @$base_rules = @$expanded_rules;
     @$expanded_rules = ();
   }
   push @$final_rules, map {my $r = {lhs=>$_->[0],rhs=>[$_->[1]],rank=>$keysetid+1}; $r} @$base_rules;
 }
 $final_rules;
}

sub mksimplerule {
 my ($self,$lhs,$rhs,$action) = @_;
 my $actions = $self->{opts}->{actions};
 $action = $actions."::".$action if (defined $action && $action !~/::/);
 [@{$lhs}, $rhs, $action ? ($self->mkaction($lhs,$rhs,$action)) : ()];
}

sub mkcomplexrule {
 my ($self,$lhs,$rhs,$r) = @_;
 my $actions = $self->{opts}->{actions};
 my %fields = %$r;
 delete $fields{lhs};
 delete $fields{rhs};
 $fields{action} = $actions."::".$fields{action} if (defined $fields{action} && $fields{action} !~/::/);
 
 $fields{action} = $self->mkaction($lhs,$rhs,$fields{action}) if defined $fields{action};
 {lhs=>$lhs, rhs=>$rhs, %fields};
}

sub mkaction {
  my ($self,$litem,$ritem,$action) = @_;
  my $subname = "Marpa::Attributed::".$$litem[0]."_".join("_",@$ritem);
  my $lobj = $self->deccase($litem);
  my $robj = $self->deccase($ritem);
  *$subname = sub {
    &$action(@_,$lobj,$robj);
  };
  $subname;
}

1;
