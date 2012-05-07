# Plugin for Foswiki
#
# Copyright (C) 2008 Oliver Krueger <oliver@wiki-one.net>
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# This piece of software is licensed under the GPLv2.

package Foswiki::Plugins::AutoTemplatePlugin;

use strict;
use warnings;

our $VERSION = '$Rev: 5221 $';
our $RELEASE = '2.01';
our $SHORTDESCRIPTION = 'Automatically sets VIEW_TEMPLATE and EDIT_TEMPLATE';
our $NO_PREFS_IN_TOPIC = 1;
our $debug;
our $isEditAction;

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning( "Version mismatch between AutoTemplatePlugin and Plugins.pm" );
        return 0;
    }

    # get configuration
    my $modeList = $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{Mode} || "rules, exist";
    my $override = $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{Override} || 0;
    $debug = $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{Debug} || 0;

    # is this an edit action?
    $isEditAction   = Foswiki::Func::getContext()->{edit};
    my $templateVar = $isEditAction?'EDIT_TEMPLATE':'VIEW_TEMPLATE';

    # back off if there is a view template already and we are not in override mode
    my $currentTemplate = Foswiki::Func::getPreferencesValue($templateVar);
    return 1 if $currentTemplate && !$override;

    # check if this is a new topic and - if so - try to derive the templateName from
    # the WebTopicEditTemplate
    # SMELL: templatetopic and formtemplate from url params come into play here as well
    if (!Foswiki::Func::topicExists($web, $topic)) {
      if (Foswiki::Func::topicExists($web, 'WebTopicEditTemplate')) {
        $topic = 'WebTopicEditTemplate';
      } else {
        return 1;
      }
    }

    # get it
    my $templateName = "";
    foreach my $mode (split(/\s*,\s*/, $modeList)) {
      if ( $mode eq "section" ) {
        $templateName = _getTemplateFromSectionInclude( $web, $topic );
      } elsif ( $mode eq "exist" ) {
        $templateName = _getTemplateFromTemplateExistence( $web, $topic );
      } elsif ( $mode eq "rules" ) {
        $templateName = _getTemplateFromRules( $web, $topic );
      }
      last if $templateName;
    }

    # only set the view template if there is anything to set
    return 1 unless $templateName;

    # in edit mode, try to read the template to check if it exists
    if ($isEditAction && !Foswiki::Func::readTemplate($templateName)) {
      writeDebug("edit tempalte not found");
      return 1;
    }

    # do it
    if ($debug) {
      if ( $currentTemplate ) {
        if ( $override ) {
          writeDebug("$templateVar already set, overriding with: $templateName");
        } else {
          writeDebug("$templateVar not changed/set");
        }
      } else {
        writeDebug("$templateVar set to: $templateName");
      }
    }
    if ($Foswiki::Plugins::VERSION >= 2.1 ) {
      Foswiki::Func::setPreferencesValue($templateVar, $templateName);
    } else {
      $Foswiki::Plugins::SESSION->{prefs}->pushPreferenceValues( 'SESSION', { $templateVar => $templateName } );
    }

    # Plugin correctly initialized
    return 1;
}

sub _getFormName {
    my ($web, $topic) = @_;

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );

    my $form;
    $form = $meta->get("FORM") if $meta;
    $form = $form->{"name"} if $form;

    return $form;
}

sub _getTemplateFromSectionInclude {
    my ($web, $topic) = @_;

    my $formName = _getFormName($web, $topic);
    return unless $formName;

    writeDebug("called _getTemplateFromSectionInclude($formName, $topic, $web)");

    my ($formweb, $formtopic) = Foswiki::Func::normalizeWebTopicName($web, $formName);

    # SMELL: This can be done much faster, if the formdefinition topic is read directly
    my $sectionName = $isEditAction?'edittemplate':'viewtemplate';
    my $templateName = "%INCLUDE{ \"$formweb.$formtopic\" section=\"$sectionName\"}%";
    $templateName = Foswiki::Func::expandCommonVariables( $templateName, $topic, $web );

    return $templateName;
}

# replaces Web.MyForm with Web.MyViewTemplate and returns Web.MyViewTemplate if it exists otherwise nothing
sub _getTemplateFromTemplateExistence {
    my ($web, $topic) = @_;

    my $formName = _getFormName($web, $topic);
    return unless $formName;

    writeDebug("called _getTemplateFromTemplateExistence($formName, $topic, $web)");
    my ($templateWeb, $templateTopic) = Foswiki::Func::normalizeWebTopicName($web, $formName);

    $templateWeb =~ s/\//\./go;
    my $templateName = $templateWeb.'.'.$templateTopic;
    $templateName =~ s/Form$//;
    $templateName .= $isEditAction?'Edit':'View';

    return $templateName;
}

sub _getTemplateFromRules {
    my ($web, $topic) = @_;

    writeDebug("called _getTemplateFromRules($web, $topic)");

    # read template rules from preferences
    my $rules = Foswiki::Func::getPreferencesValue(
      $isEditAction?'EDIT_TEMPLATE_RULES':'VIEW_TEMPLATE_RULES');

    if ($rules) {
      $rules =~ s/^\s+//;
      $rules =~ s/\s+$//;

      # check full qualified topic name first
      foreach my $rule (split(/\s*,\s*/, $rules)) {
        if ($rule =~ /^(.*?)\s*=>\s*(.*?)$/) {
          my $pattern = $1;
          my $template = $2;
          return $template if "$web.$topic" =~ /^($pattern)$/;
        }
      }
      # check topic name only
      foreach my $rule (split(/\s*,\s*/, $rules)) {
        if ($rule =~ /^(.*?)\s*=>\s*(.*?)$/) {
          my $pattern = $1;
          my $template = $2;
          return $template if $topic =~ /^($pattern)$/ ;
        }
      }
    }

    # read template rules from config
    $rules = $isEditAction?
      $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{EditTemplateRules}:
      $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{ViewTemplateRules};

    if($rules) {
      # check full qualified topic name first
      foreach my $pattern (keys %$rules) {
        return $rules->{$pattern} if "$web.$topic" =~ /^($pattern)$/;
      }
      # check topic name only
      foreach my $pattern (keys %$rules) {
        return $rules->{$pattern} if $topic =~ /^($pattern)$/;
      }
    }

    return;
}

sub writeDebug {
    return unless $debug;
    #Foswiki::Func::writeDebug("- AutoTemplatePlugin - $_[0]");
    print STDERR "- AutoTemplatePlugin - $_[0]\n";
}


1;
