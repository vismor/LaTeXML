# /=====================================================================\ #
# |  LaTeXML::Stomach                                                   | #
# | Analog of TeX's Stomach: digests tokens, stores state               | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package LaTeXML::Stomach;
use strict;
use LaTeXML::Global;
use LaTeXML::State;
use LaTeXML::Gullet;
use LaTeXML::Token;
use LaTeXML::Number;
use LaTeXML::Box;
use LaTeXML::Mouth;
use LaTeXML::Font;
use LaTeXML::Definition;
use base qw(LaTeXML::Object);

#**********************************************************************
sub new {
  my($class, %options)=@_;
  bless { gullet=> LaTeXML::Gullet->new(),
	  boxing=>[]}, $class; }

#**********************************************************************
# Initialize various parameters, preload, etc.
sub initialize {
  my($self)=@_;
  $$self{boxing} = [];
  $STATE->assignValue(MODE=>'text','global');
  $STATE->assignValue(IN_MATH=>0,'global');
  $STATE->assignValue(PRESERVE_NEWLINES=>1,'global');
  $STATE->assignValue(afterGroup=>[],'global');
  # Setup default fonts.
  $STATE->assignValue(font=>LaTeXML::Font->default(),'global');
  $STATE->assignValue(mathfont=>LaTeXML::MathFont->default(),'global');
}

#**********************************************************************
sub getGullet { $_[0]->{gullet}; }

sub getBoxingLevel { scalar(@{$_[0]->{boxing}}); }

#**********************************************************************
# Digestion
#**********************************************************************
# NOTE: Worry about whether the $autoflush thing is right?
# It puts a lot of cruft in Gullet; Should we just create a new Gullet?

sub digestNextBody {
  my($self)=@_;
  my $initdepth  = scalar(@{$$self{boxing}});
  my $token;
  local @LaTeXML::LIST=();
  while(defined($token=$$self{gullet}->readXToken(1))){ # Done if we run out of tokens
    push(@LaTeXML::LIST, $self->invokeToken($token));
    last if $initdepth > scalar(@{$$self{boxing}}); } # if we've closed the initial mode.
  push(@LaTeXML::LIST,LaTeXML::List->new()) unless $token; # Dummy `trailer' if none explicit.
  @LaTeXML::LIST; }

# Digest a list of tokens independent from any current Gullet.
# Typically used to digest arguments to primitives or constructors.
# Returns a List or MathList containing the digested material.
sub digest {
  my($self,$tokens)=@_;
  return undef unless defined $tokens;
  $$self{gullet}->openMouth((ref $tokens eq 'LaTeXML::Token' ? Tokens($tokens) : $tokens->clone),1);
  $STATE->clearPrefixes; # prefixes shouldn't apply here.
  my $ismath     = $STATE->lookupValue('IN_MATH');
  my $initdepth  = scalar(@{$$self{boxing}});
  my $depth=$initdepth;
  local @LaTeXML::LIST=();
  while(defined(my $token=$$self{gullet}->readXToken())){ # Done if we run out of tokens
    push(@LaTeXML::LIST, $self->invokeToken($token));
    my $depth  = scalar(@{$$self{boxing}});
    last if $initdepth > $depth; } # if we've closed the initial mode.
  Fatal("We've fallen off the end, somehow!?!?!\n Last token ".ToString($LaTeXML::CURRENT_TOKEN)
	." (Boxing depth was $initdepth, now $depth: Boxing generated by "
	.join(', ',map(ToString($_),@{$$self{boxing}})))
    if $initdepth < $depth;

  my $list = (scalar(@LaTeXML::LIST) == 1 ? $LaTeXML::LIST[0] 
	      : ($ismath ? LaTeXML::MathList->new(@LaTeXML::LIST) : LaTeXML::List->new(@LaTeXML::LIST)));
  $$self{gullet}->closeMouth;
  $list; }

our @forbidden_cc = (1,0,0,0, 0,0,1,0, 0,1,0,0, 0,0,0,1, 0,1);

