package SDav;

use Exporter;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common ('GET', 'POST', 'PUT');
use LWP::MediaTypes;
use LWP::UserAgent;
use Data::Dumper;

use strict;
use warnings;

# export the 'read_webdav_conf' routine on request
our @ISA       = ('Exporter');
our @EXPORT_OK = ('read_webdav_conf');


# Constructor
sub connect {
  my $package      = shift;

  my $server       = shift;
  my $realm        = shift;
  my $username     = shift;
  my $password     = shift;

  my $self = bless {}, $package;

  $self -> {'user_agent'} = new LWP::UserAgent();

  # set the agent name
  $self -> {'user_agent'} -> agent ('SDav/0.2');

  $self -> {'user_agent'} -> credentials (
    $server, $realm, $username, $password
  );

  # determine the base url
  my $url;

  if ($server =~ m/:443$/) {
    $url = "https://";
  }
  else {
    $url = "http://";
  }

  # append the server
  $url .= $server;

  $self -> {'base_url'} = $url;

  # set the path
  $self -> {'path'} = [];

  return $self;
}


sub change_dir {
  my $self = shift;

  my $path = shift;

  if ($path =~ m{/}) {
    $self -> {'path'} = [];
  }

  my @subdirs = split(/\//, $path);

  for my $subdir (@subdirs) {

    next unless defined $subdir;
    next if $subdir eq '';

    if ($subdir eq '..') {
      pop (@{ $self -> {'path'} });
    }
    else {
      push (@{ $self -> {'path'} }, $subdir);
    }
  }
  return $self -> {'path'};
}

# alias for change_dir
sub cd {
  return change_dir(@_);
}


sub base_url {
  my $self = shift;
  return $self -> {'base_url'};
}

sub dir_url {
  my $self = shift;

  my $dir_url = $self -> {'base_url'} . "/";

  for my $subdir ( @{ $self -> {'path'} } ) {

    $dir_url .= "$subdir/";

  }
  return $dir_url;
}


# ------------------------------------------------------------------------ 
# Get a directory's contents
#
# Returns a hash in which the keys are directory entries, without path.
# If a directory entry ends in a slash, it means that the entry is a
# subdirectory of the current directory.
#
# The value in each key-value pair is the http-link to the file.
# 
# NOTE: Has been tested on SARA's webdav implementation. There is, however, no
# standard return format for a "GET" command on a directory, so this routine
# may or may not work on other WebDAV implementations.
sub ls {
  my $self = shift;

  my %entries;

  my $dir_url  = $self -> dir_url();

  # create a new http request object
  my $request = HTTP::Request->new(GET => $dir_url);

  # accept text files
  $request -> header('Accept'              => 'text/plain');

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    print(STDERR "*** error in ls();\n");
    print(STDERR "*** code is '", $response -> code, "'\n");
    print(STDERR $response -> status_line, "\n");
  }
  else {

    # find all list items from the content string
    my @list_items = $response -> content =~ m/<li>(.+?)<\/li>/img;

    # process each list item, search for the link and the link text
    for my $list_item (@list_items) {
      my ($link, $entry) = 
        $list_item =~ m/<a href=\"(.+?)\">(.+?)<\/a>/;
      $entries{$entry} = $link;
    }
  }
  return %entries;
}

=head2 Upload and store a file

=head3 Usage

Uploading a file in the current remote directory with the original name:

   $dav -> put_file('test.txt');

Uploading a file to a directory relative to the current remote directory
with a different name:

   $dav -> put_file('photo.jpg' => 'photos/photo1.jpg');

Uploading a file to an absolute remote path:

   $dav -> put_file('contents.xml' => '/web/contents.xml');

=cut
sub put_file {
  my $self = shift;
  my $file_path   = shift;  # required
  my $target_path = shift;  # optional

  unless (defined $file_path) {
    print(STDERR "*** error: no file given.\n");
    return;
  }

  # check if the file exists
  unless (-f $file_path) {
    print(STDERR "*** error: file '$file_path' does not exist.\n");
    return;
  }

  # get the file name from the (possibly relative or absolute) path
  (my $file_name = $file_path) =~ s/^.*\///;

  # determine the media type
  my $media_type = media_type($file_name);

  my $target_url;

  if (defined $target_path) {
    # target specified
    if ($target_path =~ m/^\//) {
      # absolute remote path
      $target_url = $self -> {'base_url'} . $target_path;
    }
    else {
      # relative remote path
      $target_url = $self -> dir_url . $target_path;
    }
  }
  else {
    # no target specified
    $target_url = $self -> dir_url . $file_name;
  }

  
  # create a new http request object 
  my $request =
    HTTP::Request->new(PUT => $target_url);

  # set the headers
  $request -> header('Content-Type'        => $media_type);
  $request -> header('Content-Disposition' => 
                          "attachment; filename=\"$file_name\"");

  $request -> header('Accept'              => 'text/plain');

  # add the payload
  $request -> content(slurp($file_path));

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    printf(STDERR "*** error while uploading '$file_path'\n");
    return 0;
  }
  return 1;
}


=head2 Creating directories

