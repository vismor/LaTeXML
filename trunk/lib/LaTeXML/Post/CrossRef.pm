# /=====================================================================\ #
# |  LaTeXML::Post::CrossRef                                            | #
# | Scan for ID's etc                                                   | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package LaTeXML::Post::CrossRef;
use strict;
use LaTeXML::Util::Pathname;
use LaTeXML::Common::XML;
use charnames qw(:full);
use base qw(LaTeXML::Post);

our $PILCROW = "\N{PILCROW SIGN}";
our $SECTION = "\N{SECTION SIGN}";
our %TYPEPREFIX = 
  ('ltx:equation'     =>'Eq.',
   'ltx:equationmix'  =>'Eq.',
   'ltx:equationgroup'=>'Eq.',
   'ltx:figure'       =>'Fig.',
   'ltx:table'        =>'Tab.',
   'ltx:chapter'      =>'Ch.',
   'ltx:part'         =>'Pt.',
   'ltx:section'      =>$SECTION,
   'ltx:subsection'   =>$SECTION,
   'ltx:subsubsection'=>$SECTION,
   'ltx:paragraph'    =>$PILCROW,
   'ltx:subparagraph' =>$PILCROW,
   'ltx:para'         =>'p',
#   'ltx:appendix'     =>'App.',
 );

sub new {
  my($class,%options)=@_;
  my $self = $class->SUPER::new(%options);
  $$self{db}       = $options{db};
  $$self{urlstyle} = $options{urlstyle};
  $$self{toc_show} = ($options{number_sections} ? "typerefnum title" : "title");
  $$self{ref_show} = ($options{number_sections} ? "typerefnum" : "title");
  $self; }

sub process {
  my($self,$doc)=@_;
  $self->ProgressDetailed($doc,"Beginning cross-references");
  my $root = $doc->getDocumentElement;
  local %LaTeXML::Post::CrossRef::MISSING=();
  $self->fill_in_navigation($doc);
  $self->fill_in_frags($doc);
  $self->fill_in_refs($doc);
  $self->fill_in_bibrefs($doc);
  if(($$self{verbosity} >= 0) && (keys %LaTeXML::Post::CrossRef::MISSING)){
    my @msgs=();
    foreach my $type (sort keys %LaTeXML::Post::CrossRef::MISSING){
      push(@msgs,$type.": ".join(', ',sort keys %{$LaTeXML::Post::CrossRef::MISSING{$type}}));}
    $self->Warn($doc,"Missing keys:\n  ".join(";\n  ",@msgs)); }
  $self->ProgressDetailed($doc,"done cross-references");
  $doc; }

sub note_missing {
  my($self,$type,$key)=@_;
  $LaTeXML::Post::CrossRef::MISSING{$type}{$key}++; }

sub fill_in_navigation {
  my($self,$doc)=@_;
  if(my $id = $doc->getDocumentElement->getAttribute('xml:id')){
    if(my $entry = $$self{db}->lookup("ID:$id")){
      # Add navigation in any case?
      $doc->addNodes($doc->getDocumentElement, ['ltx:navigation',{}]);
      if(my $nav = $doc->findnode('//ltx:navigation')){
	my $startref =$doc->findnode('ltx:ref[@class="start"]',$nav);
	my $start_id = $startref && $startref->getAttribute('idref');
	my $h_id = $id;
	# Generate Downward TOC
	my $navtoc= $self->navtoc_aux($id, $entry->getValue('location')||'');
	# And Upward Context
	my $p_id;
	while(($p_id = $entry->getValue('parent')) && ($entry = $$self{db}->lookup("ID:$p_id"))){
	  $navtoc = ['ltx:toclist',{},
		     map(['ltx:tocentry',
			  {($_ eq $id ? (class=>'self'):())},
			  ['ltx:ref',{class=>'toc',idref=>$_,show=>'fulltitle'}],
			  (($_ eq $h_id) && $navtoc ? ($navtoc) : ())],
			 @{ $entry->getValue('children')||[] })];
	  $h_id = $p_id; }
	$navtoc = ['ltx:toclist',{},
		   ['ltx:tocentry',{},
		    ['ltx:ref',{class=>'toc',show=>'fulltitle',idref=>$h_id}],
		    $navtoc]] if $h_id && (!$start_id || ($start_id ne $h_id));
	$doc->addNodes($nav,$navtoc); }
    }}}

