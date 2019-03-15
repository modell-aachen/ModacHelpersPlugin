package Foswiki::Plugins::ModacHelpersPlugin::LoggerInstance;

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

sub new {
    my ($class) = @_;

    my $this = {};
    bless $this, $class;

    return $this;
}

sub logDebug {
    my $this = shift;

    my @caller = caller();

    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logDebug(\@caller, @_);
}

sub logInfo {
    my $this = shift;

    my @caller = caller();

    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logInfo(\@caller, @_);
}

sub logWarning {
    my $this = shift;

    my @caller = caller();

    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logWarning(\@caller, @_);
}

sub logError {
    my $this = shift;

    my @caller = caller();

    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logError(\@caller, @_);
}

sub logFatal {
    my $this = shift;

    my @caller = caller();

    Foswiki::Plugins::ModacHelpersPlugin::FoswikiLogger::logFatal(\@caller, @_);
}

1;
