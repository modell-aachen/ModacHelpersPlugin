package Foswiki::Plugins::ModacHelpersPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::UI::Rename;
use Foswiki::Form;
use JSON;
use Foswiki::AccessControlException;

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
  # $filter
  #  - 'user' == only user webs (hide hidden ones, e.g. _empty)
  #  - 'public' == filter all public webs
  #  - 'allowed' == exclude all webs the current user can't read
  my @webs = Foswiki::Func::getListOfWebs( "user,public,allowed" );
  my @invalidWebs = (
    '^System$',
    '^System/',
    '^Trash$',
    '^OUTemplate$'
  );

  my @filteredWebs = grep{ _isValidItem($_, @invalidWebs) } @webs;

  return to_json(\@filteredWebs);
}

sub _handleRESTWebTopics {
  my $request = Foswiki::Func::getRequestObject();
  my @websParam = $request->multi_param("webname");
  my $rowsParam = $request->param("rows") || 9999;
  my $json = JSON->new->utf8;

  die unless @websParam;
  @websParam = grep{ Foswiki::Func::isValidWebName($_) } @websParam;
  # prepare web restriction query
  my $webRestrictionQuery = "";
  foreach my $web (@websParam) {
    $webRestrictionQuery .= ($webRestrictionQuery ne "")?' OR ':'';
    $webRestrictionQuery .= "web:$web";
  }

  my @webTopics = ();
  my $solr = Foswiki::Plugins::SolrPlugin->getSearcher();
  my $query = "type:topic AND ($webRestrictionQuery)";
  my %params = (
    rows => $rowsParam,
    fl => 'web,topic,webtopic,title,preference*',
    sort => 'title asc'
  );
  my $wikiUser = Foswiki::Func::getWikiName();
  unless (Foswiki::Func::isAnAdmin($wikiUser)) { # add ACLs
      push @{$params{fq}}, " (access_granted:$wikiUser OR access_granted:all)"
  }

  my $results = $solr->solrSearch($query, \%params);
  my $content = $results->raw_response;
  $content = $json->decode($content->{_content});
  @webTopics = @{$content->{response}->{docs}};


  # filter topic names and build full-qualified object
  # webTopic = { title: 'Sample Web Name', name: 'SampleWebName', web: 'Processes' }
  my @invalidTopics = (
      '^WebHome$',
      '^WebActions$',
      '^WebTopicList$',
      '^WebChanges$',
      '^WebSearch$',
      '^WebPreferences$',
      '^FormManager$',
      'Template$',
      'ExtraField$'
  );
  my @filteredWebTopics = ();
  foreach my $topic (@webTopics) {
    my %topic = %{$topic};
    my $isValidTopic = _isValidItem( $topic{topic}, @invalidTopics );

    if( !$isValidTopic || (grep(/^TechnicalTopic$/, @{$topic{preference}}) && $topic{preference_TechnicalTopic_s} eq "1" ) ) {
      next; # skip this topic per definition
    }

    my %webTopic;
    $webTopic{name} = $topic{topic};
    $webTopic{web} = $topic{web};
    $webTopic{title} = $topic{title};

    push @filteredWebTopics, {%webTopic};
  }

  return to_json(\@filteredWebTopics);
}

sub _isValidItem() {
  my ($item, @filterArray ) = @_;
  my $isValid = 1;

  foreach(@filterArray) {
    $isValid &= !($item =~ m/$_/);
  }

  return $isValid;
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

1;