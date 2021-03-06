# /=====================================================================\ #
# |  LaTeXML::Model                                                     | #
# | Stores representation of Document Type for use by Document          | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package LaTeXML::Model;
use strict;
use XML::LibXML;
use XML::LibXML::Common qw(:libxml);
use XML::LibXML::XPathContext;
use LaTeXML::Global;
use LaTeXML::Font;
use LaTeXML::Util::Pathname;
use LaTeXML::Rewrite;
use base qw(LaTeXML::Object);

#**********************************************************************
sub new {
  my($class,%options)=@_;
  my $self = bless {xpath=> XML::LibXML::XPathContext->new(),
		    namespace_prefixes=>{}, namespaces=>{}, rewrites=>[], %options},$class;
  $$self{xpath}->registerFunction('match-font',\&LaTeXML::Font::match_font);
  $self->registerNamespace('xml',"http://www.w3.org/XML/1998/namespace");
  $self; }

sub getRootName { $_[0]->{roottag}; }
sub getPublicID { $_[0]->{public_id}; }
sub getSystemID { $_[0]->{system_id}; }
sub getDefaultNamespace { $_[0]->{defaultNamespace}; }

sub getDTD {
  my($self)=@_;
  $self->loadDocType unless $$self{doctype_loaded};
  $$self{dtd}; }

sub getXPath { $_[0]->{xpath}; }

#**********************************************************************
# DocType
#**********************************************************************

sub setDocType {
  my($self,$roottag,$publicid,$systemid)=@_;
  $$self{roottag}=$roottag;
  $self->setTagProperty('_Document_','model',{$roottag=>1}) if $roottag;
  $$self{public_id}   =$publicid;
  $$self{system_id}   =$systemid;
}
# Hmm, rather than messing with roottag, we could extract all
# possible root tags from the doctype, then put the tag of the
# document root in the doctype declaration.
# Well, ANY element could conceivably be a root element....
# but is that desirable? Not really, ....

# Question: if we don't have a doctype, can we rig the queries to
# let it build a `reasonable' document?

#**********************************************************************
# Namespaces
#**********************************************************************

sub registerNamespace {
  my($self,$prefix,$namespace,$default)=@_;
  if($prefix && $namespace){
    $$self{namespace_prefixes}{$namespace}=$prefix;
    $$self{namespaces}{$prefix}=$namespace;
    $$self{xpath}->registerNs($prefix,$namespace);  }
  $$self{defaultNamespace}=$namespace if $default; }

sub getNamespacePrefix {
  my($self,$namespace)=@_;
  $$self{namespace_prefixes}{$namespace}; }

sub getNamespace {
  my($self,$prefix)=@_;
  $$self{namespaces}{$prefix}; }

#**********************************************************************
# Accessors
#**********************************************************************

sub getTagProperty {
  my($self,$tag,$prop)=@_;
  $$self{tagprop}{$tag}{$prop}; }

sub setTagProperty {
  my($self,$tag,$property,$value)=@_;
  $$self{tagprop}{$tag}{$property}=$value; }

#**********************************************************************
# Document Structure Queries
#**********************************************************************

# Can the element $node contain a $childtag element?
sub canContain {
  my($self,$tag,$childtag)=@_;
  $self->loadDocType unless $$self{doctype_loaded};
  # Handle obvious cases explicitly.
  return 0 if $tag eq '#PCDATA';
  return 0 if $tag eq '_Comment_';
  return 1 if $tag eq '_Capture_';
  return 1 if $tag eq '_WildCard_';
  return 1 if $childtag eq '_Capture_';
  return 1 if $childtag eq '_WildCard_';
  return 1 if $childtag eq '_Comment_';
  return 1 if $childtag eq '_ProcessingInstruction_';
#  return 1 if $$self{permissive}; # No DTD? Punt!
  return 1 if $$self{permissive} && ($tag eq '_Document_') && ($childtag ne '#PCDATA'); # No DTD? Punt!
  # Else query tag properties.
  my $model = $$self{tagprop}{$tag}{model};
  $$model{ANY} || $$model{$childtag}; }

