package Foswiki::Plugins::ModacHelpersPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins;
use Foswiki::UI::Rename;
use Foswiki::Form;

our $VERSION = "1.0";
our $RELEASE = "1.0";
our $SHORTDESCRIPTION = 'This plugin provides several helper functions.';
our $NO_PREFS_IN_TOPIC = 1;

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
