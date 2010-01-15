# -*- perl -*-
#
# Copyright (C) 2006-2009 Red Hat
# Copyright (C) 2006-2009 Daniel P. Berrange
#
# This program is free software; You can redistribute it and/or modify
# it under either:
#
# a) the GNU General Public License as published by the Free
#   Software Foundation; either version 2, or (at your option) any
#   later version,
#
# or
#
# b) the "Artistic License"
#
# The file "LICENSE" distributed along with this file provides full
# details of the terms and conditions of the two licenses.

=pod

=head1 NAME

Sys::Virt::StoragePool - Represent & manage a libvirt storage pool

=head1 DESCRIPTION

The C<Sys::Virt::StoragePool> module represents a storage pool managed
by libvirt. There are a variety of storage pool implementations for
LVM, Local directories/filesystems, network filesystems, disk
partitioning, iSCSI, and SCSI.

=head1 METHODS

=over 4

=cut

package Sys::Virt::StoragePool;

use strict;
use warnings;


sub _new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %params = @_;

    my $con = exists $params{connection} ? $params{connection} : die "connection parameter is requried";
    my $self;
    if (exists $params{name}) {
	$self = Sys::Virt::StoragePool::_lookup_by_name($con,  $params{name});
    } elsif (exists $params{uuid}) {
	if (length($params{uuid}) == 16) {
	    $self = Sys::Virt::StoragePool::_lookup_by_uuid($con,  $params{uuid});
	} elsif (length($params{uuid}) == 32 ||
		 length($params{uuid}) == 36) {
	    $self = Sys::Virt::StoragePool::_lookup_by_uuid_string($con,  $params{uuid});
	} else {
	    die "UUID must be either 16 unsigned bytes, or 32/36 hex characters long";
	}
    } elsif (exists $params{xml}) {
	if ($params{nocreate}) {
	    $self = Sys::Virt::StoragePool::_define_xml($con,  $params{xml});
	} else {
	    $self = Sys::Virt::StoragePool::_create_xml($con,  $params{xml});
	}
    } else {
	die "address, id or uuid parameters are required";
    }

    bless $self, $class;

    return $self;
}


=item my $uuid = $pool->get_uuid()

Returns a 16 byte long string containing the raw globally unique identifier
(UUID) for the storage pool.

=item my $uuid = $pool->get_uuid_string()

Returns a printable string representation of the raw UUID, in the format
'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'.

=item my $name = $pool->get_name()

Returns a string with a locally unique name of the storage pool

=item $pool->is_active()

Returns a true value if the storage pool is currently running

=item $pool->is_persistent()

Returns a true value if the storage pool has a persistent configuration
file defined

=item my $xml = $pool->get_xml_description()

Returns an XML document containing a complete description of
the storage pool's configuration

=item $pool->create()

Start a storage pool whose configuration was previously defined using the
C<define_storage_pool> method in L<Sys::Virt>.

=item $pool->undefine()

Remove the configuration associated with a storage pool previously defined
with the C<define_storage pool> method in L<Sys::Virt>. If the storage pool is
running, you probably want to use the C<shutdown> or C<destroy>
methods instead.

=item $pool->destroy()

Immediately terminate the machine, and remove it from the virtual
machine monitor. The C<$pool> handle is invalid after this call
completes and should not be used again.

=item $flag = $pool->get_autostart();

Return a true value if the storage pool is configured to automatically
start upon boot. Return false, otherwise

=item $pool->set_autostart($flag)

Set the state of the autostart flag, which determines whether the
storage pool will automatically start upon boot of the host OS

=item $pool->refresh([$flags]);

Refresh the storage pool state. Typically this will rescan the list
of storage volumes. The C<$flags> parameter is currently unused and
if omitted defaults to zero.

=item $pool->build([$flags]);

Construct the storage pool if it does not exist. As an example, for
a disk based storage pool this would ensure a partition table exists.
The C<$flags> parameter allows control over the build operation
and if omitted defaults to zero.

=item $pool->delete([$flags]);

Delete the storage pool. The C<$flags> parameter allows the data to
be optionally wiped during delete and if omitted defaults to zero.

=item %info = $pool->get_info()

Retrieve information about the current storage pool state. The
returned hash has the following keys

=over 4

=item state

The current status of the storage pool. See constants later.

=item capacity

