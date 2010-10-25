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

package MT::Snapshot;

use strict;
use Data::Dumper;

use MT::Object;
@MT::Snapshot::ISA = qw(MT::Object);
__PACKAGE__->install_properties({
    column_defs => {
        'id' => 'integer not null auto_increment',
        'blog_id' => 'integer not null default 0',
        'object_id' => 'integer not null',
        'object_ds' => 'string(50) not null',
        'object_class' => 'string(50) not null',
        'snapshot' => 'blob',
        'title' => 'string(100)',
        'note' => 'text',
        'keep' => 'boolean'
    },
    indexes => {
        'blog_id' => 1,
        'object_id' => 1,
        'object_ds' => 1
    },
    audit => 1,
    datasource => 'object_snapshot',
    primary_key => 'id'
});

sub init {
    my $snap = shift;
    my $obj = shift;
    return $snap unless ($obj);
    $snap->SUPER::init(@_);
    require MT::Serialize;
    my $obj_class = ref($obj);
    eval "require $obj_class;";
    my $ser = MT::Serialize->new('MT');
    my $vals = $obj->column_values;
    my $data = $ser->serialize(\$vals);
    $snap->blog_id($obj->blog_id);
    $snap->object_id($obj->id);
    $snap->object_class(ref($obj));
    $snap->object_ds($obj->datasource);
    $snap->snapshot($data);
    $snap->keep(0);
    eval('MT->instance->user');
    if (!$@) {
        $snap->created_by(MT->instance->user->id);
    }
    return $snap;
}

sub obj {
    my $snap = shift;
    require MT::Serialize;
    my $ser = MT::Serialize->new('MT');
    my $thawed = $ser->unserialize($snap->snapshot);
    my $class = $snap->object_class;
    eval "require $class;";
    my $obj = $class->new;
    $obj->set_values($$thawed);
    return $obj;
}

1;
