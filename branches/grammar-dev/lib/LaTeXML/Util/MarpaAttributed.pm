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
 delete $grammar->{featsets};
 delete $grammar->{flatmap};
 delete $grammar->{featmap};
 delete $grammar->{mode};
 Marpa::XS::Grammar->new($grammar);
}


package Marpa::Attributed::Compiler;
use Clone qw(clone);
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
  my @featsets = sort keys %$features;
  $opts->{featsets} = \@featsets;
  $self->{opts}->{featsets}=\@featsets;
  my ($flatmap,$featmap) = ({},{});
  # Caution: Assuming unique feature names for now
  foreach my $featname(@featsets) {
    foreach (keys %{$features->{$featname}}) {
      mkflatmap($_,$features->{$featname}->{$_},$flatmap);
    }
    mkfeatmap($featname,$features->{$featname},$featmap);
  }
  delete $flatmap->{default}; #Default is reserved!

  $opts->{flatmap} = $flatmap;
  $opts->{featmap} = $featmap;

  my $newrules = [];
  # Add rules for the feature tree:
  my $featrules = $self->mkfeatrules;
  print STDERR "\n Flattened features into ".scalar(@$featrules)." rules...\n";

  # Convert given grammar rules to Marpa syntax:
  # TODO: Keep in mind the [e] expansion generates redundant rules, that might make conflicts.
  # Make sure "most specific" rules are either evaluated first or ranked highest, whatever makes sense
   foreach my $r(@$rules) {
     if ((ref $r) eq 'ARRAY') {
       # Simple declaration:
       my $action = $r->[2];
       my @cats = $self->mkcategories($r->[0],@{$r->[1]});
       foreach my $pair(@cats) {
	 push @$newrules, $self->mksimplerule($pair->[0],$pair->[1],$action);
       }
       #my @lcats = $self->mkcategory([$r->[0]]);
       #my @rcats = $self->mkcategory($r->[1]);
       #foreach my $lcat(@lcats) {
	 # foreach my $rcat(@rcats) {
	 #   push @$newrules,  $self->mksimplerule($lcat,$rcat,$action);
	 # }}
     }
     elsif ((ref $r) eq 'HASH') {
       # Structured declaration:
       my @cats = $self->mkcategories($r->{lhs},@{$r->{rhs}});
       foreach my $pair(@cats) {
        push @$newrules, $self->mkcomplexrule($pair->[0],$pair->[1],$r);
       }
       # my @lcats = $self->mkcategory([$r->{lhs}]);
       # my @rcats = $self->mkcategory($r->{rhs});
       # foreach my $lcat(@lcats) {
       # 	 foreach my $rcat(@rcats) {
       # 	   push @$newrules, $self->mkcomplexrule($lcat,$rcat,$r);
       # 	 }}
     }
   }

  print STDERR " Created ".scalar(@$newrules)." flat rules from ".scalar(@$rules)." attributed rules!\n";
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


sub mkcategory {
 my ($self,$itemlist) = @_;
 my $opts = $self->{opts};
 my @featsets = @{$opts->{featsets}};
 my $catlist = [];

 foreach $featstruct(@$itemlist) {
   my $resultcats = [];
   if (! ref $featstruct) { push @$catlist, $featstruct; next;}
   my @feats = map {$featstruct->{$_}||$features->{$_}->{default}} @featsets;
   push @$catlist, join('', map (ccase($_), @feats));
 }
 ($catlist);
}

sub mkcategories {
 my ($self,@cats) = @_;
 my $opts = $self->{opts};
 my $features = $opts->{features};
 my $flatmap = $opts->{flatmap};
 my @featsets = @{$opts->{featsets}};
 my $catcount = scalar(@cats)-1;
 # Recursively expand all [placeholders], keeping track of the coordinating [1]...[n] refs
 for my $i(0..$catcount) {
   my $cat = $cats[$i];
   next unless ref $cat;
   my $wild;
   foreach my $featname(@featsets) {
     if ($cat->{$featname} && ($cat->{$featname} =~ /^\[(\D+)\]$/)) {
       $wild=[$featname,$1]; last;
     }
   }
   if ($wild) { # Found wildcard, iteratively expand and substitute once and then recursively collect subresults:
     my $once_expanded_cats = expand_and_substitute(\@cats,$i,$wild,$flatmap);
     return ( map { $self->mkcategories(@$_) } @$once_expanded_cats);
   }
 }
 # No wildcards found, fallback to basic support:
 return ( [$self->mkcategory([$cats[0]]),$self->mkcategory([@cats[1..$catcount]])] );
}

sub expand_and_substitute {
  my ($cats,$i,$wild,$flatmap) = @_;
  my @vals;
  my @next = ($wild->[1]);
  while (@next) {
    my $featname = shift @next;
    push @vals, $featname;
    push @next, keys %{$flatmap->{$featname}};
  }
  [ map {substitute($cats,$i,$wild->[0],$_)} @vals ]; # One-level expansion of $cats
}

sub substitute {
  my ($given_cats,$i,$feat,$val) = @_;
  # We should clone $cats here, as we're making a new rule
  my $cats = clone($given_cats);
  my $cat=$cats->[$i];
  $cat->{$feat} = $val;
  for my $j(0..scalar(@$cats)-1) {
    next if $j==$i;
    my $check_cat = $cats->[$j];
    if ($check_cat->{$feat} && ($check_cat->{$feat} =~ /^\[(\d+)\]$/)) {
      if ($1 eq '1') {
	$check_cat->{$feat} = $val;
      } else {
	$check_cat->{$feat} = '['.($1-1).']';
      }
    }
  }
  $cats;
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
   while ($label=~/([A-Z]([a-z_]*))/g) {
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
 my @featsets = @{$opts->{featsets}};
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
