#!/usr/bin/perl

use strict;
use warnings;

use ToposPool;

sub print_usage;

my $topos_cmd = shift @ARGV;

unless ($topos_cmd) {
  print_usage;
  exit(0);
}


if ($topos_cmd eq 'new_pool') {
  my $pool = new ToposPool;
  print($pool -> name, "\n");
}
elsif ($topos_cmd eq 'upload_file') {
  my ($pool_name,
      $file_name) = @ARGV;

  unless (defined $file_name && -f $file_name) {
    print(STDERR "*** error: upload_file requires a pool name and a " .
                 "file name.\n");
    print_usage();
    exit(1);
  }
  my $pool = ToposPool -> new($pool_name);

  $pool -> upload_file_as_token ($file_name);

}
elsif ($topos_cmd eq 'delete_pool') {
  my ($pool_name) = @ARGV;
  my $pool = ToposPool -> new($pool_name);
  $pool -> delete;
}
elsif ($topos_cmd eq 'next_token') {
  my ($pool_name) = @ARGV;

  my $pool = ToposPool -> new($pool_name);

  my $token = $pool -> next_token();

  exit unless defined $token;

  if ($token -> is_file) {
    print($token -> filename, "\n");
  }
  else {
    print($token -> content);
  }
}
elsif ($topos_cmd eq 'next_token_delete') {
  my ($pool_name) = @ARGV;

  my $pool = ToposPool -> new($pool_name);

  my $token = $pool -> next_token();

  exit unless defined $token;

  if ($token -> is_file) {
    print($token -> filename, "\n");
  }
  else {
    print($token -> content);
  }

  $token -> delete;
} 
else {
  print(STDERR "*** error: unrecognized Topos command '$topos_cmd'\n\n");
  print_usage();
}

exit;


sub print_usage {
  print("Usage:\n",
        "  ./topos.pl <cmd> ... \n\n",
        "where cmd is one of:\n",
        "  new_pool              - creates a new unique pool\n",
        "  upload_file           - uploads a file as a new token\n");
}


