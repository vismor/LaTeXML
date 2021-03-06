# /=====================================================================\ #
# |  LaTeXML::Post::Graphics                                            | #
# | Graphics postprocessing for LaTeXML                                 | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #
#======================================================================
# Adapted from graphics-support.perl of LaTeX2HTML (which I had rewritten)
#======================================================================
package LaTeXML::Post::Graphics;
use strict;
use XML::LibXML;
use LaTeXML::Util::Pathname;
use POSIX;
use Image::Magick;
use LaTeXML::Post;
our @ISA = (qw(LaTeXML::Post::Processor));

#======================================================================
# Options:
#   dpi : dots per inch for target medium.
#   ignore_options  : list of graphicx options to be ignored.
#   warn_options    : list of graphicx options to cause warning if used.
#   trivial_scaling : If true, web images that only need scaling will be used as-is
#                     assuming the user agent scale the image.
#   background      : background color when filling or transparency.
#   type_map        : hash of types=>hash.
#        The hash for each type can have the following 
#           type        : the type to convert the file to.
#           transparent : if true, the background color will be made transparent.
#           quality     : the `quality' used for the image.
#           ncolors     : the image will be quantized to ncolors.
#           prescale    : If true, and there are leading (or only) scaling commands,
#                         compute the new image size and re-read the image into that size
#                         This is useful for getting the best antialiasing for postscript, eg.
sub new {
  my($class,%options)=@_;
  my $self = bless {dppt              => (($options{dpi}||100)/72.0), # Dots per point.
		    ignoreOptions     => $options{ignoreOptions}   || [],
		    trivial_scaling   => $options{trivial_scaling}  || 1,
		    graphicsSourceTypes => $options{graphicsSourceTypes} || [qw(png gif jpg jpeg eps ps)],
		    type_map          => $options{type_map} || { ps  =>{type=>'png', prescale=>1,
									transparent=>1, ncolors=>'400%',
									quality=>90},
								 eps =>{type=>'png', prescale=>1,
									transparent=>1, ncolors=>'400%',
									quality=>90},
								 jpg =>{type=>'jpg',ncolors=>'400%'},
								 jpeg=>{type=>'jpeg', ncolors=>'400%'},
								 gif =>{type=>'gif', 
									transparent=>1, ncolors=>'400%'},
								 png =>{type=>'png', transparent=>1,
									ncolors=>'400%'}},
		    background        => $options{background}       || "#FFFFFF",
		   },$class; 
  $self->init(%options); 
  $self; }

sub process {
  my($self,$doc)=@_;
  $self->findGraphicsPaths($doc);
  $self->ProgressDetailed("Using graphicspaths: ".join(', ',@{$self->getSearchPaths}));

  my @nodes = $self->selectGraphicsNodes($doc);
  $self->Progress(scalar(@nodes)." graphics nodes to process");
  foreach my $node (@nodes){
    $self->processGraphic($node);  }
  $doc; }

#======================================================================
# Potentially customizable operations.
# find graphics file
#  Need to deal with source directory, as well as graphicspath.

