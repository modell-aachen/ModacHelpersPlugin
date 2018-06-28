package Foswiki::Plugins::ModacHelpersPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::UI::Rename;
use JSON;
use Foswiki::AccessControlException;

our $VERSION = "1.0";
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'This plugin provides several helper functions.';
our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
  Foswiki::Func::registerRESTHandler('webs', \&_handleRESTWebs,
    authenticate  => 1,
    http_allow    => 'GET',
    description   => "Handler to fetch all Web's for current user"
  );

  Foswiki::Func::registerRESTHandler('topics', \&_handleRESTWebTopics,
    authenticate  => 1,
    http_allow    => 'GET',
    description   => "Handler to fetch all Topics for a given web name"
  );
}

sub updateTopicLinks {
  my ($oldWeb, $oldTopic, $newWeb, $newTopic) = @_;

  my $allReferringTopicPaths = getReferringTopics($oldWeb, $oldTopic);

  foreach my $topicPath (@$allReferringTopicPaths) {
      my ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName(undef, $topicPath);
      my $topicObject =
        Foswiki::Meta->load( $Foswiki::Plugins::SESSION, $web, $topic );
      unless ( $topicObject->haveAccess('CHANGE') ) {
          next;
      }
      rewriteLinks($topicObject, $oldWeb, $oldTopic, $newWeb, $newTopic);

  }
  return;
}

sub getReferringTopics {
  my ($web, $topic) = @_;
  my ($topicMeta, undef) = Foswiki::Func::readTopic($web, $topic);
  my $localReferringTopics = Foswiki::UI::Rename::_getReferringTopics($Foswiki::Plugins::SESSION, $topicMeta, 0);
  my $globalReferringTopics = Foswiki::UI::Rename::_getReferringTopics($Foswiki::Plugins::SESSION, $topicMeta, 1);
  my %allReferringTopics = (%$localReferringTopics, %$globalReferringTopics);
  my @allReferringTopicPaths = keys(%allReferringTopics);

  return \@allReferringTopicPaths;
}

sub rewriteLinks {
  my ( $topicObject, $oldLinkWeb, $oldLinkTopic, $newLinkWeb, $newLinkTopic ) = @_;
  my $renderer = $Foswiki::Plugins::SESSION->renderer;
  require Foswiki::Render;


  my $rewriteLinkOptions = {
      oldWeb => $oldLinkWeb,
      oldTopic => $oldLinkTopic,
      newWeb => $newLinkWeb,
      newTopic => $newLinkTopic,
      fullPaths => 0,
      noautolink => 1,
      in_pre => 0,
      in_noautolink => 0,
      in_literal => 0
  };

  my $text =
    $renderer->forEachLine( $topicObject->text(), \&Foswiki::UI::Rename::_replaceTopicReferences, $rewriteLinkOptions );
  $topicObject->text($text);
  $topicObject->save( minor => 1 );
}

sub _handleRESTWebs {

  # $filter
  #  - 'user' == only user webs (hide hidden once, e.g. _empty)
  #  - 'public' == filter all public webs
  #  - 'allowed' == exclude all webs the current user can't read
  my @webs = Foswiki::Func::getListOfWebs( "user,public,allowed" );
  return to_json(\@webs);
}

sub _handleRESTWebTopics {
  my ( %session, undef, undef, $response ) = @_;
  my $request = Foswiki::Func::getRequestObject();
  my $web = $request->param("webname");

  die unless $web;

  my @webTopics = ();
  if( Foswiki::Func::webExists( $web ) ) {
    @webTopics = Foswiki::Func::getTopicList( $web );
  }
  # filter topic names and build full-qualified object
  # webTopic = { title: 'Sample Web Name', name: 'SampleWebName', web: 'Processes' }
  my @filteredWebTopics = ();
  foreach(@webTopics) {
    my %webTopic;
    $webTopic{name} = $_;
    $webTopic{web} = $web;

    if( Foswiki::Func::checkAccessPermission( "VIEW", $session{user}, undef, $webTopic{name}, $webTopic{web} ) ) {
      my ($topicMeta, $text) = Foswiki::Func::readTopic($webTopic{web}, $webTopic{name});
      if( $topicMeta->get( 'FIELD', 'TopicTitle' ) ) {
        $webTopic{title} = $topicMeta->get( 'FIELD', 'TopicTitle' )->{value};
      }else{
        $webTopic{title} = $webTopic{name};
      }
    }

    push @filteredWebTopics, {%webTopic};
  }

  return to_json(\@filteredWebTopics);
}

1;