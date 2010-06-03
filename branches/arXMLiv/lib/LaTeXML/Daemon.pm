# /=====================================================================\ #
# |  LaTeXML::Daemon                                                    | #
# | Extends the LaTeXML object with daemon methods                      | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Bruce Miller <bruce.miller@nist.gov>                        #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package LaTeXML::Daemon;
use strict;
use LaTeXML::Global;
use LaTeXML::Error;
use LaTeXML::State;
use LaTeXML::Stomach;
use LaTeXML::Document;
use LaTeXML::Model;
use LaTeXML::Object;
use LaTeXML::MathParser;
use LaTeXML::Util::Pathname;
use LaTeXML::Bib;
use LWP::Simple;
use Encode;
our @ISA = (qw(LaTeXML));

#**********************************************************************

sub digestFileDaemonized {
  my($self,$file,$mode)=@_;
  $file =~ s/\.tex$//;
  $self->withState(sub {
     my($state)=@_;
     NoteBegin("Digesting $file");
     #We only need to initialize the state at the start of the daemon!
     #$self->initializeState('TeX.pool', @{$$self{preload} || []});
     my $pathname = pathname_find($file,types=>['tex','']);
     Fatal(":missing_file:$file Cannot find TeX file $file") unless $pathname;
     $state->assignValue(SOURCEFILE=>$pathname,'global');
     my($dir,$name,$ext)=pathname_split($pathname);
     $state->assignValue(SOURCEBASE=>$name,'global');
     $state->pushValue(SEARCHPATHS=>$dir);
     $state->installDefinition(LaTeXML::Expandable->new(T_CS('\jobname'),undef,
							Tokens(Explode($name))));
    #Note that we first open the \end and then the \begin
    #Since we have a stack and not a queue.
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       #End {document}
       my $edoc = '\\end{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($edoc),0);
     }
     #Digest input
     $state->getStomach->getGullet->input($pathname);
     #Wrap LaTeX fragments in a {document} environment
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       my $bdoc = '\\begin{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($bdoc),0);
     }

     my $list = $self->finishDigestion;
     $state->popValue('SEARCHPATHS');
     NoteEnd("Digesting $file");
     $list; });
}

sub digestBibTeXFileDaemonized {
  my($self,$file,$mode)=@_;
  $file =~ s/\.bib$//;
  $self->withState(sub {
     my($state)=@_;
     NoteBegin("Digesting bibliography $file");
     # NOTE: This is set up to do BibTeX for LaTeX (not other flavors, if any)
     #We only need to initialize the state at the start of the daemon!
     #$self->initializeState('TeX.pool','LaTeX.pool', 'BibTeX.pool', @{$$self{preload} || []});
     my $pathname = pathname_find($file,types=>['bib','']);
     Fatal(":missing_file:$file Cannot find TeX file $file") unless $pathname;
     my $bib = LaTeXML::Bib->newFromFile($file);
     my($dir,$name,$ext)=pathname_split($pathname);
     $state->pushValue(SEARCHPATHS=>$dir);
     $state->installDefinition(LaTeXML::Expandable->new(T_CS('\jobname'),undef,
							Tokens(Explode($name))));
     my $tex = $bib->toTeX;
     $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($tex),0);
     my $line = $self->finishDigestion;
     $state->popValue('SEARCHPATHS');
     NoteEnd("Digesting bibliography $file");
     $line; });
}

sub digestStringDaemonized {
  my($self,$string,$mode,$sourcebase)=@_;
  $self->withState(sub {
     my($state)=@_;
     NoteBegin("Digesting string");
     #We only need to initialize the state at the start of the daemon!
     #$self->initializeState('TeX.pool', @{$$self{preload} || []});
     $state->assignValue(SOURCEBASE=>$sourcebase,'global') if $sourcebase;
     #Note that we first open the \end and then the \begin
     #Since we have a stack and not a queue.
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       #End {document}
       my $edoc = '\\end{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($edoc),0);
     }
     #Digest input
     $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($string),0);
     #Wrap LaTeX fragments in a {document} environment
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       my $bdoc = '\\begin{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($bdoc),0);
     }

     my $line = $self->finishDigestion;
     NoteEnd("Digesting string");
     $line; });
}

sub digestURLDaemonized {
  my($self,$url,$mode)=@_;
  #Web-based
  die "Can't access source URL: $url\n" unless (head($url));
  my $content = get($url);
  die "Failed to fetch source URL: $url\n"  unless ($content);
  $self->withState(sub {
     my($state)=@_;
     NoteBegin("Digesting URL: $url");
     #We only need to initialize the state at the start of the daemon!
     #$self->initializeState('TeX.pool', @{$$self{preload} || []});
     $state->assignValue(SOURCEBASE=>$url,'global');
     $state->assignValue(SOURCEFILE=>$url,'global');
     #Note that we first open the \end and then the \begin
     #Since we have a stack and not a queue.
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       #End {document}
       my $edoc = '\\end{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($edoc),0);
     }
     #Digest input
     $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($content),0);
     #Wrap LaTeX fragments in a {document} environment
     if ($mode eq "fragment" && $state->lookupDefinition(T_CS("\\begin{document}"))) {
       my $bdoc = '\\begin{document}';
       $state->getStomach->getGullet->openMouth(LaTeXML::Mouth->new($bdoc),0);
     }
     
     my $line = $self->finishDigestion;
     NoteEnd("Digesting URL: $url");
     $line; });
}