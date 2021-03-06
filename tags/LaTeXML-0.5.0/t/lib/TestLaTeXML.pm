package TestLaTeXML;
use strict;
use base qw(Test::Builder Exporter);
use Test::More;
our @EXPORT = (qw(latexml_ok is_xmlcontent is_filecontent is_strings skip_all
		 latexml_tests),
	       @Test::More::EXPORT);

# Note that this is a singlet; the same Builder is shared.
my $Test=Test::Builder->new();

# Test the conversion of all *.tex files in the given directory (typically t/something)
# Skip any that have no corresponding *.xml file.
sub latexml_tests {
  my($directory)=@_;

  if(!opendir(DIR,$directory)){
    # Can't read directory? Fail (assumed single) test.
    $Test->expected_tests(1+$Test->expected_tests);
    do_fail($directory,"Couldn't read directory $directory:$!"); }
  else {
    local $Test::Builder::Level =  $Test::Builder::Level+1;
    my @tests = map("$directory/$_", grep(s/\.tex$//, readdir(DIR)));
    closedir(DIR);
    $Test->expected_tests(1+scalar(@tests)+$Test->expected_tests);
    eval { use_ok("LaTeXML"); }; # || skip_all("Couldn't load LaTeXML"); }
    foreach my $test (@tests){
      if(-f "$test.xml"){
	latexml_ok("$test.tex","$test.xml",$test); }
      else {
	$Test->skip("No file $test.xml"); }
    }}}


sub do_fail {
  my($name,$diag)=@_;
  { local $Test::Builder::Level =  $Test::Builder::Level+1;
    my $ok = $Test->ok(0,$name);
    $Test->diag($diag);
    return $ok; }}

sub skip_all {
  my($reason)=@_;
  $Test->skip_all($reason); }

# Would like to evolve a sensible XML comparison.
# This is a start...

# NOTE: This assumes you will have successfully loaded LaTeXML.
sub latexml_ok {
  my($texpath,$xmlpath,$name)=@_;
  my($latexml,$dom);

  eval{ $latexml = LaTeXML->new(preload=>[], searchpath=>[], includeComments=>0,
				verbosity=>-2); };
  return do_fail($name,"Couldn't instanciate LaTeXML: ".@!) unless $latexml;

  eval { $dom = $latexml->convertFile($texpath); };
  return do_fail($name,"Couldn't convert $texpath: ".@!) unless $dom;

  { local $Test::Builder::Level =  $Test::Builder::Level+1;
    is_xmlcontent($dom,$xmlpath,$name); }}


sub is_xmlcontent {
  my($xmldom,$path,$name)=@_;
  if(!defined $xmldom){
    do_fail($name,"The XML DOM was undefined for $name"); }
  else {
    { local $Test::Builder::Level =  $Test::Builder::Level+1;
      is_filecontent([split('\n',$xmldom->toString(1))],$path,$name); }}}


sub is_filecontent {
  my($strings,$path,$name)=@_;
  if(!open(IN,"<:utf8",$path)){
    do_fail($name,"Could not open $path"); }
  else {
    my @lines;
    { local $\=undef; 
      @lines = <IN>; }
    close(IN);
    { local $Test::Builder::Level =  $Test::Builder::Level+1;
      is_strings($strings,[@lines],$name); }}}

sub is_strings {
  my($strings1,$strings2,$name)=@_;
  my $max = $#$strings1 > $#$strings2 ? $#$strings1 : $#$strings2;
  my $ok = 1;
  for(my $i = 0; $i < $max; $i++){
    my $string1 = $$strings1[$i];
    my $string2 = $$strings2[$i];
    if(defined $string1){
      chomp($string1); }
    else{
      $ok = 0; $string1 = ""; }
    if(defined $string2){
      chomp($string2); }
    else{
      $ok = 0; $string2 = ""; }
    if(!$ok || ($string1 ne $string2)){
      return do_fail($name,
		     "Difference at line ".($i+1)." for $name\n"
		     ."      got : '$string1'\n"
		     ." expected : '$string2'\n"); }}
  $Test->ok(1, $name); }

1;
