package TestDaemon;
use strict;
use base qw(Test::Builder Exporter);
use Test::More;

our @EXPORT = (qw(daemon_tests daemon_ok),
	       @Test::More::EXPORT);

# Note that this is a singlet; the same Builder is shared.
our $Test=Test::Builder->new();

# Test the invocations of all *.opt files in the given directory (typically t/something)
# Skip any that have no corresponding *.xml and *.log files.
sub daemon_tests {
  my($directory)=@_;

  if(!opendir(DIR,$directory)){
    # Can't read directory? Fail (assumed single) test.
    $Test->expected_tests(1+$Test->expected_tests);
    do_fail($directory,"Couldn't read directory $directory:$!"); }
  else {
    local $Test::Builder::Level =  $Test::Builder::Level+1;
    my @tests = map("$directory/$_", grep(s/\.opt$//, sort readdir(DIR)));
    closedir(DIR);
    $Test->expected_tests(3*scalar(@tests)+$Test->expected_tests);

    foreach my $test (@tests){
      if(-f "$test.xml" && -f "$test.log"){
	daemon_ok($test,$directory); }
      else {
	$Test->skip("Missing $test.xml and/or $test.log"); }
    }
  }
}


sub daemon_ok {
  my($base,$dir)=@_;
  my $localname = $base;
  $localname =~ s/$dir\///;
  my $opts = read_options("$base.opt");
  my $invocation = "killall latexmls; cd $dir; latexmlc --destination=$localname.test.xml --log=/dev/null --local --noforce_ids ";
  foreach (keys %$opts) {
    $invocation.= "--".$_.($opts->{$_} ? ("='".$opts->{$_}."' ") : (' '));
  }
  $invocation .= " 2>$localname.test.log; cd -";
  print STDERR "\n$invocation \n";
  is(system($invocation),0,"Progress: processed $localname...\n");
  { local $Test::Builder::Level =  $Test::Builder::Level+1;
    is_filecontent("$base.xml","$base.test.xml",$base);
    is_filecontent("$base.log","$base.test.log",$base);
  }
system("rm $base.test.xml $base.test.log");
}

sub read_options {
  my $opts = {};
  open (OPT,"<",shift);
  while (<OPT>) {
    chomp;
    /(\S+)\s*=\s*(.*)/;
    my ($key,$value) = ($1,$2);
    $opts->{$key} = $value||'';
    $opts->{$key} =~ s/\s+$//; #remove trailing spaces
  }
  close OPT;
  $opts;
}

sub get_filecontent {
  my ($path,$name) = @_;
  my @lines;
  if(!open(IN,"<",$path)){
    do_fail($name,"Could not open $path"); }
  else {
    { local $\=undef; 
      @lines = <IN>; }
    close(IN);
  }
  \@lines;
}

sub is_filecontent {
  my($path1,$path2,$name)=@_;
  my $content1 = get_filecontent($path1,$name);
  my $content2 = get_filecontent($path2,$name);
  { local $Test::Builder::Level =  $Test::Builder::Level+1;
    is_strings($content1,$content2,$name); }}


sub is_strings {
  my($strings1,$strings2,$name)=@_;
  my $max = $#$strings1 > $#$strings2 ? $#$strings1 : $#$strings2;
  my $ok = 1;
  for(my $i = 0; $i <= $max; $i++){
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


sub do_fail {
  my($name,$diag)=@_;
  { local $Test::Builder::Level =  $Test::Builder::Level+1;
    my $ok = $Test->ok(0,$name);
    $Test->diag($diag);
    return $ok; }}


# Tier 1.3: Math setups with embedding variations
# Tier 1.4: Math setups with force_id variations

# Tier 1.5: 


# Tier 2: Preloads and preambles

# Tier 3: Autoflush and Timeouts

# Tier 4: Ports and local conversion

# Tier 5: Defaults and multi-job daemon processing


# 1. We need to test daemon in fragment mode with fragment tests, math mode with math tests and standard mode with standard tests. Essentially, this is all about having the right preambles.

# 2. We need to benchmark consecutive runs, to make sure the first run is slowest and the rest (3?5?) are not initializing.

# 2.1. Set a --autoflush to 2 , send 3 conversions and make sure the process pid's differ.

# 2.2. Make sure an infinite macro times out (set --timeout=3 for fast test)
# 2.3. Check if the server can be set up on all default ports.

# 3. Exhaustively test all possible option combinations - we need triples of option vector with a test case and XML result, or some sane setup of this nature.

# 4. Moreover, we should test the option logic by comparing input-output option hashes (again, exhaustively!)

# 5. We need to compare the final document, log and summary produced.



1;