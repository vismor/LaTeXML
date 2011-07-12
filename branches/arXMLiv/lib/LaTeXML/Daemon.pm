# /=====================================================================\ #
# |  LaTeXML::Daemon                                                    | #
# | Wrapper for LaTeXML processing with daemon-ish methods              | #
# |=====================================================================| #
# | Part of LaTeXML:                                                    | #
# |  Public domain software, produced as part of work done by the       | #
# |  United States Government & not subject to copyright in the US.     | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://dlmf.nist.gov/LaTeXML/                              (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package LaTeXML::Daemon;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use LaTeXML;
use LaTeXML::Util::Pathname;
use LaTeXML::Util::WWW;
use LaTeXML::Util::Extras;
use LaTeXML::Post;
use LaTeXML::Post::Scan;
use Carp;
use IO::Scalar;
use Data::Compare;
use feature "switch";

#**********************************************************************
our @IGNORABLE = qw(identity input_counter input_limit profile);

sub new {
  my ($class,%opts) = @_;
  binmode(STDERR,":utf8");
  prepare_options(undef,\%opts);
  bless {defaults=>\%opts,opts=>undef,ready=>0,
         latexml=>undef, digested_preamble=>undef}, $class;
}

sub prepare_session {
  my ($self,$opts) = @_;
  #0. Make sure all default keys are present, via bootstrapping with the defaults:
  foreach (keys %{$self->{defaults}}) {
    $opts->{$_} = $self->{defaults}->{$_} unless exists $opts->{$_};
  }
  $self->prepare_options($opts);
  #1. Check if there is some change from the current situation:
  my $nothingtodo=1 if Compare($opts, $self->{opts}, { ignore_hash_keys => [@IGNORABLE] });
  #1.1. If no, nothing to do
  unless ($nothingtodo) {
    #1.2. If yes, reset opts:
    undef $self->{opts};
    $self->{opts} = $opts;
    $self->{opts} = $self->{defaults} if (! keys %{$self->{opts}});
    $self->prepare_options($self->{opts});
  }
  # ... and initialize a session:
  $self->initialize_session unless ($nothingtodo && $self->{ready});
  return;
}

sub prepare_options {
  my ($self,$opts) = @_;
  $opts->{verbosity} = 0 unless defined $opts->{verbosity};
  $opts->{preload} = [] unless defined $opts->{preload};
  $opts->{paths} = ['.'] unless defined $opts->{paths};
  @{$opts->{paths}} = map {pathname_canonical($_)} @{$opts->{paths}};
  if ($opts->{post}) {
    # Fall back to default post processors if no preferences:
    %{$opts->{procs_post}}=%{$self->{defaults}->{procs_post}} if (defined $self && (! keys %{$opts->{procs_post}}));
    # Fall back to pmml as default
    $opts->{procs_post}->{'pmml'}=1 if (! keys %{$opts->{procs_post}});
  }
  # Any post switch implies post:
  $opts->{post}=1 if (keys %{$opts->{procs_post}});
  $opts->{parallelmath}=0 unless (keys %{$opts->{procs_post}} > 1);
}

sub initialize_session {
  my ($self) = @_;
  # Prepare LaTeXML object
  my $latexml= new_latexml($self->{opts});
  # Demand errorless initialization
  my $init_status = $latexml->getStatusMessage;
  croak $init_status unless ($init_status !~ /error/i);
  # Load preamble:
  my $digested_preamble = load_preamble($self->{opts},$latexml,$self->{digested_preamble});
  # Save in object:
  $self->{latexml} = $latexml;
  $self->{digested_preamble} = $digested_preamble;
  $self->{ready}=1;
}

