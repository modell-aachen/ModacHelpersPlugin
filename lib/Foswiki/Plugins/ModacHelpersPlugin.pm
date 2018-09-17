package Foswiki::Plugins::ModacHelpersPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::UI::Rename;
use Foswiki::Form;
use JSON;
use Foswiki::AccessControlException;
use Scalar::Util qw(looks_like_number);

our $VERSION = "1.0";
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'This plugin provides several helper functions.';
our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {

  if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
  } else {
    return 0;
  }

  Foswiki::Func::registerRESTHandler('webs', \&_handleRESTWebs,
    authenticate  => 1,
    validate => 0,
    http_allow    => 'GET',
    description   => "Handler to fetch all Web's for current user"
  );

  Foswiki::Func::registerRESTHandler('topics', \&_handleRESTWebTopics,
    authenticate  => 1,
    validate => 0,
    http_allow    => 'GET',
    description   => "Handler to fetch all Topics for a given web name"
  );

  Foswiki::Func::registerRESTHandler('moveTopicToTrash', \&_handleRESTmoveTopicToTrash,
    authenticate  => 1,
    validate => 0,
    http_allow    => 'POST',
    description   => "Handler to move a topic to trash"
  );

  return 1;
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
  my ( $session ) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my $limit = $request->param("limit") || 10;
  my $page = $request->param("page") || 0;
  my $term = $request->param("term");
  my $json = JSON->new->utf8;

  my $meta = Foswiki::Meta->new($session);
  my @hideWebs = _getHideWebs($meta);
  my $webFilter = '-web:(' .join(' OR ', @hideWebs) .')';

  my @webs = ();
  my $solr = Foswiki::Plugins::SolrPlugin->getSearcher();
  my $query = "type:topic";
  $query .= " AND web:*$term*" if $term;
  $query .= " AND $webFilter";

  my %params = (
    "fl" => 'web',
    "facet" => "true",
    "facet.field" => "web",
    "facet.method" => "enum",
    "facet.limit" => $limit,
    "facet.offset" => $page * $limit,
    "facet.sort" => "index",
    "facet.zeros" => "false"
  );

  my $wikiUser = Foswiki::Func::getWikiName();
  unless (Foswiki::Func::isAnAdmin($wikiUser)) { # add ACLs
      push @{$params{fq}}, " (access_granted:$wikiUser OR access_granted:all)"
  }

  my $results = $solr->solrSearch($query, \%params);
  my $content = $results->raw_response;
  $content = $json->decode($content->{_content});
  my %webHash = @{$content->{facet_counts}->{facet_fields}->{web}};
  my @webFacets = keys %webHash;

  my %webMap = _getWebMapping($meta, \@webFacets);
  foreach my $web (sort @webFacets) {
    push @webs, { id => $web, text => $webMap{$web} || $web};
  }

  return to_json({results => \@webs});
}

sub _getHideWebs {
  my ($meta) = @_;
  my $hideWebsPref = $meta->expandMacros("%MODAC_HIDEWEBS%");
  my @hideWebs = split(/\|/,$hideWebsPref);
  return @hideWebs;
}

sub _getWebMapping {
  my ($meta, $webFacets) = @_;

  my $webMappginPref = $meta->expandMacros("%MODAC_WEBMAPPINGS{default=\"\"}%");
  my %webMap = map {$_ =~ /^(.*)=(.*)$/, $1=>$2} split(/\s*,\s*/, $webMappginPref);
  return %webMap;
}

sub _handleRESTWebTopics {
  my ( $session ) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my @websParam = $request->multi_param("web");
  my $limit = $request->param("limit") || 10;
  my $page = $request->param("page") || 0;
  my $term = $request->param("term");
  my $json = JSON->new->utf8;
  # if only one element is given try to split by comma
  if( scalar @websParam == 1 ) {
    @websParam = split(/,/, $websParam[0]);
  }
  @websParam = grep{ Foswiki::Func::isValidWebName($_) } @websParam;
  # prepare web restriction query
  my $webRestrictionQuery = "";
  $webRestrictionQuery = 'web:(' .join(' OR ', @websParam) .')' if scalar @websParam > 0;

  my $meta = Foswiki::Meta->new($session);
  my @hideWebs = _getHideWebs($meta);
  my $webFilter = '-web:(' .join(' OR ', @hideWebs) .')' if scalar @hideWebs > 0;

  my @invalidTopics = (
    'WebHome',
    'WebActions',
    'WebTopicList',
    'WebChanges',
    'WebSearch',
    'WebPreferences',
    '*FormManager',
    '*Template',
    '*ExtraField',
    'AllTasks'
  );
  my $topicFilter = '-topic:(' .join(' OR ', @invalidTopics) .')';
  my $technicalTopicFilter = '-preference_TechnicalTopic_s:1';

  my @webTopics = ();
  my $solr = Foswiki::Plugins::SolrPlugin->getSearcher();
  my $query = "type:topic";
  $query .= " AND title:*$term*" if $term;
  $query .= " AND $webRestrictionQuery" if $webRestrictionQuery;
  $query .= " AND $webFilter" if $webFilter;
  $query .= " AND $topicFilter AND $technicalTopicFilter";

  my %params = (
    "rows" => $limit,
    "start" => $page * $limit,
    "fl" => 'web,topic,webtopic,title,preference*',
    "sort" => 'title asc'
  );

  my $wikiUser = Foswiki::Func::getWikiName();
  unless (Foswiki::Func::isAnAdmin($wikiUser)) { # add ACLs
      push @{$params{fq}}, " (access_granted:$wikiUser OR access_granted:all)"
  }

  my $results = $solr->solrSearch($query, \%params);
  my $content = $results->raw_response;
  $content = $json->decode($content->{_content});
  @webTopics = @{$content->{response}->{docs}};

  # build full-qualified object
  # webTopic = { title: 'Sample Web Name', name: 'SampleWebName', web: 'Processes' }
  my @filteredWebTopics = ();
  foreach my $topic (@webTopics) {
    my %topic = %{$topic};
    my %webTopic;
    $webTopic{id} = $topic{webtopic};
    $webTopic{web} = $topic{web};
    $webTopic{text} = $topic{title};

    push @filteredWebTopics, {%webTopic};
  }

  return to_json({results => \@filteredWebTopics});
}

