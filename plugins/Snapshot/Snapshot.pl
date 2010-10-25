##############################################################################
# Copyright © 2009 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details.  You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

package MT::Plugin::Snapshot;
use strict;
use Data::Dumper;

use vars qw( $VERSION );
$VERSION = '1.6';

use base qw( MT::Plugin );

require MT::Plugin;
require MT;

my $plugin;
$plugin = MT::Plugin::Snapshot->new({
    'name' => 'Snapshot',
    'id' => 'Snapshot',
    'author_name' => 'Six Apart',
    'description' => 'Save and revert to snapshots of entry, page, and template objects.',
    'version' => $VERSION,
    'schema_version' => '0.411',
});
MT->add_plugin($plugin);
sub init_registry {
    my $component = shift;
    my $reg = {
        key => 'snapshot',
        object_types => {
            snapshot => 'MT::Snapshot',
        },
        settings => new MT::PluginSettings([
            ['auto_snap_entry'],
            ['auto_snap_template'],
            ['keep_n_entry'],
            ['keep_n_template']
        ]),
        config_template => 'config.tmpl',
        callbacks => {
            'cms_post_save.entry' => sub { post_save('MT::Entry', @_) },
            'api_post_save.entry' => sub { post_save('MT::Entry', @_) },
            'cms_post_save.template' => sub { post_save('MT::Template', @_) },
            'MT::Entry::post_remove' => sub { post_remove('MT::Entry', @_) },
            'MT::Template::post_remove' => sub { post_remove('MT::Template', @_) },
        },
        applications => {
            cms => {
                page_actions => {
                    entry => {
                        snap_entry => {
                            label => 'Take a Snapshot of Entry',
                            code => sub { snap_objects('MT::Entry', @_) },
                        },
                        snap_list_entry => {
                            label => 'View Snapshots',
                            code => sub { snap_list('MT::Entry', @_) },
                        },
                    },
                    page => {
                        snap_page => {
                            label => 'Take a Snapshot of Page',
                            code => sub { snap_objects('MT::Page', @_) },
                        },
                        snap_list_page => {
                            label => 'View Snapshots',
                            code => sub { snap_list('MT::Page', @_) },
                        },
                    },
                    template => {
                        snap_template => {
                            label => 'Take a Snapshot of Template',
                            code => sub { snap_objects('MT::Template', @_) },
                        },
                        snap_list_template => {
                            label => 'View Snapshots',
                            code => sub { snap_list('MT::Template', @_) },
                        },
                    },
                },
                list_actions => {
                    entry => {
                        snap_entries => {
                            label => 'Snapshot Entries',
                            code => sub { snap_objects('MT::Entry', @_) },
                        },
                    },
                    page => {
                        snap_pages => {
                            label => 'Snapshot Pages',
                            code => sub { snap_objects('MT::Page', @_) },
                        },
                    },
                    template => {
                        snap_templates => {
                            label => 'Snapshot Templates',
                            code => sub { snap_objects('MT::Template', @_) },
                        },
                    },
                },
                methods => {
                    snap_entry => sub { snap_objects('MT::Entry', @_) },
                    snap_list_entry => sub { snap_list('MT::Entry', @_) },
                    snap_page => sub { snap_objects('MT::Page', @_) },
                    snap_list_page => sub { snap_list('MT::Page', @_) },
                    snap_template => sub { snap_objects('MT::Template', @_) },
                    snap_list_template => sub { snap_list('MT::Template', @_) },
                    snap_view => sub { snap_view(@_) },
                    snap_save => sub { snap_save(@_) },
                    snap_compare => sub { snap_compare(@_) },
                    snap_revert => sub { snap_revert(@_) },
                    snap_do_revert => sub { snap_do_revert(@_) },
                    snap_delete => sub { snap_delete(@_) },
                    snap_keep => sub { snap_keep(@_) },
                },
            }
        },
    };
    $component->registry($reg);
}

