# vim: set sw=2 ts=2 expandtab :
#
# ToposPool Version 1.2
#
# Version history:
#
#   1.2          Die in case a new pool name cannot be determined
#                  (contributed by John van Dam)
#   1.1          Added tokens_as_text and token_list functions
#   1.0          First released version
#
package ToposPool;

use strict;
use warnings;

use ToposToken;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common ('GET', 'POST', 'PUT');
use LWP::MediaTypes;
use LWP::UserAgent;

my $TOPOS_URL = "https://topos.grid.sara.nl/4.1";


sub new {
  my $package = shift;
  my $name    = shift;

  my $self = bless {}, $package;

  $self -> {'user_agent'} = new LWP::UserAgent();

  # set the agent name
  $self -> {'user_agent'} -> agent ('PerlTopos/1.2');

  if (defined $name) {
    # open a pool with a given name
    $self -> {'name'} = $name;
  }
  else {
    # create a new pool with a unique name
    # get the Topos pool url
    my $response = $self -> {'user_agent'} -> get("${TOPOS_URL}/newPool",
      "Accept" => "text/plain");
     
    if ( $response -> is_success ) {

      # the Topos server redirects to the url of the new pool; get this url
      my $url = $response -> base;

      # get the name by taking all word characters before the last
      # trailing slash (if present)
      if ($url =~ m/(\w+)\/?$/) {
        $self -> {'name'} = $1;
      }
      else {
        die("Unable to retrieve a Topos pool name from the request; " .
            "check the connection.");
      }
    }
  }
  return $self;
}

sub tokens_as_text {
  my $self = shift;
  my $user_agent = $self -> {'user_agent'};
  my $pool_name  = $self -> {'name'};
  
  my $response = $self -> {'user_agent'} ->
    get("${TOPOS_URL}/pools/$pool_name/tokens/",
        "Accept" => "text/plain");
     
  if ( $response -> is_success ) {
    my $content = $response -> content;
    # remove \r's
    $content =~ s/\r//g;
    return $content;
  }
  else {
    return;
  }
}

sub token_list {
  my $self = shift;
  my $content = $self -> tokens_as_text();
  my @lines = split(/\n/, $content);

  my @tokens;

  # skip the header line
  for my $line (@lines [1 .. $#lines]) {
    my ($token) = split(/\t/, $line);
    push (@tokens, $token);
  }
  return @tokens;
}


sub load {
  my $package = shift;
  my $file_name = shift;

  unless (defined $file_name) {
    $file_name = "pool_id.txt";
  }

  open(POOL, "<$file_name") or die ("cannot open pool file '$file_name'");
  my $pool_id = <POOL>;
  close(POOL);

  chomp($pool_id);
  return $package -> new ($pool_id);
}


sub save {
  my $self = shift;
  my $file_name = shift;

  unless (defined $file_name) {
    $file_name = "pool_id.txt";
  }

  open(POOL, ">$file_name") or die ("cannot open pool file '$file_name'");
  printf(POOL "%s\n", $self -> {'name'});
  close(POOL);
}
  

# delete the token pool
sub delete {
  my $self = shift;  
  my $url  = $self -> url . "/tokens/";
  my $request = new HTTP::Request (DELETE => $url);

  my $response = $self -> {'user_agent'} -> request($request);

  if ($response -> is_error) {
    print(STDERR "*** error: could not delete pool.\n");
  }
  return;
}

# Create a simple text token
sub create_token {
  my $self = shift;

  # content of the token
  my $token = shift;

  # the url for the next token    
  my $next_token_url = $self -> url . "/nextToken";

  my $request = HTTP::Request->new(PUT => $next_token_url);

  # add the payload
  $request -> content($token);

  # payload is text
  $request -> header('Content-Type'    => 'text/plain');

  $request -> header('Accept'          => 'text/plain');

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    printf(STDERR "*** error while posting '$token'\n");
    return 0;
  }
  else {
    return 1;
  }
}

