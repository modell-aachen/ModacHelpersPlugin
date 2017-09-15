package Foswiki::Contrib::ModacHelpersContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::UI::Rename;

our $VERSION = "1.0";
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'This contrib provides several helper functions.';
our $NO_PREFS_IN_TOPIC = 1;

sub updateTopicLinks {
  my ($oldWeb, $oldTopic, $newWeb, $newTopic) = @_;

  my ($oldTopicMeta, undef) = Foswiki::Func::readTopic($oldWeb, $oldTopic);
  my $localReferringTopics = Foswiki::UI::Rename::_getReferringTopics($Foswiki::Plugins::SESSION, $oldTopicMeta, 0);
  my $globalReferringTopics = Foswiki::UI::Rename::_getReferringTopics($Foswiki::Plugins::SESSION, $oldTopicMeta, 1);
  my %allReferringTopics = (%$localReferringTopics, %$globalReferringTopics);
  my @allReferringTopicNames = keys(%allReferringTopics);

  my $updateLinkOptions = {
      oldWeb => $oldWeb,
      oldTopic => $oldTopic,
      newWeb => $newWeb,
      newTopic => $newTopic,
      inWeb => $newWeb,
      fullPaths => 0,
      noautolink => 1,
      in_pre => 0,
      in_noautolink => 0,
      in_literal => 0,

  };

  Foswiki::UI::Rename::_updateReferringTopics($Foswiki::Plugins::SESSION, \@allReferringTopicNames, \&Foswiki::UI::Rename::_replaceTopicReferences,
  $updateLinkOptions);

  return;
}

1;