# Invoke a token; 
# If it is a primitive or constructor, the definition will be invoked,
# possibly arguments will be parsed from the Gullet.
# Otherwise, the token is simply digested: turned into an appropriate box.
# Returns a list of boxes/whatsits.
sub invokeToken {
  my($self,$token)=@_;
  local $LaTeXML::CURRENT_TOKEN = $token;
  my $meaning = $STATE->lookupMeaning($token);
  if(! defined $meaning){		# Supposedly executable token, but no definition!
    my $cs = $token->getCSName;
    $STATE->noteStatus(undefined=>$cs);
    Error("$cs is not defined.");
    $STATE->installDefinition(LaTeXML::Constructor->new($token,undef,
			  "<ltx:ERROR type='undefined'>".$cs."</ltx:ERROR>")); #,mode=>'text');
    $self->invokeToken($token); }
  elsif($meaning->isaDefinition){
    my @boxes = $meaning->invoke($self);
    my @err = grep( (! ref $_) || (! $_->isaBox), @boxes);
    Fatal("Execution of ".ToString($token)." yielded non boxes: ".join(',',map(Stringify($_),@err))) if @err;
    $STATE->clearPrefixes unless $meaning->isPrefix; # Clear prefixes unless we just set one.
    @boxes; }
  elsif($meaning->isaToken) {
    my $cc = $meaning->getCatcode;
    $STATE->clearPrefixes; # prefixes shouldn't apply here.
    if(($cc == CC_SPACE) && ($STATE->lookupValue('IN_MATH') || $STATE->lookupValue('inPreamble') )){ 
      (); }
    elsif($cc == CC_COMMENT){
      LaTeXML::Comment->new($meaning->getString); }
    elsif($forbidden_cc[$cc]){
      Fatal("[Internal] ".Stringify($token)." should never reach Stomach!"); }
    elsif($STATE->lookupValue('IN_MATH')){
      my $string = $meaning->getString;
      LaTeXML::MathBox->new($string,$STATE->lookupValue('font')->specialize($string),
			    $$self{gullet}->getLocator,$meaning); }
    else {
      LaTeXML::Box->new($meaning->getString, $STATE->lookupValue('font'),
			$$self{gullet}->getLocator,$meaning); }}
  else {
    Fatal("[Internal] ".Stringify($meaning)." should never reach Stomach!"); }}

# Regurgitate: steal the previously digested boxes from the current level.
sub regurgitate {
  my($self)=@_;
  my @stuff = @LaTeXML::LIST;
  @LaTeXML::LIST=();
  @stuff; }

#**********************************************************************
# Maintaining State.
#**********************************************************************
# State changes that the Stomach needs to moderate and know about (?)

#======================================================================
# Dealing with TeX's bindings & grouping.
# Note that lookups happen more often than bgroup/egroup (which open/close frames).

sub pushStackFrame {
  my($self,$nobox)=@_;
  $STATE->pushFrame;
  $STATE->assignValue(beforeAfterGroup=>[],'local'); # ALWAYS bind this!
  $STATE->assignValue(afterGroup=>[],'local'); # ALWAYS bind this!
  push(@{$$self{boxing}},$LaTeXML::CURRENT_TOKEN) unless $nobox; # For begingroup/endgroup
}

sub popStackFrame {
  my($self,$nobox)=@_;
  if(my $beforeafter=$STATE->lookupValue('beforeAfterGroup')){
    push(@LaTeXML::LIST,map($_->beDigested($self), @$beforeafter)); }
  my $after = $STATE->lookupValue('afterGroup');
  $STATE->popFrame;
  pop(@{$$self{boxing}}) unless $nobox; # For begingroup/endgroup
  $$self{gullet}->unread(@$after) if $after;
}

#======================================================================
# Grouping pushes a new stack frame for binding definitions, etc.
#======================================================================

# if $nobox is true, inhibit incrementing the boxingLevel
sub bgroup {
  my($self)=@_;
  pushStackFrame($self,0);
  return; }

sub egroup {
  my($self)=@_;
  if($STATE->isValueBound('MODE',0)){ # Last stack frame was a mode switch!?!?!
    Fatal("Unbalanced \$ or \} while ending group for ".$LaTeXML::CURRENT_TOKEN->getCSName); }
  popStackFrame($self,0);
  return; }

sub begingroup {
  my($self)=@_;
  pushStackFrame($self,1);
  return; }

sub endgroup {
  my($self)=@_;
  if($STATE->isValueBound('MODE',0)){ # Last stack frame was a mode switch!?!?!
    Fatal("Unbalanced \$ or \} while ending group for ".$LaTeXML::CURRENT_TOKEN->getCSName); }
  popStackFrame($self,1);
  return; }

#======================================================================
# Mode (minimal so far; math vs text)
# Could (should?) be taken up by Stomach by building horizontal, vertical or math lists ?