# Create multiple text tokens from a file
sub create_tokens_from_file {
  my $self = shift;

  # file containing the tokens 
  my $filename = shift;

  # verify that the file exists and load the contents
  unless (-f $filename && open(TOKENS, "<$filename") ) {
    print(STDERR "*** error: file '$filename' does not exist or cannot be " .
                 "opened.\n");
    exit(1);
  }
  
  my @tokens;

  while(my $line = <TOKENS>) {
    chomp $line;
    next if $line =~ m/^$/; # skip empty lines
    push (@tokens, "$line\n");
  }
  close(TOKENS);

  # concatenate all tokens into one string, which will be the payload
  my $content = join("", @tokens);

  # the url for the next token    
  my $pool_tokens_url = $self -> url . "/tokens/";

  my $request = HTTP::Request->new(POST => $pool_tokens_url);

  # add the payload
  $request -> content($content);

  # payload is text
  $request -> header('Content-Type'    => 'text/plain');

  $request -> header('Accept'          => 'text/plain');

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    printf(STDERR "*** error while posting tokens from '$filename'\n");
    return 0;
  }
  else {
    return 1;
  }
}

# Upload a file as a new token
sub upload_file_as_token {
  my $self = shift;

  # name of the file to be uploaded
  my $file_name = shift;

  unless (-f $file_name) {
    printf(STDERR "*** error: file '$file_name' does not exist.\n");
    exit(1);
  }

  # guess the media type from the file
  my $media_type = LWP::MediaTypes::guess_media_type($file_name);

  # print("Guessed content-type: $media_type\n");

  # the url for the next token    
  my $next_token_url = $self -> url . "/nextToken";


  # create a new http request object, initializing it with the
  # up (upload) command for a new file token
  my $request =
    HTTP::Request->new(PUT => $next_token_url);

  # set the headers
  $request -> header('Content-Type'        => $media_type);
  $request -> header('Content-Disposition' => 
                        "attachment; filename=\"$file_name\"");

  $request -> header('Accept'              => 'text/plain');

  # add the payload
  $request -> content(slurp($file_name));

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    printf(STDERR "*** error while posting '$file_name'\n");
  }
}

sub next_token {
  my $self = shift;

  # if a timeout is specified, the token will be locked for the
  # given timeout
  my $timeout = shift;

  # the url for the next token    
  my $next_token_url = $self -> url . "/nextToken";

  # if the timeout was specified and valid (a number), set the timout
  # for the lock of this token
  if (defined $timeout && $timeout =~ m/^\d+$/) {
    $next_token_url .= "?timeout=$timeout";
  }
  else {
    # no timeout or invalid timeout
    undef $timeout;
  }

  # create a new http request object, initializing it with the
  # up (upload) command for a new file token
  my $request =
    HTTP::Request->new(GET => $next_token_url);

  # accept all file types
  $request -> header('Accept'              => '*/*');

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    # no more tokens...
    return undef;
  }
  else {

    my $token = new ToposToken();

    $token -> pool ($self);

    # set the lock timeout (if one was specified)
    $token -> timeout ($timeout);

    # collect information about the token:
    #   get the uri
    $token -> url ($response -> request -> uri);

    #   is there a lock url?
    $token -> lockurl ($response -> header('X-Topos-LockURL'));

    #   is there a file name?
    my $content_disposition = $response -> header('Content-Disposition');

    if (defined $content_disposition) {
      # token is a file
      my ($filename) =
        $content_disposition =~ m/filename="([^"]+)"/;
      
      # take just the file name, no path
      $filename =~ s/^.*\///;

      # save the contents of the response to file
      open(F, ">", $filename);
      print(F $response -> content);
      close(F);

      $token -> filename ($filename);
    }
    else {
      # no file, just set the token content
      $token -> content ($response -> content);
    }
    return $token;
  } # if response is not an error
} # sub next_token


sub name {
  my $self = shift;
  my $name = shift;

  $self -> {'name'} = $name if defined $name;

  return $self -> {'name'};
}

sub url {
  my $self = shift;
  return $TOPOS_URL ."/pools/" . $self -> name;
}


# ------------------------------------------------------------------
# private routines
# ------------------------------------------------------------------

sub slurp {
  my $file_name = shift;
  open(F, "<", $file_name);
  local $/; # enable slurp mode
  my $content = <F>;
  close(F);

  return $content;
}

# module OK
1;

__END__

=cut
