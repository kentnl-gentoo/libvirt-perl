#!/usr/bin/perl

use strict;
use warnings;
use XML::XPath;

use Test::More;

unless ($ENV{TEST_MAINTAINER}) {
    plan skip_all => "Test only for module maintainer. Set TEST_MAINTAINER=1 to run";
}

my $apifile = `pkg-config --variable=libvirt_api libvirt`;
chomp $apifile;

open API, "<", $apifile or die "cannot read $apifile: $!";
my $xml;
{
    local $/ = undef;
    $xml = <API>;
};
close API;


my $count = 0;

my $xp = XML::XPath->new($xml);

my @enums;
my @functions;

my $set = $xp->find('/api/files/file/exports[@type="function"]/@symbol');
foreach my $n ($set->get_nodelist) {
    $count++;
    push @functions, $n->getData();
}

$set = $xp->find('/api/files/file/exports[@type="enum"]/@symbol');
foreach my $n ($set->get_nodelist) {
    $count++;
    push @enums, $n->getData();
}


open XS, "<Virt.xs" or die "cannot read Virt.xs: $!";

my $xs;
{
    local $/ = undef;
    $xs = <XS>
}
close XS;

my @blacklist = qw(
virConnCopyLastError
virConnGetLastError
virConnResetLastError
virConnSetErrorFunc
virCopyLastError
virDefaultErrorFunc
virErrorFunc
virFreeError
virResetLastError
virSaveLastError

virConnectAuthCallbackPtr
virConnectOpen
virConnectOpenReadOnly

virConnectDomainEventBlockJobCallback
virConnectDomainEventCallback
virConnectDomainEventDiskChangeCallback
virConnectDomainEventGraphicsCallback
virConnectDomainEventIOErrorCallback
virConnectDomainEventIOErrorReasonCallback
virConnectDomainEventRTCChangeCallback
virConnectDomainEventWatchdogCallback
virConnectDomainEventPMSuspendCallback
virConnectDomainEventPMWakeupCallback
virConnectDomainEventTrayChangeCallback
virConnectDomainEventBalloonChangeCallback

virEventAddHandleFunc
virEventAddTimeoutFunc
virEventRemoveHandleFunc
virEventRemoveTimeoutFunc
virEventUpdateHandleFunc
virEventUpdateTimeoutFunc

virStreamEventCallback
virStreamSinkFunc
virStreamSourceFunc

virConnectCloseFunc

);

foreach my $func (sort { $a cmp $b } @functions) {
    if ($func =~ /(GetConnect|Ref|GetDomain)$/ ||
	grep {/$func/ } @blacklist) {
	ok(1, $func);
	next;
    }

    ok($xs =~ /\b$func\b/, $func);
}


foreach my $enum (sort { $a cmp $b } @enums) {
    if ($enum =~ /_LAST$/ ||
	$enum =~ /VIR_(TYPED_PARAM|DOMAIN_MEMORY_PARAM|DOMAIN_SCHED_FIELD|DOMAIN_BLKIO_PARAM)_(STRING|STRING_OKAY|BOOLEAN|DOUBLE|INT|LLONG|UINT|ULLONG)/ ||
	$enum eq "VIR_CPU_COMPARE_ERROR" ||
	$enum eq "VIR_DOMAIN_NONE" ||
	$enum eq "VIR_DOMAIN_MEMORY_STAT_NR") {
	ok(1, $enum);
	next;
    }

    ok($xs =~ /REGISTER_CONSTANT(_STR)?\($enum,/, $enum);
}

done_testing($count);
