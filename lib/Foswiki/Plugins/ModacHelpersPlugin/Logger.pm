package Foswiki::Plugins::ModacHelpersPlugin::Logger;

use strict;
use warnings;

use Exporter 'import';
use Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger;

our @EXPORT = qw(
    logDebug
    logInfo
    logWarn
    logWarning
    logError
    logFatal
);

BEGIN {
    *logWarn = \&logWarning;
}

sub logDebug {
    my @caller = caller();
    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logDebug(\@caller, @_);
}

sub logInfo {
    my @caller = caller();
    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logInfo(\@caller, @_);
}

sub logWarning {
    my @caller = caller();
    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logWarning(\@caller, @_);
}

sub logError {
    my @caller = caller();
    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logError(\@caller, @_);
}

sub logFatal {
    my @caller = caller();
    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logFatal(\@caller, @_);
}

1;
