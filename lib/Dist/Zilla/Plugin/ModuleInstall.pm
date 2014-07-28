use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::ModuleInstall;

our $VERSION = '1.000000';

# ABSTRACT: Build Module::Install based Distributions with Dist::Zilla

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( has with );
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
      },
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

















use namespace::autoclean;

require inc::Module::Install;

sub _doc_template {
  my ( $self, $args ) = @_;
  my $package = __PACKAGE__;
  my $version = ( __PACKAGE__->VERSION() || 'undefined ( self-build? )' );

  my $t = <<"EOF";
use strict;
use warnings;
# Warning: This code was generated by ${package} Version ${version}
# As part of Dist::Zilla's build generation.
# Do not modify this file, instead, modify the dist.ini that configures its generation.
use inc::Module::Install {{ \$miver }};
{{ \$headings }}
{{ \$requires }}
{{ \$feet }}
WriteAll();
EOF
  return $self->fill_in_string( $t, $args );
}

sub _label_value_template {
  my ( $self, $args ) = @_;
  my $t = <<"EOF";
{{ \$label }} '{{ \$value }}';
EOF
  return $self->fill_in_string( $t, $args );
}

sub _label_string_template {
  my ( $self, $args ) = @_;
  my $t = <<"EOF";
{{ \$label }} "{{ quotemeta( \$string ) }}";
EOF
  return $self->fill_in_string( $t, $args );
}

sub _label_string_string_template {
  my ( $self, $args ) = @_;
  my $t = <<"EOF";
{{ \$label }}  "{{ quotemeta(\$stringa) }}" => "{{ quotemeta(\$stringb) }}";
EOF
  return $self->fill_in_string( $t, $args );
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
    my $hash = $prereqs->requirements_for( @{$key} )->as_string_hash;
    for ( sort keys %{$hash} ) {
      if ( 'perl' eq $_ ) {
        push @requires, _label_string_template( $self, { label => 'perl_version', string => $hash->{$_} } );
        next;
      }
      push @requires,
        $self->_label_string_string_template(
        {
          label   => $target,
          stringa => $_,
          stringb => $hash->{$_},
        },
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
    },
  );
  return $content;
}







sub register_prereqs {
  my ($self) = @_;
  $self->zilla->register_prereqs( { phase => 'configure' }, 'ExtUtils::MakeMaker' => 6.42 );
  $self->zilla->register_prereqs( { phase => 'build' },     'ExtUtils::MakeMaker' => 6.42 );
  return;
}








sub setup_installer {
  my ( $self, ) = @_;

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
__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=head1 NAME

Dist::Zilla::Plugin::ModuleInstall - Build Module::Install based Distributions with Dist::Zilla

=head1 VERSION

version 1.000000

=head1 SYNOPSIS

dist.ini

    [ModuleInstall]

=head1 DESCRIPTION

This module will create a F<Makefile.PL> for installing the dist using L<Module::Install>.

It is at present a very minimal feature set, but it works.

=head1 METHODS

=head2 register_prereqs

Tells Dist::Zilla about our needs to have EU::MM larger than 6.42

=head2 setup_installer

Generates the Makefile.PL, and runs it in a tmpdir, and then harvests the output and stores
it in the dist selectively.

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Kent Fredric.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
