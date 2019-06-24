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

our $SITEPREFS = {
    MODAC_TEMPWEB => 'ModacTesting',
};

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

  push @{$params{fq}}, $solr->getACLFilters();

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
  my $hideWebsPref = $meta->expandMacros("%MODAC_HIDEWEBS{encode=\"none\"}%");
  my @hideWebs = split(/\|/,$hideWebsPref);
  return @hideWebs;
}

sub _getWebMapping {
  my ($meta, $webFacets) = @_;

  my $webMappingPref = $meta->expandMacros("%MODAC_WEBMAPPINGS{encode=\"none\"}%");
  my %webMap = map {$_ =~ /^(.*)=(.*)$/, $1=>$2} split(/\s*,\s*/, $webMappingPref);
  return %webMap;
}

sub getLinkToTopicHistory {
  my ($webtopic, $revision) = @_;

  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName("", $webtopic);
  my $instanceId = Foswiki::Func::getPreferencesValue("INSTANCE_ID",$web);
  my $historyUrl;
  if($instanceId) {
      $historyUrl = Foswiki::Func::getScriptUrl($Foswiki::cfg{SystemWebName}, 'WorkflowAppOverview', 'view')."#/history/$instanceId/$webtopic/$revision";
  } else {
      $historyUrl = Foswiki::Func::getScriptUrl($web, $topic, 'view', 'rev' => $revision)
  }

  return $historyUrl;
}