=cut
sub make_dir {
  my $self = shift;

  # input variables
  my $new_path = shift;

  # output variables
  my $status_ok;          # 1 if the directory was created, otherwise
                          # 0
  my $message;            # message describing the succes or the error

  # internal variables
  my $target_url;

  if (defined $new_path) {
    # target specified
    if ($new_path =~ m/^\//) {
      # absolute remote path
      $target_url = $self -> {'base_url'} . $new_path;
    }
    else {
      # relative remote path
      $target_url = $self -> dir_url . $new_path;
    }

    my $request = HTTP::Request->new(MKCOL => $target_url); 

    # no headers required
    my $response = $self -> {'user_agent'} -> request ($request);

    # response messages if the caller wants a message
    my %messages = (
      201  => 'created',
      403  => 'forbidden',
      405  => 'method not allowed',
      409  => 'conflict',
      415  => 'unsupported media type',
      507  => 'insufficient storage',
    );

    # find the response message and the status

    $status_ok = $response -> is_error ? 0 : 1;

    my $code = $response -> code;

    $message = "unknown code"; # default message for unknown code

    if (exists $messages{$code}) {
      $message = $messages{$code};
    }
  } # if defined $new_path
  else {
    # no directory given, error
    $status_ok = 0;                            # not ok
    $message   = "no path specified";
  }

  if (wantarray) {
    return ($status_ok, $message);
  }
  else {
    return $status_ok;
  }
}
  
# alias for make_dir
sub mkdir {
  return make_dir(@_);
}

sub get_file {
  my $self = shift;
  my $path = shift;

  my $url;

  # determine what kind of file was specified
  if ($path =~ m/^https?:/) {
    # it is a full url
    $url = $path;
  }
  elsif ($path =~ m/^\//) {
    # it is an absolute path
    $url = $self -> base_url . $path;
  }
  else {
    # it is a relative path (or at least, it should be)
    $url = $self -> dir_url . $path;
  }

  my $request = HTTP::Request->new(GET => $url);
 
  # accept all file types
  $request -> header('Accept' => '*/*');

  # do the actual request
  my $response = $self -> {'user_agent'} -> request ($request);

  if ($response -> is_error) {
    printf(STDERR "*** error while getting the file.\n");
    return undef;
  }
  else {
    my $content_disposition = $response -> header('Content-Disposition');

    my $filename;

    if (defined $content_disposition) {

      ($filename) = $content_disposition =~ m/filename="([^"]+)"/;
      
      # take just the file name, no path (for safety)
      $filename =~ s/^.*\///;

    }
    else {
      # derive the file name from the url
      ($filename) = ($url =~ m/\/([^\/]+)$/);
    }

    # save the contents of the response to file in the *current* directory
    open(F, ">", $filename);
    print(F $response -> content);
    close(F);

    return $filename;
  }
  # has returned a file name or undef
}


# ========================================================================
# Private, static functions
# ========================================================================

# Determine the media type in a simple way for common files
sub media_type {
  my $filename = shift;

  # some mime-types of the most common files
  my %media_types = (
    txt       => 'text/plain',
    xml       => 'text/xml',
    html      => 'text/html',
    csv       => 'text/csv',
    java      => 'text/x-java',
    pl        => 'text/x-perl',
    pm        => 'text/x-perl',
    py        => 'text/x-python',
    sh        => 'text/x-sh',
    csh       => 'text/x-csh',
    xls       => 'application/vnd.ms-excel',
    doc       => 'application/msword',
    jpg       => 'image/jpeg',
    jpeg      => 'image/jpeg',
    png       => 'image/png',
    gif       => 'image/gif',
    tif       => 'image/tif',
    tiff      => 'image/tiff',
    class     => 'application/java-vm',
    jar       => 'application/java-archive',
    zip       => 'application/zip',
  );

  # default unless another media type can be determined
  my $media_type = 'application/octet-stream';

  if ($filename =~ m/\.(\w+?)$/) {
    my $extension = lc $1;

    if (exists $media_types{$extension}) {
      $media_type = $media_types{$extension};
    }
  }
  return $media_type;
}

sub slurp {
  my $file_name = shift;
  open(F, "<", $file_name) or die("$! : $file_name");
  local $/; # enable slurp mode
  my $content = <F>;
  close(F);

  return $content;
}


sub read_webdav_conf {
  my $file_name = shift;
  unless (defined $file_name) {
    $file_name = "webdav.conf";
  }

  my ($server, $realm, $username, $password);

  open(CONF, "<$file_name");
  while(my $line = <CONF>) {
    chomp $line;
    $line =~ s/#.*$//; # remove comments
    $line =~ s/^\s*//; # remove leading whitespace
    $line =~ s/\s*$//; # remove trailing whitespace

    next if $line eq "";  # skip empty lines (after cleaning up)
    if ($line =~ m/^server\s*=\s*\"([^\"]+)\"$/) {
      $server = $1;
      next;
    }
    elsif ($line =~ m/^realm\s*=\s*\"([^\"]+)\"$/) {
      $realm = $1;
      next;
    }
    elsif ($line =~ m/^username\s*=\s*\"([^\"]+)\"$/) {
      $username = $1;
      next;
    }
    elsif ($line =~ m/^password\s*=\s*\"([^\"]+)\"$/) {
      $password = $1;
      next;
    }
    else {
      print(STDERR "*** error while reading '$file_name' in the line:\n",
                   "  => $line\n");
    }
  }
  close(CONF);

  return ($server, $realm, $username, $password);
}

    


# module OK
1;


