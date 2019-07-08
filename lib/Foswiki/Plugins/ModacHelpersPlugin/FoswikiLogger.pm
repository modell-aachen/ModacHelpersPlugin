package Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger;

use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::Func;

use constant {
    FATAL => 'fatal',
    ERROR => 'error',
    WARNING => 'warning',
    INFO => 'info',
    DEBUG => 'debug',
};

sub isLogLevelActive {
    my ($caller, $level) = @_;

    return 1 if $Foswiki::cfg{Extensions}{ModacHelpersPlugin}{ModacLogLevel} >= $level;

    my $package = $caller->[0];
    my $packageLevel;
    if(defined $Foswiki::cfg{Extensions}{$package}{ModacLogLevel}) {
        $packageLevel = $Foswiki::cfg{Extensions}{$package}{ModacLogLevel};
    } elsif(defined $Foswiki::cfg{Plugins}{$package}{ModacLogLevel}) {
        $packageLevel = $Foswiki::cfg{Plugins}{$package}{ModacLogLevel};
    } elsif(defined $Foswiki::cfg{Contrib}{$package}{ModacLogLevel}) {
        $packageLevel = $Foswiki::cfg{Contrib}{$package}{ModacLogLevel};
    }
    return 1 if defined $packageLevel && $packageLevel >= $level;

    return 0;
}

sub getDetailedPackage {
    my ($caller) = @_;

    my $fileGuess = $caller->[0] =~ s#::#/#gr . '.pm';
    if ($caller->[1] =~ m#\Q$fileGuess\E$#) {
        return "$caller->[0] $caller->[2]";
    } else {
        return "$caller->[0] ($caller->[1]) $caller->[2]";
    }
}

sub logDebug {
    my $caller = shift;
    return unless isLogLevelActive($caller, 5);

    my $detailedPackage = getDetailedPackage($caller);

    unshift @_, DEBUG;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'debug',
            caller => $detailedPackage,
            deleteStacktraceFrames => 2,
            extra  => \@_
        }
    );
}

sub logInfo {
    my $caller = shift;
    return unless isLogLevelActive($caller, 4);

    my $detailedPackage = getDetailedPackage($caller);
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'debug',
            caller => $detailedPackage,
            deleteStacktraceFrames => 2,
            extra  => \@_
        }
    );
}

sub logWarning {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);
    unshift @_, WARNING;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            deleteStacktraceFrames => 2,
            extra  => \@_
        }
    );
}

sub logError {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);
    unshift @_, ERROR;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            deleteStacktraceFrames => 2,
            extra  => \@_
        }
    );
}

sub logFatal {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);
    unshift @_, FATAL;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            deleteStacktraceFrames => 2,
            extra  => \@_
        }
    );
}

1;
