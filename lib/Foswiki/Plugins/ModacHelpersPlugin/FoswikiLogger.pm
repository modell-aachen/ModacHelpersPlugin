package Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger;

use strict;
use warnings;

use Sentry::Raven;
use Devel::StackTrace;

use Foswiki::Plugins;
use Foswiki::Func;
use Foswiki::Plugins::ModacHelpersPlugin::RavenConnector;

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
            extra  => \@_
        }
    );
}

sub logInfo {
    my $caller = shift;
    return unless isLogLevelActive($caller, 4);

    my $detailedPackage = getDetailedPackage($caller);
    unshift @_, INFO;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'debug',
            caller => $detailedPackage,
            extra  => \@_
        }
    );
}

sub logWarning {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);

    _raven($detailedPackage, WARNING, \@_);

    unshift @_, WARNING;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            extra  => \@_
        }
    );
}

sub logError {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);

    _raven($detailedPackage, ERROR, \@_);

    unshift @_, ERROR;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            extra  => \@_
        }
    );
}

sub logFatal {
    my $caller = shift;

    my $detailedPackage = getDetailedPackage($caller);

    my $trace = Devel::StackTrace->new(
        ignore_package => __PACKAGE__,
    );

    my $traceString = $trace->as_string();

    _raven($detailedPackage, FATAL, \@_, traceString => $traceString);

    unshift @_, FATAL;
    push @_, $traceString;
    return $Foswiki::Plugins::SESSION->logger()->log(
        {
            level  => 'warning',
            caller => $detailedPackage,
            extra  => \@_
        }
    );
}

sub _raven {
    my ($caller, $level, $message, %options) = @_;
    my $request = Foswiki::Func::getRequestObject();

    eval {
        require Foswiki::Plugins::QueryVersionPlugin;
        $options{release} = Foswiki::Plugins::QueryVersionPlugin::query(
            $Foswiki::Plugins::SESSION,
            { name => 'QwikiContrib' },
        ) || '_unknown_';
    };

    $options{cuid} = Foswiki::Func::getCanonicalUserID();
    $options{remoteAddress} = $request->remoteAddress(),
    $options{uri} = $request->uri();
    $options{baseUrl} = $request->url(-base => 1);
    $options{method} = $request->method();
    my %params = ();
    foreach my $param ($request->param()) {
        my @values = $request->param($param);
        $params{$param} = \@values;
    }
    $options{params} = \%params;

    my $error = Foswiki::Plugins::ModacHelpersPlugin::RavenConnector::sendMessage($caller, $level, $message, %options);
    Foswiki::Func::writeWarning('Could not send message to sentry', $error) if $error;
}

1;