my $view_fields = {
    'MT::Entry' => [
        [ 'title', 'Entry Title' ],
        [ 'text', 'Entry Body', 'text' ],
        [ 'text_more', 'Extended Entry', 'text' ],
        [ 'excerpt', 'Excerpt' ],
        [ 'keywords', 'Keywords' ],
        [ 'modified_on',  'Last Modified', 'date' ],
        [ 'basename', 'Basename' ]
    ],
    'MT::Page' => [
        [ 'title', 'Page Title' ],
        [ 'text', 'Page Body', 'text' ],
        [ 'text_more', 'Extended Page', 'text' ],
        [ 'excerpt', 'Excerpt' ],
        [ 'keywords', 'Keywords' ],
        [ 'modified_on',  'Last Modified', 'date' ],
        [ 'basename', 'Filename' ]
    ],
    'MT::Template' => [
        [ 'name', 'Template Name' ],
        [ 'outfile', 'Output File' ],
        [ 'text', 'Template Body', 'code' ],
        [ 'linked_file', 'Linked File' ],
        [ 'rebuild_me', 'Rebuild automatically when building index templates', 'boolean' ],
        [ 'build_dynamic', 'Enable dynamic building', 'boolean' ]
    ]
};

sub post_save {
    my ($class, $cb, $app, $obj, $original) = @_;
    my $scope = $obj->blog_id ? 'blog:' . $obj->blog_id : 'system';
    my $settings = $plugin->get_config_hash($scope);
    my $type = lc($class);
    $type =~ s/^mt:://;
    return 1 unless ($settings->{"auto_snap_$type"});
    require MT::Snapshot;
    eval "require $class;";
    my $snap = MT::Snapshot->new($obj);
    $snap->save || die $snap->errstr;
    if (my $keep_n = $settings->{"keep_n_$type"}) {
        my $terms = {
            'object_id' => $obj->id,
            'object_ds' => $obj->datasource,
            'keep' => 0
        };
        my $n = MT::Snapshot->count($terms);
        if ($n > $keep_n) {
            for my $snap (MT::Snapshot->load($terms, {
                    'sort' => 'created_on',
                    'direction' => 'descend',
                    'offset' => $keep_n })) {
                next if ($snap->keep);
                $snap->remove || die $snap->errstr;
            }
        }
    }
1 ;
}

sub post_remove {
    my ($class, $cb, $obj) = @_;
    require MT::Snapshot;
    eval "require $class;";
    my $terms = {
        'object_id' => $obj->id,
        'object_ds' => $obj->datasource,
    };
    for my $snap (MT::Snapshot->load($terms)) {
        $snap->remove || die $snap->errstr;
    }
}

sub snap_objects {
    my ($class, $app) = @_;
    (my @ids = $app->param('id')) || return $app->error('No IDs passed');
    require MT::Snapshot;
    eval "require $class;";
    my @objs = ();
    my $last_obj;
    my $last_snap;
    for my $id (@ids) {
        my $obj = $class->load($id) || return $app->error("$class object $id not found");
        my $snap = MT::Snapshot->new($obj);
        $snap->keep(1);
        $snap->save || die $snap->errstr;
        $last_obj = $obj;
        $last_snap = $snap;
    }
    my $param = {};
    if (scalar @ids == 1) {
        return $app->redirect($app->uri( 'mode' => 'snap_view', 'args' => {
            'id' => $last_snap->id, 'saved_added' => 1,
            'blog_id' => $app->param('blog_id')
        }));
    } else {
        ## Need hash to display list of links to "edit snapshot" and "view snapshots" for each template.
        # my @snap_ids;
        # for my $id (@ids) {
        #     my $snap = MT::Snapshot->load($id);
        #     push(@snap_ids, {
        #         'id' => $snap->id,
        #         'created_on' => display_ts($snap->created_on),
        #     });
        # }
        # $param->{'snap_ids'} = \@snap_ids;
        $param->{'action_snapped_multi'} = 1;
        $param->{'headline'} = "$param->{'parent_object_type'} Snapshots Created";
    }
    init_app_vars($app, "$param->{'parent_object_type'} Snapshot");
    $param->{'snap_ts'} = display_ts($last_snap->created_on);
    return $app->build_page('snap_done.tmpl', $param);
}