sub convert {
  my ($self,$source) = @_;
  # Tie STDERR to log:
  my $log=q{}; my $status=q{};
  open(LOG,">",\$log) or croak "Can't redirect STDERR to log! Dying...";
  *ERRORIG=*STDERR;
  *STDERR = *LOG;

  # Initialize session if needed:
  $self->initialize_session unless $self->{ready};

  # Inform of identity, increase conversion counter
  my $opts = $self->{opts};
  print STDERR $opts->{identity}."\n" if $opts->{verbosity} >= 0;
  $opts->{input_counter}++;

  # Prepare content and determine source type
  my $content = $self->prepare_content($source);

  # Prepare daemon frame
  my $latexml = $self->{latexml};
  $latexml->withState(sub {
                        my($state)=@_; # Sandbox state
                        # Save preamble information for further use:
                        $state->assignValue('_preamble_loaded',$opts->{preamble},'global');
                        $state->assignValue('_authlist',$opts->{authlist},'global');
                        $state->pushDaemonFrame; });

  # First read and digest whatever we're given.
  my ($digested,$dom,$serialized);
  # Digest source:
  eval {
    if ($opts->{source_type} eq 'url') {
      $digested = $latexml->digestString($content,preamble=>$opts->{'fragment_preamble'},
                                         postamble=>$opts->{'fragment_postamble'},source=>$source,noinitialize=>1);
    } elsif ($opts->{source_type} eq 'file') {
      if ($opts->{type} eq 'bibtex') {
        # TODO: Do we want URL support here?
        $digested = $latexml->digestBibTeXFile($content,preamble=>$opts->{'fragment_preamble'},
                                               postamble=>$opts->{'fragment_postamble'},noinitialize=>1);
      } else {
        $digested = $latexml->digestFile($content,preamble=>$opts->{'fragment_preamble'},
                                         postamble=>$opts->{'fragment_postamble'},noinitialize=>1);
      }}
    elsif ($opts->{source_type} eq 'string') {
      $digested = $latexml->digestString($content,preamble=>$opts->{'fragment_preamble'},
                                         postamble=>$opts->{'fragment_postamble'},noinitialize=>1);
    }
    
    # Now, convert to DOM and output, if desired.
    if ($digested) {
      $digested = LaTeXML::List->new($self->{digested_preamble},$digested)
        if defined $self->{digested_preamble};
      local $LaTeXML::Global::STATE = $$latexml{state};
      if ($opts->{format} eq 'tex') {
        $serialized = LaTeXML::Global::UnTeX($digested);
      } elsif ($opts->{format} eq 'box') {
        $serialized = $digested->toString;
      } else {
        $dom = $latexml->convertDocument($digested);
        $serialized = $dom->toString(1) unless $opts->{post};
      }}
    1;
  } or do {#Fatal occured!
    print STDERR "$@\n";
    print STDERR "\nConversion complete: ".$latexml->getStatusMessage.".\n";
    # Close and restore STDERR to original condition.
    close LOG;
    *STDERR=*ERRORIG;
    $self->{ready}=0; return {result=>undef,log=>$log,status=>$latexml->getStatusMessage};
  };

  print STDERR "\nConversion complete: ".$latexml->getStatusMessage.".\n";
  $status = $latexml->getStatusMessage;
  # End daemon run, by popping frame:
  $latexml->withState(sub {
                        my($state)=@_; # Remove current state frame
                        $state->popDaemonFrame;
                        $$state{status} = {};
                      });

  my $result = $dom;
  $result = $self->convert_post($dom) if ($opts->{post} && $dom && (!$opts->{noparse}));

  # Close and restore STDERR to original condition.
  close LOG;
  *STDERR=*ERRORIG;
  delete $opts->{source_type};
  my $return = {result=>$result,log=>$log,status=>$status};
}

