#
# ToposToken Version 1.0

package ToposToken;

use strict;
use warnings;

use HTTP::Headers;
use HTTP::Request;
use LWP::MediaTypes;
use LWP::UserAgent;

my $TOPOS_URL = "https://topos.grid.sara.nl/4.1";

sub new {
  my $package = shift;

  my %options = @_;

  my $self = bless {
    pool       => undef,
    url        => undef,
    timeout    => undef,
    filename   => undef,
    content    => undef,
    lockurl    => undef,
  }, $package;

  if (exists $options{timeout}) {
    $self -> timeout ($options{timeout});
  }

  if (exists $options{filename}) {
    $self -> filename($options{filename});
  }

  if (exists $options{content}) {
    $self -> content($options{content});
  }

  if (exists $options{lockurl}) {
    $self -> lockurl($options{lockurl});
  }

  return $self;
}

# ------------------------------------------------------------------------
# getters / setters
# ------------------------------------------------------------------------

sub pool {
  my $self = shift;
  my $pool = shift;

  $self -> {'pool'} = $pool if defined $pool;
  return $self -> {'pool'};
}

sub url {
  my $self = shift;
  my $url  = shift;

  $self -> {'url'} = $url if defined $url;
  return $self -> {'url'};
}


sub timeout {
  my $self = shift;
  my $timeout = shift;

  if (defined $timeout) {
    $self -> {'timeout'} = $timeout;
  }
  return $self -> {'timeout'};
}

sub filename {
  my $self = shift;
  my $filename = shift;

  if (defined $filename) {
    $self -> {'filename'} = $filename;
  }
  return $self -> {'filename'};
}

sub content {
  my $self = shift;
  my $content = shift;

  if (defined $content) {
    $self -> {'content'} = $content;
  }
  return $self -> {'content'};
}

sub lockurl {
  my $self = shift;
  my $lockurl = shift;

  if (defined $lockurl) {
    $self -> {'lockurl'} = $lockurl;
  }
  return $self -> {'lockurl'};
}


sub is_file {
  my $self = shift;
  return defined $self -> {'filename'};
}

# ------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------

=head2 renew_lock

Renews the lock with a given timeout value in seconds, or if no timeout value
was specified, with same timeout value as the last timeout value.

=cut
sub renew_lock {
  my $self = shift;
  my $timeout = shift;

  $timeout = $self -> timeout ($timeout) unless defined $timeout;

  # prepare a http request 
  my $url  = $self -> lockurl;

  # add the timeout parameter
  $url .= "?timeout=$timeout";

  my $request = new HTTP::Request (GET => $url);

  my $response = $self -> pool -> {'user_agent'} -> request($request);

  if ($response -> is_error) {
    print(STDERR "*** error: could not renew token lock.\n");
  }
  return;
}
  

=head2 delete

Deletes the token from the pool.

=cut
sub delete {
  my $self = shift;
  my $url  = $self -> url;

  my $request = new HTTP::Request (DELETE => $url);

  my $response = $self -> pool -> {'user_agent'} -> request($request);

  if ($response -> is_error) {
    print(STDERR "*** error: could not delete token.\n");
  }
  return;
}

  
  
    
# package OK
1;

