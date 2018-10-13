package CPAN::Audit;
use 5.008001;
use strict;
use warnings;
use CPAN::Audit::Discover;
use CPAN::Audit::Version;
use CPAN::Audit::Query;
use CPAN::Audit::DB;

our $VERSION = "0.02";

sub new {
    my $class = shift;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ascii}       = $params{ascii};
    $self->{verbose}     = $params{verbose};
    $self->{no_color}    = $params{no_color};
    $self->{interactive} = $params{interactive};

    if ( !$self->{interactive} ) {
        $self->{ascii}    = 1;
        $self->{no_color} = 1;
    }

    $self->{query} = CPAN::Audit::Query->new( db => CPAN::Audit::DB->db );
    $self->{discover} = CPAN::Audit::Discover->new( db => CPAN::Audit::DB->db );

    return $self;
}

sub command {
    my $self = shift;
    my ( $command, @args ) = @_;

    my %dists;

    if ( $command eq 'module' ) {
        my ( $module, $version_range ) = @args;
        $self->error("Usage: module <module> [version-range]") unless $module;

        my $release = CPAN::Audit::DB->db->{module2dist}->{$module};
        my $dist = $release ? CPAN::Audit::DB->db->{dists}->{$release} : undef;

        if ( !$dist ) {
            $self->output("__GREEN__Module '$module' is not in database");
            return;
        }

        $dists{$dist} = $version_range;
    }
    elsif ( $command eq 'release' ) {
        my ( $release, $version_range ) = @args;
        $self->error("Usage: release <module> [version-range]") unless $release;

        my $dist = CPAN::Audit::DB->db->{dists}->{$release};

        if ( !$dist ) {
            $self->output(
                "__GREEN__Distribution '$release' is not in database");
            return;
        }

        $dists{$dist} = $version_range;
    }
    elsif ( $command eq 'show' ) {
        my ($advisory_id) = @args;
        $self->error("Usage: show <advisory-id>") unless $advisory_id;

        my ($release) = $advisory_id =~ m/^CPANSA-(.*?)-(\d+)-(\d+)$/;
        $self->error("Invalid advisory id") unless $release;

        my $dist = CPAN::Audit::DB->db->{dists}->{$release};
        $self->error("Unknown advisory id") unless $dist;

        my ($advisory) =
          grep { $_->{id} eq $advisory_id } @{ $dist->{advisories} };
        $self->error("Unknown advisory id") unless $advisory;

        local $self->{verbose} = 1;
        $self->print_advisory($advisory);

        return;
    }
    elsif ( $command eq 'dependencies' || $command eq 'deps' ) {
        my ($path) = @args;
        $path = '.' unless defined $path;

        $self->error("Usage: deps <path>") unless -d $path;

        my @deps = $self->{discover}->discover($path);

        $self->output( 'Discovered %d dependencies', scalar(@deps) );

        foreach my $dep (@deps) {
            my $dist = $dep->{dist}
              // CPAN::Audit::DB->db->{module2dist}->{ $dep->{module} };
            next unless $dist;

            $dists{$dist} = $dep->{version};
        }
    }
    else {
        $self->error("Error: unknown command: $command. See -h");
    }

    my $total_advisories = 0;

    if (%dists) {
        my $query = $self->{query};

        foreach my $distname ( sort keys %dists ) {
            my $version_range = $dists{$distname};

            my @advisories =
              $query->advisories_for( $distname, $version_range );

            $version_range = 'Any'
              if $version_range eq '' || $version_range eq '0';

            if (@advisories) {
                $self->output(
                    '__RED__%s (requires %s) has %d advisories__RESET__',
                    $distname, $version_range, scalar(@advisories) );

                foreach my $advisory (@advisories) {
                    $self->print_advisory($advisory);
                }
            }

            $total_advisories += @advisories;
        }
    }

    if ($total_advisories) {
        $self->output( '__RED__Total advisories found: %d__RESET__',
            $total_advisories );
    }
    else {
        $self->output('__GREEN__No advisories found__RESET__');
    }
}

sub error {
    my $self = shift;
    my ( $msg, @args ) = @_;

    $self->output( "Error: $msg", @args );
    exit 255;
}

sub output {
    my $self = shift;
    my ( $format, @params ) = @_;

    my $msg = @params ? ( sprintf( $format, @params ) ) : ($format);

    if ( $self->{no_color} ) {
        $msg =~ s{__BOLD__}{}g;
        $msg =~ s{__GREEN__}{}g;
        $msg =~ s{__RED__}{}g;
        $msg =~ s{__RESET__}{}g;
    }
    else {
        $msg =~ s{__BOLD__}{\e[39;1m}g;
        $msg =~ s{__GREEN__}{\e[32m}g;
        $msg =~ s{__RED__}{\e[31m}g;
        $msg =~ s{__RESET__}{\e[0m}g;

        $msg .= "\e[0m";
    }

    print "$msg\n";
}

sub print_advisory {
    my $self = shift;
    my ($advisory) = @_;

    $self->output("  __BOLD__* $advisory->{id}");

    if ( $self->{verbose} ) {
        print "    $advisory->{description}\n";
        if ( $advisory->{affected_versions} ) {
            print "    Affected range: $advisory->{affected_versions}\n";
        }
        if ( $advisory->{fixed_versions} ) {
            print "    Fixed range: $advisory->{fixed_versions}\n";
        }
        foreach my $reference ( @{ $advisory->{references} // [] } ) {
            print "    $reference\n";
        }
        print "\n";
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

CPAN::Audit - Audit CPAN distributions for known vulnerabilities

=head1 SYNOPSIS

    use CPAN::Audit;

=head1 DESCRIPTION

CPAN::Audit is a module and a database at the same time. It is used by L<cpan-audit> command line application to query
for vulnerabilities.

=head1 LICENSE

Copyright (C) Viacheslav Tykhanovskyi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Viacheslav Tykhanovskyi E<lt>viacheslav.t@gmail.comE<gt>

=head1 CREDITS

Takumi Akiyama (github.com/akiym)

=cut