The total logical size of the storage pool

=item allocation

The current physical allocation of the storage pool

=item available

The available space for creation of new volumes. This may
be less than the difference between capacity & allocation
if there are sizing / metadata constraints for volumes

=back

=item my $nnames = $pool->num_of_storage_volumes()

Return the number of running volumes in this storage pool. The value
can be used as the C<maxnames> parameter to C<list_storage_vol_names>.

=item my @volNames = $pool->list_storage_vol_names($maxnames)

Return a list of all volume names in this storage pool. The names can
be used with the C<get_volume_by_name> method.

=item my @nets = $pool->list_volumes()

Return a list of all volumes in the storage pool.
The elements in the returned list are instances of the
L<Sys::Virt::StorageVol> class.

=cut

sub list_volumes {
    my $self = shift;

    my $nnames = $self->num_of_storage_volumes();
    my @names = $self->list_storage_vol_names($nnames);

    my @volumes;
    foreach my $name (@names) {
	eval {
	    push @volumes, Sys::Virt::StorageVol->_new(pool => $self, name => $name);
	};
	if ($@) {
	    # nada - domain went away before we could look it up
	};
    }
    return @volumes;
}


=item my $vol = $pool->get_volume_by_name($name)

Return the volume with a name of C<$name>. The returned object is
an instance of the L<Sys::Virt::StorageVol> class.

=cut

sub get_volume_by_name {
    my $self = shift;
    my $name = shift;

    return Sys::Virt::StorageVol->_new(pool => $self, name => $name);
}

=item my $vol = $pool->create_volume($xml)

Create a new volume based on the XML description passed into the C<$xml>
parameter. The returned object is an instance of the L<Sys::Virt::StorageVol>
class. If the optional C<clonevol> is provided, data will be copied from
that source volume

=cut

sub create_volume {
    my $self = shift;
    my $xml = shift;

    return Sys::Virt::StorageVol->_new(pool => $self, xml => $xml);
}

=item my $vol = $pool->clone_volume($xml, $clonevol);

Create a new volume based on the XML description passed into the C<$xml>
parameter. The returned object is an instance of the L<Sys::Virt::StorageVol>
class. The new volume will be populated with data from the specified clone
source volume.

=cut


sub clone_volume {
    my $self = shift;
    my $xml = shift;
    my $clone = shift;

    return Sys::Virt::StorageVol->_new(pool => $self, xml => $xml, clone => $clone);
}

1;

=back

=head1 CONSTANTS

The following sets of constants may be useful in dealing with some of
the methods in this package

=head2 POOL STATES

The following constants are useful for interpreting the C<state>
key value in the hash returned by C<get_info>

=over 4

=item Sys::Virt::StoragePool::STATE_INACTIVE

The storage pool is not currently active

=item Sys::Virt::StoragePool::STATE_BUILDING

The storage pool is still being constructed and is not ready for use
yet.

=item Sys::Virt::StoragePool::STATE_RUNNING

The storage pool is running and can be queried for volumes

=item Sys::Virt::StoragePool::STATE_DEGRADED

The storage pool is running, but its operation is degraded due
to a failure.

=back

=head2 DELETION MODES

=over 4

=item Sys::Virt::StoragePool::DELETE_NORMAL

Delete the pool without any attempt to scrub data

=item Sys::Virt::StoragePool::DELETE_ZEROED

Fill the allocated storage with zeros when deleting

=back


=head2 BUILD MODES

=over 4

=item Sys::Virt::StoragePool::BUILD_NEW

Construct a new storage pool from constituent bits

=item Sys::Virt::StoragePool::BUILD_RESIZE

Resize an existing built storage pool preserving data where
appropriate

=item Sys::Virt::StoragePool::BUILD_REPAIR

Repair an existing storage pool operating in degraded mode

=back

=head1 AUTHORS

Daniel P. Berrange <berrange@redhat.com>

=head1 COPYRIGHT

Copyright (C) 2006-2009 Red Hat
Copyright (C) 2006-2009 Daniel P. Berrange

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of either the GNU General Public License as published
by the Free Software Foundation (either version 2 of the License, or at
your option any later version), or, the Artistic License, as specified
in the Perl README file.

=head1 SEE ALSO

L<Sys::Virt>, L<Sys::Virt::Error>, C<http://libvirt.org>

=cut