# Can the element $node contain a $childtag element indirectly?
# That is, by openning some number of autoOpen'able tags?
# And if so, return the tag to open.
sub canContainIndirect {
  my($self,$tag,$childtag)=@_;
  $self->loadDocType unless $$self{doctype_loaded};
  $$self{tagprop}{$tag}{indirect_model}{$childtag}; }

sub canContainSomehow {
  my($self,$tag,$childtag)=@_;
  $self->canContain($tag,$childtag) ||  $self->canContainIndirect($tag,$childtag); }

# Can this node be automatically closed, if needed?
sub canAutoClose {
  my($self,$tag)=@_;
  $self->loadDocType unless $$self{doctype_loaded};
  return 1 if $tag eq '#PCDATA';
  return 1 if $tag eq '_Comment_';
  $$self{tagprop}{$tag}{autoClose}; }

sub canHaveAttribute {
  my($self,$tag,$attrib)=@_;
  $self->loadDocType unless $$self{doctype_loaded};
  return 1 if $attrib eq 'xml:id';
  return 1 if $$self{permissive};
  $$self{tagprop}{$tag}{attributes}{$attrib}; }

#**********************************************************************
# DTD Analysis
#**********************************************************************
# Uses XML::LibXML to read in the DTD. Then extracts a simplified
# model: which elements can appear within each element, ignoring
# (for now) the ordering, repeat, etc, of the elements.
# From this, and the Tag declarations of autoOpen (that an
# element can be opened automatically, if needed) we derive an implicit model.
# Thus, if we want to insert an element (or, say #PCDATA) into an
# element that doesn't allow it, we may find an implied element
# to create & insert, and insert the #PCDATA into it.

