#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $Pod::Usage::Formatter = 'Pod::Text::Termcap'; }

use Getopt::Long;
use Pod::Usage;

my $instructions =
{
    '>' => sub
        {
            my $bf = shift;

            if ( defined $bf->{array_size} && $bf->{pointer} + 1 >= $bf->{array_size} )
            {
                print STDERR "[bf.pl] Reached end of memory - Cannot increment memory pointer\n";
                return;
            }

            $bf->{pointer}++;
        },

    '<' => sub
        {
            my $bf = shift;

            if ( $bf->{pointer} <= 0 )
            {
                print STDERR "[bf.pl] Reached beginning of memory - Cannot decrement memory pointer\n";
                return;
            }

            $bf->{pointer}--;
        },

    '+' => sub
        {
            my $bf = shift;

            $bf->{memory}->[ $bf->{pointer} ]++;

            if ( defined $bf->{cell_size} )
            {
                $bf->{memory}->[ $bf->{pointer} ] %= ( 1 << $bf->{cell_size} );
            }
        },

    '-' => sub
        {
            my $bf = shift;

            $bf->{memory}->[ $bf->{pointer} ]--;

            if ( defined $bf->{cell_size} )
            {
                $bf->{memory}->[ $bf->{pointer} ] %= ( 1 << $bf->{cell_size} );
            }
        },

     ',' => sub
        {
            my $bf = shift;

            if ( defined $bf->{prompt} )
            {
                print $bf->{prompt};
            }

            my $input = getc;

            if ( defined $bf->{echo} )
            {
                print $input;
            }

            $bf->{memory}->[ $bf->{pointer} ] = ord $input;

            if ( defined $bf->{cell_size} )
            {
                $bf->{memory}->[ $bf->{pointer} ] %= ( 1 << $bf->{cell_size} );
            }
        },

    '.' => sub
        {
            my $bf = shift;

            print chr $bf->{memory}->[ $bf->{pointer} ];
        },

    '[' => sub
        {
            my $bf = shift;

            if ( ! $bf->{memory}->[ $bf->{pointer} ] )
            {
                $bf->{pc} = $bf->{jump}->{ $bf->{pc} };
            }
        },

    ']' => sub
        {
            my $bf = shift;

            if ( $bf->{memory}->[ $bf->{pointer} ] )
            {
                $bf->{pc} = $bf->{jump}->{ $bf->{pc} };
            }
        },

    '?' => sub
        {
            my $bf = shift;

            my $max = max( $#{ $bf->{memory} }, $bf->{pointer} );

            while ( ! $bf->{memory}->[$max] && $max > $bf->{pointer} )
            {
                $max--;
            }

            my $lines = "\n";

            for ( my $i = 0; $i <= $max; $i += 16 )
            {
                my $line_hex = '';
                my $line_ascii = '';

                for ( my $j = 0; $j < 16; $j++ )
                {
                    my $value = $bf->{memory}->[ $i + $j ];

                    my $hex = sprintf '%02x', $value;
                    my $ascii = ( 32 <= $value && $value <= 126 ) ? chr($value) : '.';

                    if ( $i + $j == $bf->{pointer} )
                    {
                        $line_hex .= "\e[7m" . $hex . "\e[27m";
                        $line_ascii .= "\e[7m" . $ascii . "\e[27m";
                    }
                    else
                    {
                        $line_hex .= $hex;
                        $line_ascii .= $ascii;
                    }

                    $line_hex .= ' ' if $j < 15;
                    $line_hex .= ' ' if $j == 7;
                }

                $lines .= sprintf "%08x  %s  %s\n", $i, $line_hex, $line_ascii;
            }

            print $lines;
        },
};

sub configure
{
    my $bf = shift;

    my $man = 0;

    $bf->{array_size} = 30_000;
    $bf->{cell_size} = 8;

    GetOptions
        (
            'help' => sub { pod2usage( -verbose => 3 ) },
            'array-size=n' => \$bf->{array_size},
            'cell-size=n' => \$bf->{cell_size},
            'echo' => \$bf->{echo},
            'prompt=s' => \$bf->{prompt},
        ) or exit 1;

    my $path = shift @ARGV;

    if ( ! defined $path )
    {
        pod2usage
            (
                -exitval => 1,
                -output => \*STDERR,
                -sections => 'NAME|SYNOPSIS|OPTIONS|AUTHOR',
                -verbose => 99,
            );
    }

    if ( ! -f $path )
    {
        print STDERR "File does not exist\n";
        exit 1;
    }

    open my $fh, '<', $path;
    local $/ = undef;
    $bf->{program} = <$fh>;
    close $fh;
}

sub preprocess
{
    my $bf = shift;

    my $position_stack = [];

    for ( my $position = 0; $position < length $bf->{program}; $position++ )
    {
        my $instruction = substr $bf->{program}, $position, 1;

        if ( $instruction eq '[' )
        {
            push @$position_stack, $position;
        }
        elsif ( $instruction eq ']' )
        {
            my $previous_position = pop @$position_stack;

            if ( ! defined $previous_position )
            {
                print "[bf.pl] Syntax error - Closing bracket without opening bracket\n";
                exit 1;
            }

            $bf->{jump}->{ $position } = $previous_position;
            $bf->{jump}->{ $previous_position } = $position;
        }
    }

    if ( scalar @$position_stack )
    {
        print "[bf.pl] Syntax error - Opening bracket without closing bracket\n";
        exit 1;
    }
}

sub main
{
    my $bf = {};

    $bf->{program} = '';
    $bf->{pc} = -1;  # Program counter will be incremented in main loop
    $bf->{memory} = [];
    $bf->{pointer} = 0;
    $bf->{jump} = {};

    configure($bf);
    preprocess($bf);

    while ( 1 )
    {
        $bf->{pc}++;

        if ( $bf->{pc} >= length $bf->{program} )
        {
            exit;
        }

        my $instruction = substr $bf->{program}, $bf->{pc}, 1;

        if ( defined $instructions->{$instruction} )
        {
            $instructions->{$instruction}->($bf);
        }
    }
}

main();

__END__

=head1 NAME

bf.pl - Brainfuck interpreter in Perl

=head1 SYNOPSIS

bf.pl [I<OPTIONS>] I<PATH>

=head1 OPTIONS

=over 8

=item B<-h>, B<--help>

Display verbose help

=item B<-a>=I<n>, B<--array-size>=I<n>

Set memory array size to I<n> cells (default: 30000)

=item B<-c>=I<n>, B<--cell-size>=I<n>

Set memory cell size to I<n> bits (default: 8)

=item B<-e>, B<--echo>

Cause the , instruction to print after input (default: disabled)

=item B<-p>=I<s>, B<--prompt>=I<s>

Cause the , instruction to print I<s> before input (default: disabled)

=back

=head1 TRADITIONAL INSTRUCTIONS

=over 8

=item B<>>

Increment the memory pointer

=item B<<>

Decrement the memory pointer

=item B<+>

Increment the value at the memory pointer

=item B<->

Decrement the value at the memory pointer

=item B<.>

Output (to standard output) the value at the memory pointer

=item B<,>

Input (from standard input) a value at the memory pointer

=item B<[>

Jump to the matching ] if the value at the memory pointer is zero

=item B<]>

Jump to the matching [ if the value at the memory pointer is nonzero

=back

=head1 EXTENDED INSTRUCTIONS

=over 8

=item B<?>

Output a hexdump of the memory in canonical hex/ascii format

=back

=head1 VERSION

Version 1.1, August 2016

=head1 AUTHOR

L<https://github.com/telnet23>

=cut
