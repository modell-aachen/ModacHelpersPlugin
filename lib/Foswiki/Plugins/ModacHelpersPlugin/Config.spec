# ---+ Extensions
# ---++ ModacHelpersPlugin

# **STRING**
# A string describing the environment of the system, e.g. production, testing
$Foswiki::cfg{ModacHelpersPlugin}{Environment} = 'production';

# **BOOLEAN**
# Use Sentry for backend logs.
$Foswiki::cfg{Extensions}{ModacHelpersPlugin}{NoBackendSentry} = 0;

# **SELECT 5, 4, 3, 2**
# Global loglevel 5="DEBUG", 4="INFO", 3="WARNING", 2="ERROR" and 1="FATAL"
$Foswiki::cfg{Extensions}{ModacHelpersPlugin}{ModacLogLevel} = 4;

# **STRING**
# Sentry DSN
$Foswiki::cfg{Extensions}{ModacHelpersPlugin}{SentryDsn} = '';

1;