sub convert_post {
  my ($self,$dom) = @_;
  my $opts = $self->{opts};
  my ($style,$parallel,$proctypes,$format,$verbosity,$defaultcss,$embed) = 
    map {$opts->{$_}} qw(stylesheet parallelmath procs_post format verbosity defaultcss embed);
  $verbosity = $verbosity||0;
  my %PostOPS = (verbosity=>$verbosity,siteDirectory=>".");
  #Postprocess
  #Default is XHTML, XML otherwise (TODO: Expand)
  $format="xml" if ($style);
  $format="xhtml" unless (defined $format);
  if (!$style) {
    given ($format) {
      when ("xhtml") {$style = "LaTeXML-xhtml.xsl";}
      when ("html") {$style = "LaTeXML-html.xsl";}
      when ("html5") {$style = "LaTeXML-html5.xsl";}
      when ("xml") {undef $style;}
      default {Error("Unrecognized target format: $format");}
    }}
  my @css=();
  unshift (@css,"core.css") if ($defaultcss);
  $parallel = $parallel||0;
  my $doc;
  eval {
    $doc = LaTeXML::Post::Document->new($dom,nocache=>1);
    1;}
    or do {                     #Fatal occured!
      #Since this is postprocessing, we don't need to do anything
      #   just avoid crashing... and exit
      undef $doc;
      print STDERR "FATAL: Post-processor crashed! $@\n";
      return undef;
    };
  require LaTeXML::Post::MathML;
  require LaTeXML::Post::OpenMath;
  require LaTeXML::Post::PurgeXMath;
  my @mprocs=();

  push (@mprocs, LaTeXML::Post::MathML::Presentation->new(%PostOPS)) if $proctypes->{'pmml'};
  push (@mprocs, LaTeXML::Post::MathML::Content->new(%PostOPS)) if $proctypes->{'cmml'};
  push (@mprocs, LaTeXML::Post::OpenMath->new(%PostOPS)) if $proctypes->{'openmath'};
  my $main = shift(@mprocs);
  $main->setParallel(@mprocs) if $parallel;
  $main->keepTeX if ($$proctypes{'keepTeX'} && $parallel);
  my @procs=();
  push(@procs,$main);
  push(@procs,@mprocs) unless $parallel;
  push(@procs, LaTeXML::Post::PurgeXMath->new(%PostOPS)) unless $$proctypes{'keepXMath'};
  require LaTeXML::Post::XSLT;
  my @csspaths=();
#  if (@css) {
#    foreach my $css (@css) {
#      $css .= '.css' unless $css =~ /\.css$/;
#      # Dance, if dest is current dir, we'll find the old css before the new one!
#      my @csssources = map {pathname_canonical($_)}
#                            pathname_findall($css,types=>['css'],
#                                            (),
#                                            installation_subdir=>'style');
#      my $csspath = pathname_absolute($css,pathname_directory('.'));
#      while (@csssources && ($csssources[0] eq $csspath)) {
#        shift(@csssources);
#      }
#      my $csssource = shift(@csssources);
#      pathname_copy($csssource,$csspath)  if $csssource && -f $csssource;
#      push(@csspaths,$csspath);
#    }}

  push(@procs,LaTeXML::Post::XSLT->new(stylesheet=>$style,
					 parameters=>{number_sections
						      =>("true()"),
                                                      (@csspaths ? (CSS=>[@csspaths]):()),},
                                       %PostOPS)) if $style;
  my $postdoc;
  eval { ($postdoc) = LaTeXML::Post::ProcessChain($doc,@procs); 1;}
  or do {                     #Fatal occured!
    #Since this is postprocessing, we don't need to do anything
    #   just avoid crashing... and exit
    print STDERR "FATAL: Post-processor crashed! $@\n";
    return;
  };

  return $postdoc;
}

########## Helper routines: ############

sub new_latexml {
  my $opts = shift;
  my $latexml = LaTeXML->new(preload=>[@{$opts->{preload}}], searchpaths=>[@{$opts->{paths}}],
                          graphicspaths=>['.'],
			  verbosity=>$opts->{verbosity}, strict=>$opts->{strict},
			  includeComments=>$opts->{comments},inputencoding=>$opts->{inputencoding},
			  includeStyles=>$opts->{includestyles},
			  documentid=>$opts->{documentid},
			  nomathparse=>$opts->{noparse});
  if(my @baddirs = grep {! -d $_} @{$opts->{paths}}){
    warn $opts->{identity}.": these path directories do not exist: ".join(', ',@baddirs)."\n"; }

  $latexml->withState(sub {
                        my($state)=@_;
                        $latexml->initializeState('TeX.pool', @{$$latexml{preload} || []});
                      });
  return $latexml;
}

sub load_preamble {
  my ($opts,$latexml,$original) = @_;
  my $digested = undef;
  # Preload the preamble if any (and not loaded)
  if ($opts->{preamble} && ($opts->{preamble_loaded} ne $opts->{preamble})) {
    #TODO: It is difficult to digest 2 files via LaTeXML into 1 XML output right now...
    my $response=auth_get($opts->{preamble},$opts->{authlist});
    if ($response->is_success) {
      my $content = $response->content;
      $digested = $latexml->digestString($content,source=>$opts->{preamble},noinitialize=>1);
    } else {
      if (!$opts->{local}) { carp "File preamble allowed only when 'local' is enabled!"; return; }
      $digested = $latexml->digestFile($opts->{preamble},noinitialize=>1);
    }
    $opts->{preamble_loaded} = $opts->{preamble};
  }
  $digested = $original unless defined $digested;
  return $digested;
}