sub snap_list {
    my ($class, $app) = @_;
    my $id = $app->param('id') || return $app->error('No object ID passed');
    require MT::Snapshot;
    eval "require $class;";
    my $obj = $class->load($id);
    my $param = {};
    my $users = {};
    param_assign($app, undef, $obj, $param);
    for my $key (qw( deleted updated )) {
        $param->{$key} = $app->param($key);
    }
    init_app_vars($app, "$param->{'parent_object_type'} Snapshots");

    my $terms = {
        'object_id' => $obj->id,
        'object_ds' => $obj->datasource
    };
    my @snap_loop;
    for my $snap (MT->model('snapshot')->load($terms)) {
        push(@snap_loop, {
            'id' => $snap->id,
            'created_on' => display_ts($snap->created_on),
        });
    }
    $param->{'snap_loop'} = \@snap_loop;
    return $app->listing({
        type => 'snapshot',
        template => 'snap_list.tmpl',
        terms => $terms,
        args => {
            'sort' => 'created_on',
            'direction' => 'descend'
        },
        code => sub {
            my ($snap, $row) = @_;
            $row->{'created_on'} = display_ts($snap->created_on);
            if ($snap->created_by) {
                if ($users->{$snap->created_by} ||= MT->model('author')->load($snap->created_by)) {
                    $row->{'created_by'} = $snap->created_by;
                    $row->{'created_by_name'} = $users->{$snap->created_by}->name;
                }
            }
        },
        params => $param,
    });

}

sub snap_view {
    my ($app) = @_;
    my $id = $app->param('id') || return $app->error('No snapshot ID passed');
    require MT::Snapshot;
    my $snap = MT::Snapshot->load($id);
    my $obj = $snap->obj;
    my $fields = $view_fields->{ref($obj)}
        || [ keys %{$obj->column_values} ];
    my @field_loop = ();
    my $param = {};
    require MT::Util;
    for my $field (@$fields) {
        my ($col, $label, $type) = @$field;
        $label ||= $col;
        $type ||= '';
        my $value = $obj->column($col);
        if ($type eq 'boolean') {
            $value = $value ? 'On' : 'Off'
        } elsif ($type eq 'date') {
            $value = display_ts($value);
        } elsif (($type eq 'text')) {
            $value = convert_breaks($app, $value, $obj);
        } elsif ($type eq 'code') {
            $value = MT::Util::encode_html($value);
            $value = MT->apply_text_filters($value, ['__default__'], $app);
        }
        push(@field_loop, {
            'column' => $col,
            'label' => $label,
            'value' => $value
        });
    }
    $param->{'field_loop'} = \@field_loop;
    for my $key (qw( saved saved_added )) {
        $param->{$key} = 1 if ($app->param($key));
    }
    param_assign($app, $snap, $obj, $param);
    init_app_vars($app, "$param->{'parent_object_type'} Snapshot");
    return $app->build_page('snap_view.tmpl', $param);
}

sub convert_breaks {
    my ($app, $value, $obj) = @_;
    eval { $obj->convert_breaks }; return $value if ($@);
    require MT::Blog;
    my $blog = MT::Blog->load($obj->blog_id);
    my $convert_breaks = defined $obj->convert_breaks
        ? $obj->convert_breaks : $blog->convert_paras;
    if ($convert_breaks) {
        my $filters = $obj->text_filters;
        push @$filters, '__default__' unless @$filters;
        $value = MT->apply_text_filters($value, $filters, $app);
    }
    return $value;
}

sub snap_save {
    my ($app) = @_;
    my $id = $app->param('id') || return $app->error('No snapshot ID passed');
    require MT::Snapshot;
    my $snap = MT::Snapshot->load($id);
    $snap->title($app->param('title'));
    $snap->note($app->param('note'));
    $snap->save || return $app->error($snap->errstr);
    return $app->redirect($app->uri( 'mode' => 'snap_view', 'args' => {
        'id' => $snap->id, 'saved' => 1, 'blog_id' => $app->param('blog_id')
    }));
}