sub navtoc_aux {
  my($self,$id, $relative_to)=@_;
  if(my $entry = $$self{db}->lookup("ID:$id")){
    if(($entry->getValue('location')||'') eq $relative_to){
      my $kids = $entry->getValue('children');
      if($kids && @$kids){
	return (['ltx:toclist',{},map(['ltx:tocentry',{},
				       ['ltx:ref',{class=>'toc',show=>'fulltitle',idref=>$_}],
				       $self->navtoc_aux($_,$relative_to)],
				      @$kids)]); }}}
  (); }

sub fill_in_frags {
  my($self,$doc)=@_;
  my $db = $$self{db};
  # Any nodes with an ID will get a fragid;
  # This is the id/name that will be used within xhtml/html.
  foreach my $node ($doc->findnodes('//@xml:id')){
    if(my $entry = $db->lookup("ID:".$node->value)){
      if(my $fragid = $entry->getValue('fragid')){
	$node->parentNode->setAttribute(fragid=>$fragid); }}}}

# Fill in content text for any <... @idref..>'s or @labelref
sub fill_in_refs {
  my($self,$doc)=@_;
  my $db = $$self{db};
  $self->ProgressDetailed($doc,"Filling in refs");
  foreach my $ref ($doc->findnodes('descendant::*[@idref or @labelref]')){
    my $tag = $doc->getQName($ref);
    next if $tag eq 'ltx:XMRef'; # Blech; list those TO fill-in, or list those to exclude?
    my $id = $ref->getAttribute('idref');
    my $show = $ref->getAttribute('show');
    $show = $$self{ref_show} unless $show;
    $show = $$self{toc_show} if $show eq 'fulltitle';
    if(!$id){
      if(my $label = $ref->getAttribute('labelref')){
	my $entry;
	if(($entry = $db->lookup($label)) && ($id=$entry->getValue('id'))){
	  $show =~ s/^type//; 	# Since author may have put explicit \S\ref... in! 
	}
	else {
	  $self->note_missing('Label',$label);
	  if(!$ref->textContent){
	    $doc->addNodes($ref,$label);  # Just to reassure (?) readers.
	    $ref->setAttribute(broken=>1); }
	}}}
    if($id){
      if(!$ref->getAttribute('href')){
	if(my $url = $self->generateURL($doc,$id)){
	  $ref->setAttribute(href=>$url); }}
      if(!$ref->getAttribute('title')){
	if(my $titlestring = $self->generateTitle($id)){
	  $ref->setAttribute(title=>$titlestring); }}
      if(!$ref->textContent && !(($tag eq 'ltx:graphics') || ($tag eq 'ltx:picture'))){
	$doc->addNodes($ref,$self->generateRef($doc,$id,$show)); }
      if(my $entry = $$self{db}->lookup("ID:$id")){
	$ref->setAttribute(stub=>1) if $entry->getValue('stub'); }
    }}}


# Needs to evolve into the combined stuff that we had in DLMF.
# (eg. concise author/year combinations for multiple bibrefs)
sub fill_in_bibrefs {
  my($self,$doc)=@_;
  $self->ProgressDetailed($doc,"Filling in bibrefs");
  my $db = $$self{db};
  foreach my $bibref ($doc->findnodes('descendant::ltx:bibref')){
    my $show   = $bibref->getAttribute('show');
    # Messy, since we're REPLACING the bibref with it's expansion.
    my @save = ();
    my ($p,$s) = ($bibref->parentNode, undef);
    while(($s = $p->lastChild) && ($$s != $$bibref)){ # Remove & Save following siblings.
      unshift(@save,$p->removeChild($s)); }
    $doc->removeNodes($bibref);
#    $doc->addNodes($p,$self->make_bibcite($doc,$show,split(/,/,$bibref->getAttribute('bibrefs'))));
    $doc->addNodes($p,$self->make_bibcite($doc,$bibref));
    map($p->appendChild($_),@save); # Put these back.
 }}

# Given a list of bibkeys, construct links to them.
# Mostly tuned to author-year style.
# Combines when multiple bibitems share the same authors.