sub loadDocType {
  my($self)=@_;
  $$self{doctype_loaded}=1;
  NoteProgress("\n(Loading DocType ");
  if(!$$self{system_id}){
    Warn("No DTD declared...assuming LaTeXML!");
    # article ??? or what ? undef gives problems!
    $self->setDocType(undef,"-//NIST LaTeXML//LaTeXML article",'LaTeXML.dtd',
		      "http://dlmf.nist.gov/LaTeXML");
    $$self{permissive}=1;	# Actually, they could have declared all sorts of Tags....
#    return; 
  }
  # Parse the DTD
  foreach my $dir (@INC){	# Load catalog (all, 1st only ???)
    next unless -f "$dir/LaTeXML/dtd/catalog";
    NoteProgress("\n(Loading XML Catalog $dir/LaTeXML/dtd/catalog");
    XML::LibXML->load_catalog("$dir/LaTeXML/dtd/catalog"); 
    NoteProgress(")");
    last; }
  NoteProgress("\n(Loading DTD for $$self{public_id} $$self{system_id}");
  my $dtd = XML::LibXML::Dtd->new($$self{public_id},$$self{system_id});
  if($dtd){
    NoteProgress("via catalog "); }
  else { # Couldn't find dtd in catalog, try finding the file. (search path?)
    my @paths = (@{ $STATE->lookupValue('SEARCHPATHS') },
		 map("$_/dtd", @INC));
    my $dtdfile = pathname_find($$self{system_id},paths=>[@paths]);
    if($dtdfile){
      { local $/=undef;
	NoteProgress("from $dtdfile ");
	if(open(DTD,$dtdfile)){
	  my $dtdtext = <DTD>;
	  close(DTD);
	  $dtd = XML::LibXML::Dtd->parse_string($dtdtext); 
	  Error("Parsing of DTD \"$$self{public_id}\" \"$$self{system_id}\" failed") unless $dtd; }
	else {
	  Error("Couldn't read DTD from $dtdfile"); }}}
    else {
      Error("Couldn't find DTD \"$$self{public_id}\" \"$$self{system_id}\" failed"); }}
  NoteProgress(")");		# Done reading DTD
  return unless $dtd;

  $$self{dtd}=$dtd;
  NoteProgress("(Analyzing DTD");
  # Extract all possible children for each tag.
  foreach my $node ($dtd->childNodes()){
    if($node->nodeType() == XML_ELEMENT_DECL()){
      my $decl = $node->toString();
      chomp($decl);
      if($decl =~ /^<!ELEMENT\s+([a-zA-Z0-9\-\_\:]+)\s+(.*)>$/){
	my($tag,$model)=($1,$2);
	$model=~ s/[\*\?\,\(\)\|]/ /g;
	$model=~ s/\s+/ /g; $model=~ s/^\s+//; $model=~ s/\s+$//;
	$$self{tagprop}{$tag}{model}={ map(($_ => 1), split(/ /,$model))};
      }
      else { warn("Warning: got \"$decl\" from DTD");}
    }
    elsif($node->nodeType() == XML_ATTRIBUTE_DECL()){
      $$self{tagprop}{$1}{attributes}{$2}=1
	if($node->toString =~ /^<!ATTLIST\s+([a-zA-Z0-0-+]+)\s+([a-zA-Z0-0-+]+)\s+(.*)>$/) }
    }
  # Determine any indirect paths to each descendent via an `autoOpen-able' tag.
  foreach my $tag (keys %{$$self{tagprop}}){
    local %::DESC=();
    computeDescendents($self,$tag,''); 
    $$self{tagprop}{$tag}{indirect_model}={%::DESC}; }
  # PATCHUP
  if($$self{permissive}){
    $$self{tagprop}{_Document_}{indirect_model}{'#PCDATA'}='p'; }
  NoteProgress(")");		# Done analyzing

  if(0){
    print STDERR "Doctype\n";
    foreach my $tag (sort keys %{$$self{tagprop}}){
      print STDERR "$tag can contain ".join(', ',sort keys %{$$self{tagprop}{$tag}{model}})."\n"; 
      print STDERR "$tag can indirectly contain ".
	join(', ',sort keys %{$$self{tagprop}{$tag}{indirect_model}})."\n";  }}
  NoteProgress(")");		# done Loading
}

sub computeDescendents {
  my($self,$tag,$start)=@_;
  foreach my $kid (keys %{$$self{tagprop}{$tag}{model}}){
    next if $::DESC{$kid};
    $::DESC{$kid}=$start if $start;
    if($$self{tagprop}{$kid}{autoOpen}){
      computeDescendents($self,$kid,$start||$kid); }
  }
}


#**********************************************************************
# Rewrite Rules

sub addRewriteRule {
  my($self,$mode,@specs)=@_;
  push(@{$$self{rewrites}},LaTeXML::Rewrite->new($mode,@specs)); }

sub applyRewrites {
  my($self,$document,$node, $until_rule)=@_;
  foreach my $rule (@{$$self{rewrites}}){
    last if $until_rule && ($rule eq $until_rule);
    $rule->rewrite($document,$node); }}

#**********************************************************************
1;

__END__

=pod 

=head1 NAME

C<LaTeXML::Model> -- represents the Document Model

=head1 DESCRIPTION

C<LaTeXML::Model> encapsulates information about the document model to be used
in converting a digested document into XML by the L<LaTeXML::Document>.
This information is based on the DTD, but may also be modified by
modules implementing various macro packages; thus the model may not be
complete until digestion is completed.

The kinds of information that is relevant is not only the content model
(what each element can contain contain), but also SGML-like information
such as whether an element can be implicitly opened or closed, if needed
to insert a new element into the document.

Currently, only a DTD is understood (no schema yet), and even there, the 
stored model is only approximate.  For example, we only record that
certain elements can appear within another; we don't preserve any
information about required order or number of instances.

=head2 Model Creation

=over 4

=item C<< $MODEL = LaTeXML::Model->new(%options); >>