sub snap_compare {
    my ($app) = @_;
    require Algorithm::Diff;
    import Algorithm::Diff qw( sdiff );
    my $id = $app->param('id') || return $app->error('No snapshot ID passed');
    my $obj_id = $app->param('object_id') || return $app->error('No object ID passed');
    my $comp_id = $app->param('compare_id') || return $app->error('No comparison ID passed');
    require MT::Snapshot;
    my $orig_snap = MT::Snapshot->load($id);
    my $orig_obj = $orig_snap->obj;
    my $class = $orig_snap->object_class;
    eval "require $class;";
    my $new_obj;
    my $new_snap;
    if ($comp_id eq 'current') {
        $new_obj = $class->load($obj_id);
    } else {
        $new_snap = MT::Snapshot->load($comp_id);
        $new_obj = $new_snap->obj;
    }
    my $fields = $view_fields->{$class};
    my $param = {};
    my @field_loop = ();
    for my $field (@$fields) {
        my ($col, $label, $type) = @$field;
        $label ||= $col;
        $type ||= '';
        my ($val_a, $val_b);
        $val_a = $orig_obj->column($col);
        if ($comp_id eq 'current') {
            $val_b = $new_obj->$col;
        } else {
            $val_b = $new_obj->column($col);
        }
        if ($type eq 'boolean') {
            $val_a = $val_a ? 'On' : 'Off';
            $val_b = $val_b ? 'On' : 'Off';
        } elsif ($type eq 'date') {
            next; # what do we want to do here?
        } elsif (($type eq 'text')) {
            $val_a = convert_breaks($app, $val_a, $orig_obj);
            $val_b = convert_breaks($app, $val_b, $new_obj);
        } elsif ($type eq 'code') {
            $val_a = MT::Util::encode_html($val_a);
            $val_a = MT->apply_text_filters($val_a, ['__default__'], $app);
            $val_b = MT::Util::encode_html($val_b);
            $val_b = MT->apply_text_filters($val_b, ['__default__'], $app);
        }
        push(@field_loop, {
            'column' => $col,
            'label' => $label,
            'value' => html_compare($val_a, $val_b)
        });
    }
    $param->{'field_loop'} = \@field_loop;
    $param->{'snap_a'} = display_ts($orig_snap->created_on);
    $param->{'snap_a_id'} = $orig_snap->id;
    $param->{'snap_b'} = $new_snap ? display_ts($new_snap->created_on) : '';
    $param->{'snap_b_id'} = $new_snap? $new_snap->id : 0;
    param_assign($app, $orig_snap, $orig_obj, $param);
    init_app_vars($app, "$param->{'parent_object_type'} Snapshot Comparison");
    return $app->build_page('snap_compare.tmpl', $param);
}

sub snap_revert {
    my ($app) = @_;
    my $id = $app->param('id') || return $app->error('No snapshot ID passed');
    require MT::Snapshot;
    my $snap = MT::Snapshot->load($id);
    my $class = $snap->object_class;
    eval "require $class;";
    my $obj = $snap->obj;
    my $param = {};
    $param->{'id'} = $snap->id;
    param_assign($app, $snap, $obj, $param);
    init_app_vars($app, "Revert $param->{'parent_object_type'} to Snapshot");
    return $app->build_page('snap_revert_confirm.tmpl', $param);
}

sub snap_do_revert {
    my ($app) = @_;
    if ($app->param('cancel')) {
            # snap_list() expects "id" to be the object ID
        $app->param('id', $app->param('object_id'));
        return snap_list($app->param('class'), @_);
    }
    my $id = $app->param('id') || return $app->error('No snapshot ID passed');
    require MT::Snapshot;
    my $snap = MT::Snapshot->load($id);
    my $class = $snap->object_class;
    eval "require $class;";
    my $obj = $snap->obj;
    $obj->save || return $app->error("Couldn't save object");
    my $param = {};
    param_assign($app, $snap, $obj, $param);
    $param->{'action_reverted'} = 1;
    $param->{'headline'} = "$param->{'parent_object_type'} Reverted to Snapshot";
    init_app_vars($app, "$param->{'parent_object_type'} Reverted");
    return $app->build_page('snap_done.tmpl', $param);
}

sub snap_delete {
    my ($app) = @_;
    require MT::Snapshot;
    for my $id ($app->param('id')) {
        my $snap = MT::Snapshot->load($id);
        next unless $snap;
        $snap->remove;
    }
    if ($app->param('return_url')) {
        return $app->redirect($app->param('return_url') . '&blog_id=' . $app->param('blog_id'));
    }
    my $type = lc($app->param('parent_object_type'));
    return $app->redirect($app->uri( 'mode' => "snap_list_$type", 'args' => {
        'id' => $app->param('object_id'), 'deleted' => 1,
        'blog_id' => $app->param('blog_id')
    }));
}

sub snap_keep {
    my ($app) = @_;
    require MT::Snapshot;
    for my $id ($app->param('id')) {
        my $snap = MT::Snapshot->load($id);
        next unless $snap;
        $snap->keep($app->param('keep') ? 1 : 0);
        $snap->save;
    }
    if ($app->param('return_url')) {
        return $app->redirect($app->param('return_url') . '&blog_id=' . $app->param('blog_id'));
    }
    my $type = lc($app->param('parent_object_type'));
    return $app->redirect($app->uri( 'mode' => "snap_list_$type", 'args' => {
        'id' => $app->param('object_id'), 'updated' => 1,
        'blog_id' => $app->param('blog_id')
    }));
}