# WORK OUT the fallback when BibTeX wasn't used...
# IE. explicit thebibliography
sub XXXXXmake_bibcite {
  my($self,$doc, $show,@keys)=@_;
    my @data = ();
    foreach my $key (@keys){
      if(my $bentry = $$self{db}->lookup("BIBLABEL:$key")){
	if(my $id = $bentry->getValue('id')){
	  if(my $entry = $$self{db}->lookup("ID:$id")){
	    my $names = $entry->getValue('names');
	    my $year  = $entry->getValue('year');
	    my $title = $entry->getValue('title');
	    my $refnum= $entry->getValue('refnum'); # This come's from the \bibitem, w/o BibTeX
	    $show = 'refnum' unless $names;	    # Disable author-year format!
	    push(@data,{names    =>[$doc->trimChildNodes($names)],
			namestext=>($names ? $names->textContent :''),
			year     =>[$doc->trimChildNodes($year)],
			refnum   =>[$doc->trimChildNodes($refnum)],
			title    =>[$doc->trimChildNodes($title)],
			attr=>{idref=>$id,
			       href=>$self->generateURL($doc,$id),
			       ($title ? (title=>$title->textContent):())}}); }}}
      else {
	$self->note_missing('Citation',$key); }}
  if(!$show){			# Default is like author(year), but combine same authors
    my @stuff=();
    while(@data){
      push(@stuff,', ') if @stuff;
      my $datum = shift(@data);
      my @group = ();
      while($$datum{namestext} && @data
	    && ($$datum{namestext} eq $data[0]->{namestext})){
	push(@group,shift(@data)); }
      if(@group){
	push(@stuff,@{$$datum{names}},
	     '(',['ltx:ref',$$datum{attr}, @{$$datum{year}}]);
	foreach my $next (@group){
	  push(@stuff,', ', ['ltx:ref',$$next{attr}, @{$$next{year}}]); }
	push(@stuff,')'); }
      else {
	push(@stuff,
	     ['ltx:ref',$$datum{attr}, @{$$datum{names}},'(', @{$$datum{year}},')']); }}
    @stuff; }
  else {
    my @refs=();
    my $saveshow = $show;
    foreach my $datum (@data){
      my @stuff=();
      while($show){
	if(($show =~ s/^author//) || ($show =~ s/^names//)){
	  push(@stuff,@{$$datum{names}}); }
	elsif(($show =~ s/^year//) || ($show =~ s/^date//)){
	  push(@stuff,@{$$datum{year}}); }
	elsif($show =~ s/^title//){
	  push(@stuff,@{$$datum{title}}); }
	elsif($show =~ s/^refnum//){
	  push(@stuff,@{$$datum{refnum}}); }
	elsif($show =~ s/^(.)//){
	  push(@stuff, $1); }}
      push(@refs,['ltx:ref',$$datum{attr},@stuff]); 
      $show=$saveshow; }
    $doc->conjoin(', ',@refs); }}


sub make_bibcite {
  my($self,$doc,$bibref)=@_;
  my $show = $bibref->getAttribute('show');
  my @keys = split(/,/,$bibref->getAttribute('bibrefs'));
  my $sep  = $bibref->getAttribute('separator') || ', ';
  my $yysep= $bibref->getAttribute('yyseparator') || ', ';
  my @phrases = $bibref->getChildNodes();	  # get the ltx;note's in the bibref!
  # Collect all the data from the bibliography
  my @data = ();
  foreach my $key (@keys){
    if(my $bentry = $$self{db}->lookup("BIBLABEL:$key")){
      if(my $id = $bentry->getValue('id')){
	if(my $entry = $$self{db}->lookup("ID:$id")){
	  my $names = $entry->getValue('names');
	  my $fnames= $entry->getValue('fullnames');
	  my $year  = $entry->getValue('year');
	  my $number= $entry->getValue('number');
	  my $title = $entry->getValue('title');
	  my $refnum= $entry->getValue('refnum'); # This come's from the \bibitem, w/o BibTeX
	  $show = 'refnum' unless $names;	    # Disable author-year format!
	  # fullnames ?
	  push(@data,{names    =>[$doc->trimChildNodes($names)],
		      namestext=>($names ? $names->textContent :''),
		      fullnames=>[$doc->trimChildNodes(($fnames ? $fnames : $names))],
		      year     =>[$doc->trimChildNodes($year)],
		      rawyear  =>($year ? $year->getAttribute('rawyear') : undef),
		      suffix   =>($year ? $year->getAttribute('suffix') : undef),
		      number   =>[$doc->trimChildNodes($number)],
		      refnum   =>[$doc->trimChildNodes($refnum)],
		      title    =>[$doc->trimChildNodes($title)],
		      attr=>{idref=>$id,
			     href=>$self->generateURL($doc,$id),
			     ($title ? (title=>$title->textContent):())}}); }}}
    else {
      $self->note_missing('Citation',$key); }}
  my $checkdups = ($show =~ /author/i) && ($show =~ /(year|number)/i);
  my @refs=();
  my $saveshow = $show;
  while(@data){
    my $datum = shift(@data);
    my $didref = 0;
    my @stuff=();
    $show=$saveshow;
    while($show){
      if($show =~ s/^author//i){
	push(@stuff,@{$$datum{names}}); }
      if($show =~ s/^fullauthor//i){
	push(@stuff,@{$$datum{fullnames}}); }
      elsif($show =~ s/^title//i){
	push(@stuff,@{$$datum{title}}); }
      elsif($show =~ s/^refnum//i){
	push(@stuff,@{$$datum{refnum}}); }
      elsif($show =~ s/^phrase(\d)//i){
	push(@stuff,$phrases[$1-1]->childNodes) if $phrases[$1-1]; }
      elsif($show =~ s/^year//i){
	if($checkdups && @data && ($$datum{namestext} eq $data[0]{namestext})){
	  push(@stuff,['ltx:ref',$$datum{attr},@{$$datum{year}}]);
	  # NOTE: This needs to deal with YEARa,b situations too!
	  while($checkdups && @data && ($$datum{namestext} eq $data[0]{namestext})){
	    my $next = shift(@data);
	    push(@stuff, $yysep);
	    if((($$datum{rawyear}||'x') eq ($$next{rawyear}||'y')) && $$next{suffix}){
	      push(@stuff,['ltx:ref',$$next{attr},$$next{suffix}]);  }
	    else {
	      push(@stuff,['ltx:ref',$$next{attr},@{$$next{year}}]);  }}
	  $didref=1; }
	else {
	  push(@stuff,@{$$datum{year}}); }}
      elsif($show =~ s/^number//i){
	if($checkdups && @data && ($$datum{namestext} eq $data[0]{namestext})){
	  push(@stuff,['ltx:ref',$$datum{attr},@{$$datum{number}}]);
	  while($checkdups && @data && ($$datum{namestext} eq $data[0]{namestext})){
	    my $next = shift(@data);
	    push(@stuff, ", ");	# GET FROM bibref!
	    push(@stuff,['ltx:ref',$$next{attr},@{$$next{number}}]);  }
	  $didref=1; }
	else {
	  push(@stuff,@{$$datum{number}}); }}
      elsif($show =~ s/^(.)//){
	push(@stuff, $1); }}
    push(@refs,
	 (@refs ? ($sep) : ()),
	 ($didref ? @stuff : (['ltx:ref',$$datum{attr},@stuff]))); }
  @refs; }

sub generateURL {
  my($self,$doc,$id)=@_;
  my($object,$location);
  if(($object = $$self{db}->lookup("ID:".$id))
     && ($location = $object->getValue('location'))){
    my $doclocation = $self->siteRelativePathname($doc->getDestination);
    my $url = pathname_relative('/'.$location,  '/'.pathname_directory($doclocation));
    my $format = $$self{format} || 'xml';
    my $urlstyle = $$self{urlstyle}||'file';
    if($urlstyle eq 'server'){
      $url =~ s/(^|\/)index.\Q$format\E$/$1/; } # Remove trailing index.$format
    elsif($urlstyle eq 'negotiated'){
      $url =~ s/\.\Q$format\E$//; # Remove trailing $format
      $url =~ s/(^|\/)index$/$1/; # AND trailing index
    }
    $url = '.' unless $url;
#    $url .= '/' if ($url ne '.') && ($url =~ /\/$/);
    if(my $fragid = $object->getValue('fragid')){
      $url = '' if ($url eq '.') or ($location eq $doclocation);
      $url .= '#'.$fragid; }
    elsif($location eq $doclocation){
      $url = ''; }
    $url; }
  else {
    $self->note_missing('ID',$id); }}

# Generate the contents of a <ltx:ref> of the given id.
# show is a string containing substrings 'type', 'refnum' and 'title'
# (standing for the type prefix, refnum and title of the id'd object)
# and any other random characters; the
our $NBSP = pack('U',0xA0);
sub generateRef {
  my($self,$doc,$id,$show)=@_;
  my $fallback_show = ($show !~ /title/ ? "title" : "refnum");
  my @fallback=();
  # Find entry associated with $id, or first ancestor, that can fill in the show pattern.
  while(my $entry = $id && $$self{db}->lookup("ID:$id")){
    my @stuff = $self->generateRef_aux($doc,$entry,$show);
    return @stuff if @stuff;
    @fallback = $self->generateRef_aux($doc,$entry,$fallback_show) unless @fallback;
    $id = $entry->getValue('parent'); }
  (@fallback ? @fallback : ("?")); }

# Interpret a "Show" pattern for a given DB entry.
# The pattern can contain substrings to be substituted
#   type   => the type prefix (eg Ch. or similar)
#   refnum => the reference number
#   title  => the title.
# and any other random characters which are preserved.
sub generateRef_aux {
  my($self,$doc,$entry,$show)=@_;
  my $OK=0;
  my @stuff=();
  while($show){
    if($show =~ s/^typerefnum(\.?\s*)//){
      my $r = $1;
      $r =~ s/\s+/$NBSP/ if $r;
      my @rest = ($1 ? ($1):());
      if(my $refnum = $entry->getValue('refnum')){
	my $type   = $entry->getValue('type');
	$OK = 1;
	push(@stuff, ['ltx:span',{class=>'refnum'},
		      ($type && $TYPEPREFIX{$type} ? ($TYPEPREFIX{$type}) :()),
		      $doc->trimChildNodes($refnum),
		      ($r ? ($r):())]); }}
    elsif($show =~ s/^type(\.?\s*)//){
      my $r = $1;
      $r =~ s/\s+/$NBSP/ if $r;
      my $type   = $entry->getValue('type');
      if($type && $TYPEPREFIX{$type}){
	$OK = 1;
	push(@stuff, $TYPEPREFIX{$type},($r ? ($r):())); }}
    elsif($show =~ s/^refnum(\.?\s*)//){
      my $r = $1;
      $r =~ s/\s+/$NBSP/ if $r;
      if(my $refnum = $entry->getValue('refnum')){
	$OK = 1;
	push(@stuff, ['ltx:span',{class=>'refnum'},
		      $doc->trimChildNodes($refnum),
		      ($r ? ($r):())]); }}
    elsif($show =~ s/^title//){
      if(my $title = $entry->getValue('title')){
	$OK = 1;
	push(@stuff, ['ltx:span',{class=>'title'},$doc->trimChildNodes($title)]); }}
    elsif($show =~ s/^(.)//){
      push(@stuff, $1); }}
  ($OK ? @stuff : ()); }

sub generateTitle {
  my($self,$id)=@_;
  # Add author, if any ???
  my $string = "";
  while(my $entry = $id && $$self{db}->lookup("ID:$id")){
    my $title  = $entry->getValue('title');
    $title = $title->textContent if $title && ref $title;
    $title =~ s/^\s+// if $title;
    $title =~ s/\s+$// if $title;
    my $refnum = ($$self{number_sections} ? $entry->getValue('refnum') : '');
    $refnum = $refnum->textContent if $refnum && ref $refnum;
    $refnum =~ s/^\s+// if $refnum;
    $refnum =~ s/\s+$// if $refnum;
    if($title || $refnum){
      $string .= ' in ' if $string;
      my $type   = $entry->getValue('type');
      $string .= $TYPEPREFIX{$type} if $TYPEPREFIX{$type};
      $string .= $refnum if $refnum;
      $string .= ($refnum ? '. ':'').$title if $title; }
    $id = $entry->getValue('parent'); }
  $string; }

# ================================================================================
1;