# Returns a list of FieldDefinitions, which are mandatory, but have no value.
# Each item is amended by a 'mapped_title' field, containing a display value.
sub getNonSatisfiedFormFields {
    my ($meta) = @_;
    return () unless $meta;

    my $form = $meta->get('FORM');
    return () unless $form;
    my $formName = $form->{name};
    return () unless $formName;

    my $formDef = new Foswiki::Form($meta->session(), $meta->web(), $formName);
    return () unless $formDef;

    my $mappings; # lazy loaded

    my @unsatisfied;
    foreach my $field (@{$formDef->getFields}) {
        my $metadata = $meta->get('FIELD', $field->{name});
        next if defined $metadata && defined $metadata->{value} && $metadata->{value} ne '';

        my $fieldDef = $formDef->getField($field->{name});
        next unless $fieldDef->isMandatory();

        $mappings = getDocumentFormTableMappings() unless defined $mappings;

        $fieldDef->{mapped_title} = $mappings->{$field->{name}};
        $fieldDef->{mapped_title} = $field->{description} unless defined $fieldDef->{mapped_title} && $fieldDef->{mapped_title} ne '';
        $fieldDef->{mapped_title} = $field->{name} unless defined $fieldDef->{mapped_title} && $fieldDef->{mapped_title} ne '';

        push @unsatisfied, $fieldDef;
    }
    return @unsatisfied;
}

sub getDocumentFormTableMappings {
    Foswiki::Func::loadTemplate('DocumentFormTable');
    my $modacformtable_mappings = Foswiki::Func::expandTemplate('modacformtable_mappings');
    $modacformtable_mappings = Foswiki::Func::expandCommonVariables($modacformtable_mappings);
    $modacformtable_mappings =~ s#^\s+##;
    $modacformtable_mappings =~ s#\s+$##;
    my @parts = split(/\s*,\s*/, $modacformtable_mappings);
    return { map{ split(/=/, $_, 2) } @parts };
}

sub deleteWeb {
    my ($web) = @_;
    _deleteWebOrTopic($web, undef);
    _deleteSolrEntriesByQuery("web: \"$web\"");
    Foswiki::Plugins::TasksAPIPlugin::deleteAllTasksForWeb( $web );
    _updateWebCache($web);
}

sub deleteTopic {
    my ($webTopic) = @_;

    if( $webTopic =~ m/\// ) {
      die "webTopic: $webTopic needs to be seperated by dot (.)";
    }

    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $webTopic);

    _deleteWebOrTopic($web, $topic);
    _deleteSolrEntriesByQuery("web: \"$web\" topic: \"$topic\"");
    Foswiki::Plugins::TasksAPIPlugin::deleteAllTasksForTopic( $webTopic );
    _updateWebCache($web);
}

sub _updateWebCache {
    my ($web) = @_;
    Foswiki::Plugins::DBCachePlugin::updateCache($web);
}

sub _deleteWebOrTopic {
    my ($normalizedWeb, $normalizedTopic)  = @_;
    my $cuid = Foswiki::Func::getCanonicalUserID();
    my $plainFileStore = Foswiki::Store::PlainFile->new();
    my $meta = Foswiki::Meta->load( $Foswiki::Plugins::SESSION, $normalizedWeb, $normalizedTopic);

    $plainFileStore->remove($cuid, $meta);
    $plainFileStore->finish();
}

sub _deleteSolrEntriesByQuery {
    my ($query) = @_;
    my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer();
    $indexer->deleteByQuery( $query );
    $indexer->commit(1);
}

sub _handleRESTmoveTopicToTrash {
  my $request = Foswiki::Func::getRequestObject();
  my $topicId = $request->param("topicId");

  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName("", $topicId);
  Foswiki::Func::moveTopic($web, $topic, $Foswiki::cfg{TrashWebName}, $topic.time());
}

1;