sub param_assign {
    my ($app, $snap, $obj, $param) = @_;
    $param->{'object_id'} = $obj->id;
    $param->{'class'} = ref($obj);
    if ($snap) {
        $param->{'id'} = $snap->id;
        $param->{'snap_ts'} = display_ts($snap->created_on);
        $param->{'snap_title'} = $snap->title;
        $param->{'snap_show_title'} = $snap->title ? $snap->title
            : $param->{'snap_ts'};
        $param->{'snap_note'} = $snap->note;
        if ($snap->created_by) {
            if (my $user = MT::Author->load($snap->created_by)) {
                $param->{'created_by'} = $snap->created_by;
                $param->{'created_by_name'} = $user->name;
            }
        }
    }
    $param->{'object_type'} = 'snapshot';
    $param->{'parent_object_type'} = ref($obj);
    $param->{'parent_object_type'} =~ s/^MT:://;
    $param->{'lc_object_type'} = lc($param->{'parent_object_type'});
    $param->{'object_ds'} = $obj->datasource;
    eval { $obj->title }; my $can_title = !$@;
    eval { $obj->name }; my $can_name = !$@;
    $param->{'object_title'} = $can_title? $obj->title
        : $can_name ? $obj->name : $obj->id;
}

sub html_compare {
    my ($a_html, $b_html) = @_;
    my $a = html2list($a_html);
    my $b = html2list($b_html);
    my $prev = '';
    my $ins_run = '';
    my $del_run = '';
    my $html = '';
    my $sp = '';
    for my $diff (sdiff($a, $b)) {
        if ($diff->[0] eq 'u') { # unchanged
            $sp = '';
            if ($del_run) {
                $html .= qq{<del>$del_run</del>};
                $del_run = '';
            }
            if ($ins_run) {
                $html .= qq{<ins>$ins_run</ins>};
                $ins_run = '';
            }
            $html .= $diff->[1];
        } elsif ($diff->[0] eq '+') { # added
            $ins_run .= $diff->[2];
        } elsif ($diff->[0] eq '-') { # removed
            $del_run .= $diff->[1];
        } elsif ($diff->[0] eq 'c') { # changed
            $ins_run .= $diff->[2];
            $del_run .= $diff->[1];
        }
        $prev = $diff->[0];
    }
    $html .= qq{<del>$del_run</del>} . qq{<ins>$ins_run</ins>};
    #$html =~ s/\n\n/<p>/g;
    #$html =~ s#\n#<br />#g;
    return $html;
}

sub html2list {
    my ($html) = @_;
    my $mode = 'char';
    my $cur = '';
    my @list = ();
    for my $c (split(//, $html)) {
        if ($mode eq 'tag') {
            if ($c eq '>') {
                $cur .= $c;
                push(@list, $cur);
                $cur = '';
                $mode = 'char';
            } else {
                $cur .= $c;
            }
        } else {
            if ($c eq '<') {
                push(@list, $cur);
                $cur = $c;
                $mode = 'tag';
            } elsif ($c =~ /\s/) {
                push(@list, $cur);
                $cur = $c;
            } else {
                $cur .= $c;
            }
        }
    }
    push(@list, $cur);
    @list = map { $_ ? $_ : () } @list;
    return \@list;
}

sub display_ts {
    sprintf('%04d-%02d-%02d %02d:%02d',
        unpack('A4A2A2A2A2A2', $_[0]));
}

sub init_app_vars {
    my ($app, $bc) = @_;
    $app->{'plugin_template_path'} = 'plugins/Snapshot/tmpl';
    $app->add_breadcrumb($bc);
}

sub apply_default_settings {
# overriding this method to implement system-scope defaults
    my ($plugin, $data, $scope_id) = @_;
    if ($scope_id eq 'system') {
        return $plugin->SUPER::apply_default_settings($data, $scope_id);
    } else {
        my $sys;
        for my $setting (@{$plugin->{'settings'}}) {
            my $key = $setting->[0];
            next if exists($data->{$key});
                # don't load system settings unless we need to
            $sys ||= $plugin->get_config_obj('system')->data;
            $data->{$key} = $sys->{$key};
        }
    }
}

1;