sub prepare_content {
  my ($self,$source)=@_;
  $source=~s/\n$//g; # Eliminate trailing new lines

  my $opts=$self->{opts};
  given ($opts->{source_type}) {
    when ("string") {return $source;}
    when ("file") { if ($opts->{local}) {
                    my $file = pathname_find($source,types=>['tex',q{}]);
                    $file = pathname_canonical($file) if $file;
                    #Recognize bibtex case
                    $opts->{type} = 'bibtex' if ($opts->{type} eq 'auto') && ($file =~ /\.bib$/);
                    return $file; }
                  else {print STDERR "File input only allowed when 'local' is enabled,"
                                    ."falling back to string input..";
                        $opts->{source_type}="string"; return $source; }}
    when ("url") {  my $response = auth_get($source,$opts->{authlist});
                  if ($response->is_success) {return $response->content;} else {
                  print STDERR "TODO: Flag a retrieval error and do something smart?"; return undef;}}
    default { # Guess the input type:
      my @source_lines = split(/\n/,$source);
      if (scalar(@source_lines)>1) {$opts->{source_type}="string"; return $source; }
      if ($opts->{local}) {
        my $file = pathname_find($source,types=>['tex',q{}]);
        $file = pathname_canonical($file) if $file;
        #Recognize bibtex case
        $opts->{type} = 'bibtex' if ($opts->{type} eq 'auto') && ($file =~ /\.bib$/);
        if ($file) {$opts->{source_type}="file"; return $file; }
      }
      my $response = auth_get($source,$opts->{authlist});
      if ($response->is_success) {$opts->{source_type}="url"; return $response->content; }
      $opts->{source_type}="string"; return $source;
    }
  }
}

1;

__END__

=pod 

=head1 NAME

C<LaTeXML::Daemon> - Daemon object and API for LaTeXML and LaTeXMLPost conversion.

=head1 SYNOPSIS

    use LaTeXML::Daemon;
    my $daemon = LaTeXML::Daemon->new(%options);
    $daemon->setOptions(%opts);
    my ($result,$status,$log) = $daemon->convert($tex);

=head1 DESCRIPTION

A Daemon object represents a converter instance and can convert files on demand, until dismissed.

=head2 METHODS

=over 4

=item C<< my $daemon = LaTeXML::Daemon->new(%options); >>

=item C<< $daemon->setOptions(%opts);  >>

=item C<< my ($result,$status,$log) = $daemon->convert($tex); >>

Converts $tex into $result and supplies detailed information of the conversion log and status.

=back

=head2 CUSTOMIZATION OPTIONS

 Options: (key=>value pairs)
 preload => [modules]   optional modules to be loaded
 includestyles          allows latexml to load raw *.sty file;
                        by default it avoids this.
 preamble => [files]    loads tex files containing document frontmatter.
 postamble => [files] loads texs file containing document backmatter. (TODO)

 paths => [dir]         paths searched for files,
                        modules, etc; 
 log => file            specifies log file, reuqires 'local' default: STDERR
 TODO? --documentid=id  assign an id to the document root.
 verbosity => level     verbosity of reporting, 0 or negative for silent, 
                        positive for increasing detail
 strict                 makes latexml less forgiving of errors
 type => bibtex         processes the file as a BibTeX bibliography.
 format => box|xml|tex  output format (Boxes, XML document or TeX document)
 noparse                suppresses parsing math (default: off)
 post                   requests a followup post-processing
 embed                  requests an embeddable XHTML div (= document body)
                        (requires: 'post')
 stylesheet => name     specifies a stylesheet, to be used by the post-processor.
 css => [cssfiles]      css stylesheets to html/xhtml
 nodefaultcss           disables the default css stylesheet
 post_procs->{pmml}     converts math to Presentation MathML
                        (default for xhtml format)
 post_procs->{cmml}     converts math to Content MathML
 post_procs->{openmath} converts math to OpenMath 
 parallelmath           requests parallel math markup for MathML
                        (off by default)
 post_procs->{keepTeX}  keeps the TeX source of a formula as a MathML
                        annotation element (requires 'parallelmath' : TODO really?)
 post_procs->{keepXMath} keeps the XMath of a formula as a MathML
                         annotation-xml element (requires 'parallelmath' : TODO really?)
 nocomments              omit comments from the output
 inputencoding => enc    specify the input encoding.
 debug => package        enables debugging output for the named
                         package

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

Public domain software, produced as part of work done by the
United States Government & not subject to copyright in the US.

=cut