# Extract any graphicspath PI's from the document and return a reference 
# to a list of search paths.
sub findGraphicsPaths {
  my($self,$doc)=@_;
  foreach my $pi ($doc->findnodes('.//processing-instruction("latexml")')){
    if($pi->textContent =~ /^\s*graphicspath\s*=\s*([\"\'])(.*?)\1\s*$/){
      my $value=$2;
      while($value=~ s/^\s*\{(.*?)\}//){
	$self->addSearchPath($1); }}}}

# Return a list of ZML nodes which have graphics that need processing.
sub selectGraphicsNodes {
  my($self,$doc)=@_;
  $doc->getElementsByTagNameNS($self->getNamespace,'graphics'); }

# Return the pathname to an appropriate image.
sub findGraphicsFile {
  my($self,$node)=@_;
  my $name = $node->getAttribute('graphic');
  ($name ? $self->findFile($name,$$self{graphicsSourceTypes}) : undef); }

# Return the Transform to be used for this node
# Default is based on parsing the graphicx options
sub getTransform {
  my($self,$node)=@_;
  my $options = $node->getAttribute('options');
  ($options ? $self->parseOptions($options) : []); }

# Get a hash of the image processing properties to be applied to this image.
sub get_type_map {
  my($self,$source,$options)=@_;
  my($dir,$name,$type)=pathname_split($source);
  $$self{type_map}{$type}; }

# Set the attributes of the graphics node to record the image file name,
# width and height.
sub setGraphicsSrc {
  my($self,$node,$src,$width,$height)=@_;
  $node->setAttribute('src',$src);
  $node->setAttribute('width',$width);
  $node->setAttribute('height',$height);
}

sub processGraphic {
  my($self,$node)=@_;
  my $source = $self->findGraphicsFile($node);
  if(!$source){
    $self->Warn("Missing graphic for $node; skipping"); return; }
  my $transform = $self->getTransform($node);
  my($image,$width,$height)=$self->transformGraphic($node,$source,$transform); 
  $self->setGraphicsSrc($node,$image,$width,$height) if $image;
}

#======================================================================

sub transformGraphic {
  my($self,$node,$source,$transform)=@_;
  my ($reldir,$name,$type) = pathname_split(pathname_relative($source,$self->getSourceDirectory));

  my $key = join('|',"$reldir$name.$type", map(join(' ',@$_),@$transform));
  $self->ProgressDetailed("Processing $key");

  my $map       = $self->get_type_map($source,$transform);
  return warn "Don't know what to do with graphics file format $source" unless $map;
  my $newtype = $$map{type} || $type;

  if(my $prev = $self->cacheLookup($key)){	# Image was processed on previous run?
    $prev =~ /^(.*?)\|(\d+)\|(\d+)$/;
    my ($cached,$width,$height)=($1,$2,$3);
    $self->ProgressDetailed(">> Reuse $cached @ $width x $height"); 
    ($cached,$width,$height); }
  # Trivial scaling case: Use original image with different width & height.
  elsif($$self{trivial_scaling} && ($newtype eq $type) && !grep(!($_->[0]=~/^scale/),@$transform)){
    my ($width,$height)=$self->trivial_scaling($source,$transform);
    my $copy = $self->copyFile($source);
    $self->ProgressDetailed(">> Copied to $copy for $width x $height");
    $self->cacheStore($key,"$copy|$width|$height");
    $self->ProgressDetailed(">> done with $key");
    ($copy,$width,$height); }
  else {
    my ($image,$width,$height) =$self->complex_transform($source,$transform, $map);
    my $N = $self->cacheLookup('_max_image_') || 0;
    my $newname = "$name-GEN". ++$N;
    $self->cacheStore('_max_image_',$N);

    my $destdir = pathname_concat($$self{destinationDirectory},$reldir);
    pathname_mkdir($destdir) 
      or return $self->Error("Could not create relative directory $destdir: $!");
    my $dest = pathname_make(dir=>$destdir,name=>$newname,type=>$newtype);
    $self->ProgressDetailed(">> Writing to $dest ");
    my $reldest = pathname_make(dir=>$reldir,name=>$newname,type=>$newtype);
    $image->Write(filename=>$dest) and warn "Couldn't write image $dest: $!";

    $self->cacheStore($key,"$reldest|$width|$height");
    $self->ProgressDetailed(">> done with $key");
    ($reldest,$width,$height); }
}

#======================================================================
# Compute the desired image size (width,height)
sub trivial_scaling {
  my($self,$source,$transform)=@_;

  my $image = Image::Magick->new(); 
  if(!$image->Read($source)){}	# ????
#  $image->
  my($w,$h) = $image->Get('width','height');

  foreach my $trans (@$transform){
    my($op,$a1,$a2,$a3,$a4)=@$trans;
    if($op eq 'scale'){		# $a1 => scale
      ($w,$h)=(ceil($w*$a1),ceil($h*$a1)); }
    elsif($op eq 'scale-to'){	# $a1 => width, $a2 => height, $a3 => preserve aspect ratio.
      if($a3){ # If keeping aspect ratio, ignore the most extreme request
	if($a1/$w < $a2/$h) { $a2 = $h*$a1/$w; }
	else                { $a1 = $w*$a2/$h; }}
      ($w,$h)=(ceil($a1*$$self{dppt}),ceil($a2*$$self{dppt})); }}
  return ($w,$h); }

# Transform the image, returning (image,width,height);
sub complex_transform {
  my($self,$source,$transform, $map)=@_;
  my $image = Image::Magick->new(); 
  $image->Set(antialias=>1);
  if(!$image->Read($source)){
# ?????? Seems to have read it???
#    warn("Failed to read image $source"); 
#    return; 
}
  my $orig_ncolors = $image->Get('colors');
  my ($w,$h) = $image->Get('width','height');
  my @transform = @$transform;

  # For prescaling, compute the desired size and re-read the image into that size,
  # with an appropriate density set.  This will give much better anti-aliasing.
  # Actually, we'll set the density & size up a further factor of $F, and then downscale.
  if($$map{prescale}){
    my($w0,$h0)=($w,$h);
    while(@transform && ($transform[0]->[0] =~ /^scale/)){
      my($op,$a1,$a2,$a3,$a4)=@{shift(@transform)};
      if($op eq 'scale'){	# $a1 => scale
	($w,$h)=(ceil($w*$a1),ceil($h*$a1)); }
      elsif($op eq 'scale-to'){ 
	# $a1 => width, $a2 => height, $a3 => preserve aspect ratio.
	if($a3){ # If keeping aspect ratio, ignore the most extreme request
	  if($a1/$w < $a2/$h) { $a2 = $h*$a1/$w; }
	  else                { $a1 = $w*$a2/$h; }}
	($w,$h)=(ceil($a1*$$self{dppt}),ceil($a2*$$self{dppt})); }}
    my $X = 4;			# Expansion factor
    my($dx,$dy)=(int($X * 72 * $w/$w0),int($X * 72 * $h/$h0)); 
    $self->ProgressDetailed(">> reloading to desired size $w x $h (density = $dx x $dy)");
    $image = Image::Magick->new();
    $image->Set(antialias=>1);
    $image->Set(density=>$dx.'x'.$dy); # Load at prescaled, higher density
    $image->Read($source);
    $image->Set(colorspace=>'RGB');
    $image->Scale(geometry=>int(100/$X)."%"); # Now downscale.
    ($w,$h) = $image->Get('width','height'); }

  my $notes='';
  foreach my $trans (@transform){
    my($op,$a1,$a2,$a3,$a4)=@$trans;
    if($op eq 'scale'){		# $a1 => scale
      ($w,$h)=(ceil($w*$a1),ceil($h*$a1));
      $notes .= " scale to $w x $h";
      $image->Scale(width=>$w,height=>$h); }
    elsif($op eq 'scale-to'){ 
      # $a1 => width, $a2 => height, $a3 => preserve aspect ratio.
      if($a3){ # If keeping aspect ratio, ignore the most extreme request
	if($a1/$w < $a2/$h) { $a2 = $h*$a1/$w; }
	else                { $a1 = $w*$a2/$h; }}
      ($w,$h)=(ceil($a1*$$self{dppt}),ceil($a2*$$self{dppt}));
      $notes .= " scale-to $w x $h";
      $image->Scale(width=>$w,height=>$h); }
    elsif($op eq 'rotate'){
      $image->Rotate(degrees=>-$a1,color=>$$self{background});
      ($w,$h) = $image->Get('width','height'); 
      $notes .= " rotate $a1 to $w x $h"; }
    # In the following two, note that TeX's coordinates are relative to lower left corner,
    # but ImageMagick's coordinates are relative to upper left.
    elsif(($op eq 'trim') || ($op eq 'clip')){
      my($x0,$y0,$ww,$hh);
      if($op eq 'trim'){ # Amount to trim: a1=left, a2=bottom, a3=right, a4=top
	($x0,$y0,$ww,$hh)=( floor($a1*$$self{dppt}),             floor($a4*$$self{dppt}),
			    ceil($w - ($a1 + $a3)*$$self{dppt}), ceil($h - ($a4 + $a2)*$$self{dppt})); 
	$notes .= " trim to $ww x $hh @ $x0,$y0"; }
      else {			# BBox: a1=left, a2=bottom, a3=right, a4=top
	($x0,$y0,$ww,$hh)=( floor($a1*$$self{dppt}),        floor($h - $a4*$$self{dppt}),
			    ceil(($a3 - $a1)*$$self{dppt}), ceil(($a4 - $a2)*$$self{dppt})); 
	$notes .= " clip to $ww x $hh @ $x0,$y0"; }

      if(($x0 > 0) || ($y0 > 0) || ($x0+$ww < $w) || ($y0+$hh < $h)){
	my $x0p=max($x0,0); $x0 = min($x0,0);
	my $y0p=max($y0,0); $y0 = min($y0,0);
	$image->Crop(x=>$x0p, width =>min($ww,$w-$x0p),
		     y=>$y0p, height=>min($hh,$h-$y0p));
	$w = min($ww+$x0, $w-$x0p);
	$h = min($hh+$y0, $h-$y0p); 
	$notes .= " crop $w x $h @ $x0p,$y0p"; }
      # No direct `padding' operation in ImageMagick
      my $nimage = Image::Magick->new();
      $nimage->Set('size',"$ww x $hh");
      $nimage->Read("xc:$$self{background}");
      $nimage->Composite(image=>$image, compose=>'over', x=>-$x0, y=>-$y0);
      $image=$nimage; 
      ($w,$h)=($ww,$hh);
    }}
  if(my $trans = $$map{transparent}){
    $notes .= " transparent=$$self{background}"; 
    $image->Transparent($$self{background}); }

  my $curr_ncolors = $image->Get('colors');
  if(my $req_ncolors = $$map{ncolors}){
    $req_ncolors = int($orig_ncolors * $1/ 100) if $req_ncolors =~ /^([\d]*)\%$/;
    if($req_ncolors < $curr_ncolors){
    $notes .= " quantize $orig_ncolors => $req_ncolors";
    $image->Quantize(colors=>$req_ncolors);  }}

  if(my $quality = $$map{quality}){
    $notes .= " quality=$quality";
    $image->Set('quality',$$map{quality}); }

  $self->ProgressDetailed(">> Transformed : $notes") if $notes;
  ($image,$w,$h); }

sub min { ($_[0] < $_[1] ? $_[0] : $_[1]); }
sub max { ($_[0] > $_[1] ? $_[0] : $_[1]); }

#**********************************************************************
# Note that viewport is supposed to be relative to bounding box,
# and EITHER ONE can cause clipping, if clip=true.
# However, apparently the INTENT of bounding box is simply to 
# supply one, if one can't be found, in order to determine the image size.
# In our case, we may end up getting a gif, jpeg, etc, whose origin is always 0,0,
# and whose size is clear; also postscript figures sizes will be determined
# by ghostview(?).  Another use of setting a bounding box, when clip=false,
# is to make the image lay ontop of neighboring text.  This isn't quite
# possible in HTML, other than possibly through some tricky CSS.
# Besides, I'd like to avoid reading the bb file, if I can.
# --- So, for all these reasons, we simply ignore bounding box here.

sub parseOptions {
  my($self,$options)=@_;
  local $_;
  # --------------------------------------------------
  # Parse options
  my ($v,$clip,$trim,$width,$height,$scale,$aspect,$a,$rotfirst,@bb,@vp,)
    =('', '',   '',   0,    0,   0,    '',      0, '',        0);
  my @unknown=();
  foreach (split(',',$options||'')){
    /^\s*(\w+)(=\s*(.*))?\s*$/;  $_=$1; $v=$3||'';
    my $op = $_;
    if(grep($op eq $_, @{$$self{ignoreOptions}})){  } # Ignore this option
    elsif(/^bb$/)               { @bb = map(to_bp($_),split(' ',$v)); }
    elsif(/^bb(ll|ur)(x|y)$/)   { $bb[2*/ur/ + /y/] = to_bp($v); }
    elsif(/^nat(width|height)$/){ $bb[2 + /width/] = to_bp($v); }
    elsif(/^viewport$/)         { @vp = map(to_bp($_),split(' ',$v)); $trim=0;}
    elsif(/^trim$/)             { @vp = map(to_bp($_),split(' ',$v)); $trim=1;}
    elsif(/^clip$/)             { $clip = !($v eq 'false'); }
    elsif(/^keepaspectratio$/)  { $aspect = !($v eq 'false'); }
    elsif(/^width$/)            { $width = to_bp($v); }
    elsif(/^(total)?height$/)   { $height = to_bp($v); }
    elsif(/^scale$/)            { $scale = $v; }
    elsif(/^angle$/)            { $a = $v; $rotfirst = !($width||$height||$scale); }
    elsif(/^origin$/)           { } # ??
    else { push(@unknown,[$op,$v]); }}
  # --------------------------------------------------
  # Now, compile the options into a sequence of `transformations'.
  # Note: the order of rotation & scaling is significant,
  # but the order of various clipping options w.r.t rotation or scaling is not.
  my @transform=();
  # We ignore viewport & trim if clip isn't set, since in that case we shouldn't 
  # actually remove anything from the image (and there's no way to have the image
  # overlap neighboring text, etc, in current HTML).
  push(@transform, [($trim ? 'trim' : 'clip'), @vp]) if(@vp && $clip);
  push(@transform,['rotate',$a]) if($rotfirst && $a); # Rotate before scaling?
  if($width && $height){ push(@transform,['scale-to',$width,$height,$aspect]); }
  elsif($width)        { push(@transform,['scale-to',$width,999999,1]); }
  elsif($height)       { push(@transform,['scale-to',999999,$height,1]); }
  elsif($scale)        { push(@transform,['scale',$scale]); }
  push(@transform,['rotate',$a]) if(!$rotfirst && $a);  # Rotate after scaling?
  #  ----------------------
  [@transform,@unknown]; }

our %BP_conversions=(pt=>72/72.27, pc=>12/72.27, in=>72, bp=>1,
		     cm=>72/2.54, mm=>72/25.4, dd=>(72/72.27)*(1238/1157),
		     cc=>12*(72/72.27)*(1238/1157),sp=>72/72.27/65536);
sub to_bp { 
  my($x)=@_;
  $x =~ /^\s*([+-]?[\d\.]+)(\w*)\s*$/;
  my($v,$u)=($1,$2);
  $v*($u ? $BP_conversions{$u} : 1); }


#======================================================================
1;
