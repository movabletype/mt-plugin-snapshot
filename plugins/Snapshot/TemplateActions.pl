
# TemplateActions.pl
# TemplateActions plugin for Movable Type
# by Kevin Shay

use strict;
package MT::Plugin::TemplateActions;

use vars qw( $VERSION );
$VERSION = '1.0';

use base qw( MT::Plugin );

require MT::Plugin;
require MT;
my $plugin = MT::Plugin::TemplateActions->new({
	name => "TemplateActions",
	description => 'Adds the missing Plugin Actions section to the Edit Template screen.',
	author_name => 'Kevin Shay',
	author_link => 'http://www.staggernation.com/mtplugins/',
	callbacks => {
		'MT::App::CMS::AppTemplateSource.edit_template' => \&fix_it
	}
});

sub fix_it {
	my ($cb, $app, $template) = @_;
	my $old = '</div>\s+<TMPL_INCLUDE NAME="footer\.tmpl">';
	my $new = <<"TMPL";
<TMPL_IF NAME=PLUGIN_ACTION_LOOP>
<div class="box" id="plugin-actions-box">
<h4><MT_TRANS phrase="Plugin Actions"></h4>
<div class="inner">
<ul>
<TMPL_LOOP NAME=PLUGIN_ACTION_LOOP>
<li><a href="<TMPL_VAR NAME=PAGE>;from=edit_template;id=<TMPL_VAR NAME=ID>;blog_id=<TMPL_VAR NAME=BLOG_ID>"><TMPL_VAR NAME=LINK_TEXT></a></li>
</TMPL_LOOP>
</ul>
</div>
</div>
</TMPL_IF>

</div>

<TMPL_INCLUDE NAME="footer.tmpl">
TMPL
	$$template =~ s/$old/$new/;
}

1;
