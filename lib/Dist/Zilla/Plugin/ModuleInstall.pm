use strict;
use warnings;

package Dist::Zilla::Plugin::ModuleInstall;

our $VERSION = '1.000000';

# ABSTRACT: Build Module::Install based Distributions with Dist::Zilla

# AUTHORITY

use Moose;
use Moose::Autobox;
use Config;
use Dist::Zilla::Plugin::MakeMaker::Runner;

has 'make_path' => (
  isa     => 'Str',
  is      => 'ro',
  default => $Config{make} || 'make',
);

has '_runner' => (
  is      => 'ro',
  lazy    => 1,
  handles => [qw(build test)],
  default => sub {
    my ($self) = @_;
    Dist::Zilla::Plugin::MakeMaker::Runner->new(
      {
        zilla       => $self->zilla,
        plugin_name => $self->plugin_name . '::Runner',
        make_path   => $self->make_path,
      }
    );
  },
);

with 'Dist::Zilla::Role::BuildRunner';
with 'Dist::Zilla::Role::InstallTool';
with 'Dist::Zilla::Role::TextTemplate';
with 'Dist::Zilla::Role::Tempdir';
with 'Dist::Zilla::Role::PrereqSource';
with 'Dist::Zilla::Role::TestRunner';

use Dist::Zilla::File::InMemory;

=head1 DESCRIPTION

This module will create a F<Makefile.PL> for installing the dist using L<Module::Install>.

It is at present a very minimal feature set, but it works.

=cut

=head1 SYNOPSIS

dist.ini

    [ModuleInstall]

=cut

use namespace::autoclean;

require inc::Module::Install;

sub _doc_template {
  my ( $self, $args ) = @_;
  my $t = join qq{\n},
    (
    q{use strict;},
    q{use warnings;},
    q{# Warning: This code was generated by }
      . __PACKAGE__
      . q{ Version }
      . ( __PACKAGE__->VERSION() || 'undefined ( self-build? )' ),
    q{# As part of Dist::Zilla's build generation.},
    q{# Do not modify this file, instead, modify the dist.ini that configures its generation.},
    q|use inc::Module::Install {{ $miver }};|,
    q|{{ $headings }}|,
    q|{{ $requires }}|,
    q|{{ $feet }}|,
    q{WriteAll();},
    );
  return $self->fill_in_string( $t, $args );
}

sub _label_value_template {
  my ( $self, $args ) = @_;
  return $self->fill_in_string( q|{{$label}} '{{ $value }}';|, $args );
}

sub _label_string_template {
  my ( $self, $args ) = @_;
  return $self->fill_in_string( q|{{$label}} "{{ quotemeta( $string ) }}";|, $args );
}

sub _label_string_string_template {
  my ( $self, $args ) = @_;
  return $self->fill_in_string( q|{{$label}}  "{{ quotemeta($stringa) }}" => "{{ quotemeta($stringb) }}";|, $args );
}

sub _generate_makefile_pl {
  my ($self) = @_;
  my ( @headings, @requires, @feet );

  push @headings, _label_value_template( $self, { label => 'name', value => $self->zilla->name } ),
    _label_string_template( $self, { label => 'abstract', string => $self->zilla->abstract } ),
    _label_string_template( $self, { label => 'author',   string => $self->zilla->authors->[0] } ),
    _label_string_template( $self, { label => 'version',  string => $self->zilla->version } ),
    _label_string_template( $self, { label => 'license',  string => $self->zilla->license->meta_yml_name } );

  my $prereqs = $self->zilla->prereqs;

  my $doreq = sub {
    my ( $key, $target ) = @_;
    push @requires, qq{\n# @$key => $target};
    my $hash = $prereqs->requirements_for(@$key)->as_string_hash;
    for ( sort keys %{$hash} ) {
      if ( $_ eq 'perl' ) {
        push @requires, _label_string_template( $self, { label => 'perl_version', string => $hash->{$_} } );
        next;
      }
      push @requires,
        $self->_label_string_string_template(
        {
          label   => $target,
          stringa => $_,
          stringb => $hash->{$_},
        }
        );
    }
  };

  $doreq->( [qw(configure requires)],   'configure_requires' );
  $doreq->( [qw(build     requires)],   'requires' );
  $doreq->( [qw(runtime   requires)],   'requires' );
  $doreq->( [qw(runtime   recommends)], 'recommends' );
  $doreq->( [qw(test      requires)],   'test_requires' );

  push @feet, qq{\n# :ExecFiles};
  for my $execfile ( $self->zilla->find_files(':ExecFiles')->map( sub { $_->name } )->flatten ) {
    push @feet, _label_string_template( $self, $execfile );
  }
  my $content = _doc_template(
    $self,
    {
      miver    => "$Module::Install::VERSION",
      headings => join( qq{\n}, @headings ),
      requires => join( qq{\n}, @requires ),
      feet     => join( qq{\n}, @feet ),
    }
  );
  return $content;
}

=method register_prereqs

Tells Dist::Zilla about our needs to have EU::MM larger than 6.42

=cut

sub register_prereqs {
  my ($self) = @_;
  $self->zilla->register_prereqs( { phase => 'configure' }, 'ExtUtils::MakeMaker' => 6.42 );
  $self->zilla->register_prereqs( { phase => 'build' },     'ExtUtils::MakeMaker' => 6.42 );
}

=method setup_installer

Generates the Makefile.PL, and runs it in a tmpdir, and then harvests the output and stores
it in the dist selectively.

=cut

sub setup_installer {
  my ( $self, $arg ) = @_;

  my $file = Dist::Zilla::File::FromCode->new( { name => 'Makefile.PL', code => sub { _generate_makefile_pl($self) }, } );

  $self->add_file($file);
  my (@generated) = $self->capture_tempdir(
    sub {
      system( $^X, 'Makefile.PL' ) and do {
        warn "Error running Makefile.PL, freezing in tempdir so you can diagnose it\n";
        warn "Will die() when you 'exit' ( and thus, erase the tempdir )";
        system("bash") and die "Can't call bash :(";
        die "Finished with tempdir diagnosis, killing dzil";
      };
    }
  );
  for (@generated) {
    if ( $_->is_new ) {
      $self->log( 'ModuleInstall created: ' . $_->name );
      if ( $_->name =~ /^inc\/Module\/Install/ ) {
        $self->log( 'ModuleInstall added  : ' . $_->name );
        $self->add_file( $_->file );
      }
    }
    if ( $_->is_modified ) {
      $self->log( 'ModuleInstall modified: ' . $_->name );
    }
  }
  return;
}

1;

