# -*- perl -*-

use strict;
use warnings;

use Test::More tests => 27;
use XML::XPath;
use XML::XPath::XMLParser;

BEGIN {
        use_ok('Sys::Virt');
        use_ok('Sys::Virt::Domain');
}


my $conn = Sys::Virt->new(uri => "test:///default");

isa_ok($conn, "Sys::Virt");


my $nid = $conn->num_of_domains();
is($nid, 1, "1 active domain");

my @domids = $conn->list_domain_ids($nid);
is_deeply(\@domids, [1], "domain ids");

my $dom = $conn->get_domain_by_id($domids[0]);
isa_ok($dom, "Sys::Virt::Domain");

is($dom->get_name, "test", "name");
is($dom->get_id, "1", "id");
is($dom->get_uuid_string, "004b96e1-2d78-c30f-5aa5-f03c87d21e69", "uuid");

my @doms = $conn->list_domains();
is($#doms, 0, "one domain");
isa_ok($doms[0], "Sys::Virt::Domain");


my $nname = $conn->num_of_defined_domains();
is($nname, 0, "0 defined domain");

my $xml = "<domain type='test'>
  <name>wibble</name>
  <uuid>12341234-5678-5678-5678-123412341234</uuid>
  <memory>10241024</memory>
  <currentMemory>1024120</currentMemory>
  <vcpu>4</vcpu>
</domain>";


$conn->define_domain($xml);

$nname = $conn->num_of_defined_domains();
is($nname, 1, "1 defined domain");

my @names = $conn->list_defined_domain_names($nname);
is_deeply(\@names, ["wibble"], "names");

@doms = $conn->list_defined_domains();
is($#doms, 0, "1 defined domain");
isa_ok($doms[0], "Sys::Virt::Domain");

$dom = $conn->get_domain_by_name("wibble");
isa_ok($dom, "Sys::Virt::Domain");


$dom->create();

my $nids = $conn->num_of_domains();
is($nids, 2, "2 active domains");

my @ids = $conn->list_domain_ids($nids);
is_deeply(\@ids, [1, 2], "domain ids");


my $info = $dom->get_info();
is($info->{memory}, "1024120", "memory");
is($info->{maxMem}, "10241024", "max mem");
is($info->{nrVirtCpu}, "4", "vcpu");
is($info->{state}, &Sys::Virt::Domain::STATE_RUNNING, "state");

$dom->destroy();


$nids = $conn->num_of_domains();
is($nids, 1, "1 active domains");

@ids = $conn->list_domain_ids($nids);
is_deeply(\@ids, [1], "domain ids");

$dom = $conn->get_domain_by_name("wibble");

$dom->undefine();


$nname = $conn->num_of_defined_domains();
is($nname, 0, "0 defined domain");

@names = $conn->list_defined_domain_names($nname);
is_deeply(\@names, [], "names");