sub _handleRESTWebTopics {
  my ( $session ) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my @websParam = $request->multi_param("web");
  my $currentWeb = $request->param("current_web");
  my @websFilterParam = $request->multi_param("web_filter");
  my $optionForNoTopicParent = $request->param('option_for_notopicparent');
  my $limit = $request->param("limit") || 10;
  my $page = $request->param("page") || 0;
  my $term = $request->param("term");
  my $caseSensitive = Foswiki::Func::isTrue($request->param("case_sensitive"));
  my $noDiscussions = Foswiki::Func::isTrue($request->param("no_discussions"));
  my $json = JSON->new->utf8;
  # if only one element is given try to split by comma
  if( scalar @websParam == 1 ) {
    @websParam = split(/,/, $websParam[0]);
  }
  @websParam = grep{ Foswiki::Func::isValidWebName($_) } @websParam;
  # prepare web restriction query
  my $webRestrictionQuery = "";
  $webRestrictionQuery = 'web:(' .join(' OR ', @websParam) .')' if scalar @websParam > 0;

  my $webFilter;
  my @hideWebs;
  if(scalar @websFilterParam) {
      @hideWebs = grep{ Foswiki::Func::isValidWebName($_) } @websFilterParam;
  } else {
      my $meta = Foswiki::Meta->new($session);
      @hideWebs = _getHideWebs($meta);
  }
  $webFilter = '-web:(' .join(' OR ', @hideWebs) .')' if scalar @hideWebs > 0;

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
  my $contentTemplateFilter = '-preference_IS_CONTENT_TEMPLATE_s:1';

  my $termQuery;
  if($term) {
      my @terms = split(/(?:\s|\/)+/, $term); # Slashes cause a lot of trouble, since they indicate a regex. Thus they must be escaped with quotes, however, since they will be filtered anyway it is simpler to just nil them.
      @terms = map{ $_ =~ s#([][\\+-:!(){}^~*?"&|])#\\$1#gr } @terms;
      @terms = map{ $_ =~ m#/# ? "\"$_\"" : $_ } @terms;
      my $termsRegular = join(' AND ', @terms);
      $termsRegular = "($termsRegular)" if scalar @terms > 1;
      my $termsAsterisk = join(' AND ', map{ "(*$_* OR $_)" } @terms);
      $termsAsterisk = "($termsAsterisk)" if scalar @terms > 1;

      my @termQueryParts = (
          'title' . ($caseSensitive ? '' : '_search') . ":$termsRegular",
          "title:\"$term\"",
          'topic' . ($caseSensitive ? '' : '_search') . ":$termsAsterisk",
          "topic:\"$term\"",
          'webtopic' . ($caseSensitive ? '' : '_search') . ":$termsAsterisk",
          "webtopic:\"$term\"",
          "field_DocumentNumber_search:($termsAsterisk)",
      );
      if(!$caseSensitive) {
          push @termQueryParts, "title_ngram_search:\"$term\"",
      }
      $termQuery = '(' . join(' OR ', @termQueryParts) . ')';
  }

  my @webTopics = ();
  my $solr = Foswiki::Plugins::SolrPlugin->getSearcher();
  my $query = "type:topic";
  $query .= " AND $termQuery" if $termQuery;
  $query .= " AND $webRestrictionQuery" if $webRestrictionQuery;
  $query .= " AND $webFilter" if $webFilter;
  $query .= " AND $topicFilter AND $technicalTopicFilter AND $contentTemplateFilter";
  if($noDiscussions) {
      my $suffix = Foswiki::Func::expandCommonVariables("%WORKFLOWSUFFIX%");
      $query .= " AND -topic:*$suffix";
  }

  my %params = (
    "rows" => $limit,
    "start" => $page * $limit,
    "fl" => 'web,topic,webtopic,title,preference*,field_DocumentNumber_s',
    "sort" => 'title asc'
  );

  push @{$params{fq}}, $solr->getACLFilters();

  my $results = $solr->solrSearch($query, \%params);
  my $content = $results->raw_response;
  $content = $json->decode($content->{_content});
  @webTopics = @{$content->{response}->{docs}};

  # build full-qualified object
  # webTopic = { title: 'Sample Web Name', name: 'SampleWebName', web: 'Processes' }
  my @filteredWebTopics = ();
  foreach my $topic (@webTopics) {
    my %topic = %{$topic};
    my $documentNumber = '';
    if($topic{field_DocumentNumber_s}) {
      $documentNumber = $topic{field_DocumentNumber_s} . ' ';
    }
    my $webTopicText = $documentNumber . $topic{title};
    my %webTopic;
    $webTopic{id} = $topic{webtopic};
    $webTopic{web} = $topic{web};
    $webTopic{text} =  $webTopicText;
    $webTopic{DocumentNumber} = $topic{field_DocumentNumber_s};

    push @filteredWebTopics, {%webTopic};
  }

  if(!$page && !$term && $currentWeb && $optionForNoTopicParent) {
      my $webHome = {
          id => $Foswiki::cfg{HomeTopicName},
          web => $currentWeb,
          text => $session->i18n->maketext( "No topic parent" ),
      };
      unshift @filteredWebTopics, $webHome;
  }

  return to_json({results => \@filteredWebTopics, count => $content->{response}->{numFound}});
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
        next unless $fieldDef && $fieldDef->isMandatory();

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

sub getTempWebName {
    my $tempWebName = Foswiki::Func::getPreferencesValue('MODAC_TEMPWEB');
    if(! $tempWebName) {
        die "Modac temp web is not defined";
    }
    if( ! Foswiki::Func::webExists( $tempWebName ) ) {
        local $Foswiki::Plugins::SESSION = Foswiki->new('BaseUserMapping_333', undef, undef);
        Foswiki::Func::createWeb( $tempWebName );
        my ($meta, $text) = Foswiki::Func::readTopic($tempWebName, "WebPreferences");
        $text .= "\n   * Set ALLOWWEBCHANGE = AdminGroup\n";
        Foswiki::Func::saveTopic($tempWebName, "WebPreferences", $meta, $text);
    }
    return $tempWebName;
}

sub makeValidWikiWord {
    my ($text) = @_;
    return $text unless $text;
    $text =~ s/[^a-zA-Z0-9]//g;
    $text =~ s/^\d+//g;
    $text =~ s/\b(\w)/uc($1)/ge;
    return $text;
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

sub getDeletedImagePlaceholder {
    my $lang = $Foswiki::Plugins::SESSION->i18n()->language();
    $lang = 'en' unless $lang eq 'de';

    my $attachment = "Keep_tidy_ask_$lang.svg";
    my $redirectWeb = $Foswiki::cfg{SystemWebName};
    my $redirectTopic = 'ModacHelpersPlugin';

    return ($redirectWeb, $redirectTopic, $attachment);
}

sub getRmsCredentials {
    my $rms = $Foswiki::cfg{Plugins}{ModacLogHelperPlugin}{rms} || 'rms.modac.eu';

    my ($user, $key);
    if($Foswiki::cfg{ExtensionsRepositories} =~ m#\Q$rms\E[^,]*,[^,]*,([^,]+),([^,]+)\)#) {
        $user = $1;
        $key = $2;
    }

    return $user, $key;
}

1;
