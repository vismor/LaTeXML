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
  mkflatmap($_,$features->{$_},$flatmap) foreach(@featset);
  mkfeatmap($features->{$_},$featmap,$_) foreach(@featset);
  delete $flatmap->{default}; #Default is reserved!
  $opts->{flatmap} = $flatmap;
  $opts->{featmap} = $featmap;
  print STDERR "Flattening ".scalar(@$rules)." rules...\n";

  # Explode each rules into a family of rules:
  my $newrules = [];
   foreach my $r(@$rules) {
     if ((ref $r) eq 'ARRAY') {
       # Simple declaration:
       my $flatrules = $self->mksimplerule($self->mkcategories([$r->[0]]),
                                           $self->mkcategories($r->[1]),
                                           $r->[2]);
       push @$newrules, @$flatrules;
     }
     elsif ((ref $r) eq 'HASH') {
       # Structured declaration:
       my $flatrules = $self->mkcomplexrule(
                                            $self->mkcategories([$r->{lhs}]),
                                            $self->mkcategories($r->{rhs}),
                                            $r);
       push @$newrules, @$flatrules;
     }
   }
  print STDERR "Created ".scalar(@$newrules)." flat rules!\n";
  $opts->{rules}=$newrules;
}

# Generate a flattened map for each feature class, to be used for rule generation
sub mkflatmap {
 my ($name,$someref,$store) = @_;
 my @flatfeats;
 # Recurs inside, two cases:
 # I. Array ref
 if (ref $someref eq 'ARRAY') {
   my @subfeats = @$someref;
   # Fetch flat feats from store (base feature if not yet processed)
   # CAVEAT: Needs to declare any feature prior to using it as a subfeature!
   foreach (@subfeats) {
     push @flatfeats, (exists $store->{$_}) ? (keys %{$store->{$_}}) : ($_);
   }
 # II. Hash ref
 } elsif (ref $someref eq 'HASH') {
   my @subfeats = keys %$someref;
   foreach my $subfeat(@subfeats) {
     if ($someref->{$subfeat}) {
       # This is a subfeature definition, process recursively:
       mkflatmap($subfeat,$someref->{$subfeat},$store);
     } else {
       # No definition, hence base category or already defined, do nothing.
     }
     push @flatfeats, (exists $store->{$subfeat}) ? (keys %{$store->{$subfeat}}) : ($subfeat);
   }
 } # III. Base category, do nothing
 else {return;}

 # Add flatfeats to store:
 $store->{$name} = {};
 $store->{$name}->{$_} = 1 foreach @flatfeats;
}

# Generate a flattened map between each terminal feature value (resp. category) and its feature name
sub mkfeatmap {
 my ($hashref,$store,$featname) = @_;
 foreach my $key(keys %$hashref) {
   if ((ref $hashref->{$key}) eq 'ARRAY') {
     $store->{$_} = $featname foreach @{$hashref->{$key}};
   } elsif ((ref $hashref->{$key}) eq 'HASH') {
     mkfeatmap($hashref->{$key},$store,$featname);
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
   if (! ref $featstruct) { push @$catlist, [$featstruct]; next;}
   my @feats = map {$featstruct->{$_}||$features->{$_}->{default}} @featset;
   foreach my $feature( @feats ) {
     my $catparts = ccase($flatmap->{$feature}||{$feature=>undef});
     if (@$resultcats) {
       my @newcats = ();
       foreach my $part(@$catparts) {
         push @newcats, (map {$_.$part} @$resultcats);
       }
       $resultcats = \@newcats;
     } else {
       @$resultcats = @$catparts;
     }
   }
   push @$catlist, $resultcats;
 }
 
 my $flatrules = [];
 foreach my $item(@$catlist) {
   if (@$flatrules) {
     my @newrules = ();
     foreach my $cat(@$item) {
       push @newrules, (map {[@{$_},$cat]} @$flatrules);
     }
     $flatrules = \@newrules;
   } else {
     @$flatrules = map {[$_]} @$item;
   }
 }
 $flatrules;
}


# Convert array reference entries into Camel case fragments
sub ccase {
 my ($args) = @_;
 my $out = [map {
   $_ = lc($_);
   s/^(\w)/uc($1)/e;
   $_;
 } (keys %$args)];
 $out;
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


sub mksimplerule {
 my ($self,$lhs,$rhs,$action) = @_;
 my $actions = $self->{opts}->{actions};
 my $rules = [];
 $action = $actions."::".$action if (defined $action && $action !~/::/);
 foreach my $litem(@$lhs) {
   foreach my $ritem(@$rhs) {
     push @$rules, [@{$litem}, $ritem, $action ? ($self->mkaction($litem,$ritem,$action)) : ()];
   }
 }
 $rules;
}

sub mkcomplexrule {
 my ($self,$lhs,$rhs,$r) = @_;
 my $actions = $self->{opts}->{actions};
 my %fields = %$r;
 delete $fields{lhs};
 delete $fields{rhs};
 $fields{action} = $actions."::".$fields{action} if (defined $fields{action} && $fields{action} !~/::/);
 my $rules = [];
 foreach my $litem(@$lhs) {
   foreach my $ritem(@$rhs) {
     $fields{action} = $self->mkaction($litem,$ritem,$fields{action}) if defined $fields{action};
     push @$rules, {lhs=>@$litem, rhs=>$ritem, %fields};
   }
 }
 $rules;
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
