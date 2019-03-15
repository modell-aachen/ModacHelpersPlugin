package Foswiki::Plugins::ModacHelpersPlugin::RavenConnector;

use strict;
use warnings;

use Exporter 'import';
use JSON;

our @EXPORT = qw(sentryMessage);

our $raven;

sub sendMessage {
    my ($caller, $level, $message, %options) = @_;

    return if $Foswiki::cfg{Extensions}{ModacHelpersPlugin}{NoBackendSentry};
    return 'Please configure {Extensions}{ModacHelpersPlugin}{SentryDsn}' unless $Foswiki::cfg{Extensions}{ModacHelpersPlugin}{SentryDsn};

    eval {
        require Sentry::Raven;

        $raven ||= Sentry::Raven->new(
            sentry_dsn => $Foswiki::cfg{Extensions}{ModacHelpersPlugin}{SentryDsn},
        );
        my %ravenOptions = (
            level => $level,
            culprit => $caller,
            tags => {type => 'foswiki_backend'},
            environment => ($Foswiki::cfg{ModacHelpersPlugin}{Environment} || 'unknown_environment'),
        );
        if($options{uri}) {
            my $data = "params=" . to_json($options{params} || {}, {pretty => 1}); # apparently raven supports only a single key=value pair
            %ravenOptions = (%ravenOptions, Sentry::Raven->request_context($options{uri}, method => $options{method}, data => $data));
        }
        if($options{cuid} && $options{remoteAddress}) {
            %ravenOptions = (
                %ravenOptions,
                Sentry::Raven->user_context(
                    id => $options{cuid},
                    ip_address => $options{remoteAddress},
                ),
            );
        }
        if($options{release}) {
            $ravenOptions{release} = $options{release};
        }
        if($options{traceString}) {
            $ravenOptions{extra} = {
                stacktrace => $options{traceString},
            };
        }
        $raven->capture_message(
            join(' | ', @$message),
            %ravenOptions,
        );
    };
    return $@;
}

1;