sub beginMode {
  my($self,$mode)=@_;
  $self->pushStackFrame;	# Effectively bgroup
  my $prevmode =  $STATE->lookupValue('MODE');
  my $ismath = $mode=~/math$/;
  $STATE->assignValue(MODE=>$mode,'local');
  $STATE->assignValue(IN_MATH=>$ismath,'local');
  if($mode eq $prevmode){}
  elsif($ismath){
    # When entering math mode, we set the font to the default math font,
    # and save the text font for any embedded text.
    $STATE->assignValue(savedfont=>$STATE->lookupValue('font'),'local');
    $STATE->assignValue(font     =>$STATE->lookupValue('mathfont'),'local');
    $STATE->assignValue(mathstyle=>($mode =~ /^display/ ? 'display' : 'text'),'local'); }
  else {
    # When entering text mode, we should set the font to the text font in use before the math.
    $STATE->assignValue(font=>$STATE->lookupValue('savedfont'),'local'); }
  return; }

sub endMode {
  my($self,$mode)=@_;
  if(! $STATE->isValueBound('MODE',0)){ # Last stack frame was NOT a mode switch!?!?!
    Fatal("Unbalanced \$ or \} while ending mode $mode for ".$LaTeXML::CURRENT_TOKEN->getCSName); }
  elsif($STATE->lookupValue('MODE') ne $mode){
    Fatal("Can't end mode $mode: Was in mode ".$STATE->lookupValue('MODE')."!!"); }
  $self->popStackFrame;		# Effectively egroup.
 return; }

#**********************************************************************
1;

__END__

=pod 

=head1 NAME

C<LaTeXML::Stomach> -- digests tokens into boxes, lists, etc.

=head1 DESCRIPTION

C<LaTeXML::Stomach> digests tokens read from a L<LaTeXML::Gullet>
(they will have already been expanded).  

There are basically four cases when digesting a L<LaTeXML::Token>:

=over 4

=item A plain character

is simply converted to a L<LaTeXML::Box> (or L<LaTeXML::MathBox> in math mode),
recording the current L<LaTeXML::Font>.

=item A primitive

If a control sequence represents L<LaTeXML::Primitive>, the primitive is invoked, executing its
stored subroutine.  This is typically done for side effect (changing the state in the L<LaTeXML::State>),
although they may also contribute digested material.
As with macros, any arguments to the primitive are read from the L<LaTeXML::Gullet>.

=item Grouping (or environment bodies)

are collected into a L<LaTeXML::List> (or L<LaTeXML::MathList> in math mode).

=item Constructors

A special class of control sequence, called a L<LaTeXML::Constructor> produces a 
L<LaTeXML::Whatsit> which remembers the control sequence and arguments that
created it, and defines its own translation into C<XML> elements, attributes and data.
Arguments to a constructor are read from the gullet and also digested.

=back

=head2 Digestion

=over 4

=item C<< $list = $stomach->digestNextBody; >>

Return the digested L<LaTeXML::List> after reading and digesting a `body'
from the its Gullet.  The body extends until the current
level of boxing or environment is closed.  

=item C<< $list = $stomach->digest($tokens); >>

Return the L<LaTeXML::List> resuting from digesting the given tokens.
This is typically used to digest arguments to primitives or
constructors.

=item C<< @boxes = $stomach->invokeToken($token); >>

Invoke the given (expanded) token.  If it corresponds to a
Primitive or Constructor, the definition will be invoked,
reading any needed arguments fromt he current input source.
Otherwise, the token will be digested.
A List of Box's, Lists, Whatsit's is returned.

=item C<< @boxes = $stomach->regurgitate; >>

Removes and returns a list of the boxes already digested 
at the current level.  This peculiar beast is used
by things like \choose (which is a Primitive in TeX, but
a Constructor in LaTeXML).

=back

=head2 Grouping

=over 4

=item C<< $stomach->bgroup; >>

Begin a new level of binding by pushing a new stack frame,
and a new level of boxing the digested output.

=item C<< $stomach->egroup; >>

End a level of binding by popping the last stack frame,
undoing whatever bindings appeared there, and also
decrementing the level of boxing.

=item C<< $stomach->begingroup; >>

Begin a new level of binding by pushing a new stack frame.

=item C<< $stomach->endgroup; >>

End a level of binding by popping the last stack frame,
undoing whatever bindings appeared there.

=back

=head2 Modes

=over 4

=item C<< $stomach->beginMode($mode); >>

Begin processing in C<$mode>; one of 'text', 'display-math' or 'inline-math'.
This also begins a new level of grouping and switches to a font
appropriate for the mode.

=item C<< $stomach->endMode($mode); >>

End processing in C<$mode>; an error is signalled if C<$stomach> is not
currently in C<$mode>.  This also ends a level of grouping.

=back

=head1 AUTHOR

Bruce Miller <bruce.miller@nist.gov>

=head1 COPYRIGHT

Public domain software, produced as part of work done by the
United States Government & not subject to copyright in the US.

=cut
