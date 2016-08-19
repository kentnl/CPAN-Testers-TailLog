use 5.006;    # our
use strict;
use warnings;

package CPAN::Testers::TailLog;

our $VERSION  = '0.001000';
our $DISTNAME = 'CPAN-Testers-TailLog';

# ABSTRACT: Extract recent test statuses from metabase log

# AUTHORITY

sub new {
    my $buildargs = { ref $_[1] ? %{ $_[1] } : @_[ 1 .. $#_ ] };
    my $class = ref $_[0] ? ref $_[0] : $_[0];
    my $self = bless $buildargs, $class;
    $self->_check_cache_file  if exists $self->{cache_file};
    $self->_check_min_refresh if exists $self->{min_refresh};
    $self->_check_url         if exists $self->{url};
    $self;
}

sub cache_file {
    $_[0]->{cache_file} = $_[0]->_build_cache_file
      unless exists $_[0]->{cache_file};
    $_[0]->{cache_file};
}

sub get {
    if (   $_[0]->min_refresh <= 0
        or not defined $_[0]->{_last_refresh}
        or ( ( time - $_[0]->{_last_refresh} ) > $_[0]->min_refresh ) )
    {
        $_[0]->_ua->mirror( $_[0]->url, $_[0]->cache_file );
        $_[0]->{_last_refresh} = time;
    }
    $_[0]->_parse_response( $_[0]->cache_file );
}

sub min_refresh {
    $_[0]->{min_refresh} = $_[0]->_build_min_refresh
      unless exists $_[0]->{min_refresh};
    $_[0]->{min_refresh};
}

sub url {
    $_[0]->{url} = $_[0]->_build_url unless exists $_[0]->{url};
    $_[0]->{url};
}

# -- private ] --

sub _parse_line {
    my %record;
    @record{
        qw( submitted reporter grade filename platform perlversion uuid accepted )
      } = (
        $_[1] =~ qr{
      \A
      \s*
      \[ (.+? ) \] # submitted
      \s*
      \[ (.+? ) \] # reported
      \s*
      \[ (.+? ) \] # grade
      \s*
      \[ (.+?) \] # filename
      \s*
      \[ (.+?) \] # platform
      \s*
      \[ (.+?) \] # perlversion
      \s*
      \[ (.+?) \] # uuid
      \s*
      \[ (.+?) \] # accepted
    }x
      );
    \%record;
}

sub _parse_response {
    require Path::Tiny;
    my (@lines) = Path::Tiny::path( $_[1] )->lines_utf8( { chomp => 1 } );

    # Skip prelude
    shift @lines while @lines and $lines[0] !~ /\A\s*\[/;
    [ map { $_[0]->_parse_line($_) } @lines ];
}

sub _ua {
    $_[0]->{_ua} = $_[0]->_build_ua unless exists $_[0]->{_ua};
    $_[0]->{_ua};
}

# -- builders ] --
sub _build_cache_file {
    require File::Temp;
    my $temp = File::Temp->new(
        TEMPLATE => $DISTNAME . '-XXXXX',
        TMPDIR   => 1,
        SUFFIX   => '.txt',
    );
    $_[0]->{_tempfile} = $temp;
    require Path::Tiny;

    # Touching tempfiles required to get useful if-modified behaviour
    Path::Tiny::path( $temp->filename )->touch( time - ( 7 * 24 * 60 * 60 ) );
    $temp->filename;
}

sub _build_min_refresh {
    60;
}

sub _build_ua {
    require HTTP::Tiny;
    HTTP::Tiny->new( agent => ( $DISTNAME . '/' . $VERSION ), );
}

sub _build_url {
    'http://metabase.cpantesters.org/tail/log.txt';
}

# -- checkers ] --
sub _check_cache_file {
    require Path::Tiny;
    my $path = Path::Tiny::path( $_[0]->{cache_file} );
    my $dir  = $path->parent;
    die "cache_file: Directory for $path not accessible: $?"
      unless -e $dir
      and -d $dir
      and -r $dir;
    if ( not -e $path ) {

        # Path doesn't exist, test creating it
        # Hope touch dies if it can't be written
        $path->touch( time - ( 7 * 24 * 60 * 60 ) );
    }
    return if -e $path and not -d $path and -w $path;
    die "cache_file: $path exists but is unwriteable";
}

sub _check_min_refresh {
    die "min_refresh: not a positive integer"
      unless $_[0]->{min_refresh} =~ /\A\d+\z/;
}

sub _check_url {
    die "url: Missing protocol in $_[0]->{url}" if $_[0]->{url} !~ qr{://};
    die "url: Unknown protocol in $_[0]->{url}"
      if $_[0]->{url} !~ qr{\Ahttps?://};
}

1;
