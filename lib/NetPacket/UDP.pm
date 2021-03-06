#
# NetPacket::UDP - Decode and encode UDP (User Datagram Protocol)
# packets. 

package NetPacket::UDP;
# ABSTRACT: Assemble and disassemble UDP (User Datagram Protocol) packets.

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use NetPacket;
use NetPacket::IP;

BEGIN {
    @ISA = qw(Exporter NetPacket);

# Items to export into callers namespace by default
# (move infrequently used names to @EXPORT_OK below)

    @EXPORT = qw(
    );

# Other items we are prepared to export if requested

    @EXPORT_OK = qw(udp_strip
    );

# Tags:

    %EXPORT_TAGS = (
    ALL         => [@EXPORT, @EXPORT_OK],
    strip       => [qw(udp_strip)],
);

}

#
# Decode the packet
#

sub decode {
    my $class = shift;
    my($pkt, $parent) = @_;
    my $self = {};

    # Class fields

    $self->{_parent} = $parent;
    $self->{_frame} = $pkt;

    # Decode UDP packet

    if (defined($pkt)) {

	($self->{src_port}, $self->{dest_port}, $self->{len}, $self->{cksum},
	 $self->{data}) = unpack("nnnna*", $pkt);
    }

    # Return a blessed object

    bless($self, $class);
    return $self;
}

#
# Strip header from packet and return the data contained in it
#

undef &udp_strip;
*udp_strip = \&strip;

sub strip {
    return decode(__PACKAGE__,shift)->{data};
}   

#
# Encode a packet
#

sub encode {

    my $self = shift;
    my ($ip) = @_;
    my ($packet);

    # Adjust the length accodingly
    $self->{len} = 8 + length($self->{data});

    # First of all, fix the checksum
    $self->checksum($ip);

    # Put the packet together
    $packet = pack("nnnna*", $self->{src_port},$self->{dest_port},
                $self->{len}, $self->{cksum}, $self->{data});

    return($packet); 
}

# 
# UDP Checksum
#

sub checksum {

    my( $self, $ip ) = @_;

    my $proto = NetPacket::IP::IP_PROTO_UDP;

    # Pack pseudo-header for udp checksum

    my $src_ip = gethostbyname($ip->{src_ip});
    my $dest_ip = gethostbyname($ip->{dest_ip});

    no warnings;

    my $packet = pack 'a4a4CCnnnnna*' =>

      # fake ip header part
      $src_ip, $dest_ip, 0, $proto, $self->{len},

      # proper UDP part
      $self->{src_port}, $self->{dest_port}, $self->{len}, 0, $self->{data};

    $packet .= "\x00" if length($packet) % 2;

    $self->{cksum} = NetPacket::htons(NetPacket::in_cksum($packet)); 

}

1;

__END__

=head1 SYNOPSIS

  use NetPacket::UDP;

  $udp_obj = NetPacket::UDP->decode($raw_pkt);
  $udp_pkt = NetPacket::UDP->encode($ip_obj);
  $udp_data = NetPacket::UDP::strip($raw_pkt);

=head1 DESCRIPTION

C<NetPacket::UDP> provides a set of routines for assembling and
disassembling packets using UDP (User Datagram Protocol).  

=head2 Methods

=over

=item C<NetPacket::UDP-E<gt>decode([RAW PACKET])>

Decode the raw packet data given and return an object containing
instance data.  This method will quite happily decode garbage input.
It is the responsibility of the programmer to ensure valid packet data
is passed to this method.

=item C<NetPacket::UDP-E<gt>encode($ip_obj)>

Return a UDP packet encoded with the instance data specified. Needs parts 
of the IP header contained in $ip_obj, the IP object, in order to calculate 
the UDP checksum. The length field will also be set automatically.

=back

=head2 Functions

=over

=item C<NetPacket::UDP::strip([RAW PACKET])>

Return the encapsulated data (or payload) contained in the UDP
packet.  This data is suitable to be used as input for other
C<NetPacket::*> modules.

This function is equivalent to creating an object using the
C<decode()> constructor and returning the C<data> field of that
object.

=back

=head2 Instance data

The instance data for the C<NetPacket::UDP> object consists of
the following fields.

=over

=item src_port

The source UDP port for the datagram.

=item dest_port

The destination UDP port for the datagram.

=item len

The length (including length of header) in bytes for this packet.

=item cksum

The checksum value for this packet.

=item data

The encapsulated data (payload) for this packet.

=back

=head2 Exports

=over

=item default

none

=item exportable

udp_strip

=item tags

The following tags group together related exportable items.

=over

=item C<:strip>

Import the strip function C<udp_strip>.

=item C<:ALL>

All the above exportable items.

=back

=back

=head1 EXAMPLE

The following example prints the source IP address and port, the
destination IP address and port, and the UDP packet length:

  #!/usr/bin/perl -w

  use strict;
  use Net::PcapUtils;
  use NetPacket::Ethernet qw(:strip);
  use NetPacket::IP;
  use NetPacket::UDP;

  sub process_pkt {
      my($arg, $hdr, $pkt) = @_;

      my $ip_obj = NetPacket::IP->decode(eth_strip($pkt));
      my $udp_obj = NetPacket::UDP->decode($ip_obj->{data});

      print("$ip_obj->{src_ip}:$udp_obj->{src_port} -> ",
	    "$ip_obj->{dest_ip}:$udp_obj->{dest_port} ",
	    "$udp_obj->{len}\n");
  }

  Net::PcapUtils::loop(\&process_pkt, FILTER => 'udp');

The following is an example use in combination with Net::Divert 
to alter the payload of packets that pass through. All occurences
of foo will be replaced with bar. This example is easy to test with 
netcat, but otherwise makes little sense. :) Adapt to your needs:

    use Net::Divert;
    use NetPacket::IP qw(IP_PROTO_UDP);
    use NetPacket::UDP;

    $divobj = Net::Divert->new('yourhost',9999);

    $divobj->getPackets(\&alterPacket);

    sub alterPacket
    {
        my ($data, $fwtag) = @_;

        $ip_obj = NetPacket::IP->decode($data);

        if($ip_obj->{proto} == IP_PROTO_UDP) {

            # decode the UDP header
            $udp_obj = NetPacket::UDP->decode($ip_obj->{data});

            # replace foo in the payload with bar
            $udp_obj->{data} =~ s/foo/bar/g;

            # reencode the packet
            $ip_obj->{data} = $udp_obj->encode($ip_obj);
            $data = $ip_obj->encode;

        }

        $divobj->putPacket($data,$fwtag);
    }

=head1 COPYRIGHT

Copyright (c) 2001 Tim Potter.

Copyright (c) 1995,1996,1997,1998,1999 ANU and CSIRO on behalf of 
the participants in the CRC for Advanced Computational Systems
('ACSys').

This module is free software.  You can redistribute it and/or
modify it under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful,
but without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=head1 AUTHOR

Tim Potter E<lt>tpot@samba.orgE<gt>

Stephanie Wehner E<lt>atrak@itsx.comE<gt>

Yanick Champoux <yanick@cpan.org>

=cut