Creates a new model.  The only useful option is
C<< permissive=>1 >> which ignores any DTD and allows the
document to be built without following any particular content model.

=back

=head2 Document Type

=over 4

=item C<< $name = $MODEL->getRootName; >>

Return the name of the expected root element.

=item C<< $publicid = $MODEL->getPublicID; >>

Return the public identifier for the document type.

=item C<< $systemid = $MODEL->getSystemID; >>

Return the system identifier for the document type
(typically a filename for the DTD).

=item C<< $MODEL->setDocType($rootname,$publicid,$systemid,$namespace); >>

Sets the root element name and the public and system identifiers
for the desired document type, as well as the default namespace URI.

=back

=head2 Namespaces

=over 4

=item C<< $namespace = $MODEL->getDefaultNamespace; >>

Return the default namespace url.

=item C<< $MODEL->registerNamespace($prefix,$namespace_url,$default); >>

Register C<$prefix> to stand for the namespace C<$namespace_url>.
If C<$default> is true, make this namespace the default one.
This will be used as the namespace for any unprefixed tags.

=item C<< $MODEL->getNamespacePrefix($namespace); >>

Return the prefix to use for the given C<$namespace>.

=item C<< $MODEL->getNamespace($prefix); >>

Return the namespace url for the given C<$prefix>.

=back

=head2 Model queries

=over 2

=item C<< $boole = $MODEL->canContain($tag,$childtag); >>

Returns whether an element C<$tag> can contain an element C<$childtag>.
The element names #PCDATA, _Comment_ and _ProcessingInstruction_
are specially recognized.

=item C<< $auto = $MODEL->canContainIndirect($tag,$childtag); >>

Checks whether an element C<$tag> could contain an element C<$childtag>,
provided an `autoOpen'able element C<$auto> were inserted in C<$tag>.

=item C<< $boole = $MODEL->canContainSomehow($tag,$childtag); >>

Returns whether an element C<$tag> could contain an element C<$childtag>,
either directly or indirectly.

=item C<< $boole = $MODEL->canAutoClose($tag); >>

Returns whether an element C<$tag> is allowed to be closed automatically,
if needed.

=item C<< $boole = $MODEL->canHaveAttribute($tag,$attribute); >>

Returns whether an element C<$tag> is allowed to have an attribute
with the given name.

=back

=head2 Tag Properties

=over 2

=item C<< $value = $MODEL->getTagProperty($tag,$property); >>

Gets the value of the $property associated with the element name C<$tag>.
Known properties are:

   autoOpen   : This asserts that the tag is allowed to be
                opened automatically if needed to insert some 
                other element.  If not set this tag will need to
                be explicitly opened.
   autoClose  : This asserts that the $tag is allowed to be 
                closed automatically if needed to insert some
                other element.  If not set this tag will need 
                to be explicitly closed.
   afterOpen  : supplies code to be executed whenever an element
                of this type is opened.  It is called with the
                created node and the responsible digested object
                as arguments.
   afterClose : supplies code to be executed whenever an element
                of this type is closed.  It is called with the
                created node and the responsible digested object
                as arguments.

=item C<< $MODEL->setTagProperty($tag,$property,$value); >>

sets the value of the C<$property> associated with the element name C<$tag> to C<$value>.

=back

=head2 Rewrite Rules

=over 2

=item C<< $MODEL->addRewriteRule($mode,@specs); >>

Install a new rewrite rule with the given C<@specs> to be used 
in C<$mode> (being either C<math> or C<text>).
See L<LaTeXML::Rewrite> for a description of the specifications.

=item C<< $MODEL->applyRewrites($document,$node,$until_rule); >>

Apply all matching rewrite rules to C<$node> in the given document.
If C<$until_rule> is define, apply all those rules that were defined
before it, otherwise, all rules

=back

=head1 AUTHOR

Bruce Miller <bruce.miller@nist.gov>

=head1 COPYRIGHT

Public domain software, produced as part of work done by the
United States Government & not subject to copyright in the US.

=cut
