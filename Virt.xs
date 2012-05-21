/* -*- c -*-
 *
 * Copyright (C) 2006 Red Hat
 * Copyright (C) 2006-2007 Daniel P. Berrange
 *
 * This program is free software; You can redistribute it and/or modify
 * it under either:
 *
 * a) the GNU General Public License as published by the Free
 *   Software Foundation; either version 2, or (at your option) any
 *   later version,
 *
 * or
 *
 * b) the "Artistic License"
 *
 * The file "LICENSE" distributed along with this file provides full
 * details of the terms and conditions of the two licenses.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <libvirt/virterror.h>
#include <libvirt/libvirt.h>

/*
 * On 32-bit OS (and some 64-bit) Perl does not have an
 * integer type capable of storing 64 bit numbers. So
 * we serialize to/from strings on these platforms
 */

long long
virt_SvIVll(SV *sv) {
#ifdef USE_64_BIT_ALL
    return SvIV(sv);
#else
    return strtoll(SvPV_nolen(sv), NULL, 10);
#endif
}


unsigned long long
virt_SvIVull(SV *sv) {
#ifdef USE_64_BIT_ALL
    return SvIV(sv);
#else
    return strtoull(SvPV_nolen(sv), NULL, 10);
#endif
}


#ifndef PRId64
#define PRId64 "lld"
#endif


SV *
virt_newSVll(long long val) {
#ifdef USE_64_BIT_ALL
    return newSViv(val);
#else
    char buf[100];
    int len;
    len = snprintf(buf, 100, "%" PRId64, val);
    return newSVpv(buf, len);
#endif
}


#ifndef PRIu64
#define PRIu64 "llu"
#endif

SV *
virt_newSVull(unsigned long long val) {
#ifdef USE_64_BIT_ALL
    return newSVuv(val);
#else
    char buf[100];
    int len;
    len = snprintf(buf, 100, "%" PRIu64, val);
    return newSVpv(buf, len);
#endif
}



void ignoreVirErrorFunc(void * userData, virErrorPtr error) {
  /* Do nothing */
}


SV *
_sv_from_error(virErrorPtr error)
{
    HV *hv;

    hv = newHV ();

    /* Map virErrorPtr attributes to hash keys */
    (void)hv_store (hv, "level", 5, newSViv (error ? error->level : 0), 0);
    (void)hv_store (hv, "code", 4, newSViv (error ? error->code : 0), 0);
    (void)hv_store (hv, "domain", 6, newSViv (error ? error->domain : VIR_FROM_NONE), 0);
    (void)hv_store (hv, "message", 7, newSVpv (error && error->message ? error->message : "Unknown problem", 0), 0);

    return sv_bless (newRV_noinc ((SV*) hv), gv_stashpv ("Sys::Virt::Error", TRUE));
}


void
_croak_error(void)
{
    virErrorPtr error = virGetLastError();
    sv_setsv(ERRSV, _sv_from_error (error));

    /* croak does not return, so we free this now to avoid leaking */
    virResetError(error);

    croak (Nullch);
}


void
_populate_constant(HV *stash, char *name, int val)
{
    SV *valsv;

    valsv = newSViv(0);
    sv_setuv(valsv,val);
    newCONSTSUB(stash, name, valsv);
}


void
_populate_constant_str(HV *stash, char *name, const char *value)
{
    SV *valsv;

    valsv = newSVpv(value, strlen(value));
    newCONSTSUB(stash, name, valsv);
}


void
_populate_constant_ull(HV *stash, char *name, unsigned long long val)
{
    SV *valsv;

    valsv = virt_newSVull(val);
    newCONSTSUB(stash, name, valsv);
}


#define REGISTER_CONSTANT(name, key) _populate_constant(stash, #key, name)
#define REGISTER_CONSTANT_STR(name, key) _populate_constant_str(stash, #key, name)
#define REGISTER_CONSTANT_ULL(name, key) _populate_constant_ull(stash, #key, name)

static int
_domain_event_lifecycle_callback(virConnectPtr con,
                                 virDomainPtr dom,
                                 int event,
                                 int detail,
                                 void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSViv(event)));
    XPUSHs(sv_2mortal(newSViv(detail)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_generic_callback(virConnectPtr con,
                               virDomainPtr dom,
                               void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_rtcchange_callback(virConnectPtr con,
                                 virDomainPtr dom,
                                 long long utcoffset,
                                 void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(virt_newSVll(utcoffset)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_watchdog_callback(virConnectPtr con,
                                virDomainPtr dom,
                                int action,
                                void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSViv(action)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_io_error_callback(virConnectPtr con,
                                virDomainPtr dom,
                                const char *srcPath,
                                const char *devAlias,
                                int action,
                                void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSVpv(srcPath, 0)));
    XPUSHs(sv_2mortal(newSVpv(devAlias, 0)));
    XPUSHs(sv_2mortal(newSViv(action)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_disk_change_callback(virConnectPtr con,
                                   virDomainPtr dom,
                                   const char *oldSrcPath,
                                   const char *newSrcPath,
                                   const char *devAlias,
                                   int reason,
                                   void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSVpv(oldSrcPath, 0)));
    XPUSHs(sv_2mortal(newSVpv(newSrcPath, 0)));
    XPUSHs(sv_2mortal(newSVpv(devAlias, 0)));
    XPUSHs(sv_2mortal(newSViv(reason)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_tray_change_callback(virConnectPtr con,
                                   virDomainPtr dom,
                                   const char *devAlias,
                                   int reason,
                                   void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSVpv(devAlias, 0)));
    XPUSHs(sv_2mortal(newSViv(reason)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_pmwakeup_callback(virConnectPtr con,
                                virDomainPtr dom,
                                int reason,
                                void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSViv(reason)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_pmsuspend_callback(virConnectPtr con,
                                 virDomainPtr dom,
                                 int reason,
                                 void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSViv(reason)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_io_error_reason_callback(virConnectPtr con,
                                       virDomainPtr dom,
                                       const char *srcPath,
                                       const char *devAlias,
                                       int action,
                                       const char *reason,
                                       void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSVpv(srcPath, 0)));
    XPUSHs(sv_2mortal(newSVpv(devAlias, 0)));
    XPUSHs(sv_2mortal(newSViv(action)));
    XPUSHs(sv_2mortal(newSVpv(reason, 0)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_graphics_callback(virConnectPtr con,
                                virDomainPtr dom,
                                int phase,
                                virDomainEventGraphicsAddressPtr local,
                                virDomainEventGraphicsAddressPtr remote,
                                const char *authScheme,
                                virDomainEventGraphicsSubjectPtr subject,
                                void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    HV *local_hv;
    HV *remote_hv;
    AV *subject_av;
    int i;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    local_hv = newHV();
    (void)hv_store(local_hv, "family", 6, newSViv(local->family), 0);
    (void)hv_store(local_hv, "node", 4, newSVpv(local->node, 0), 0);
    (void)hv_store(local_hv, "service", 7, newSVpv(local->service, 0), 0);

    remote_hv = newHV();
    (void)hv_store(remote_hv, "family", 6, newSViv(remote->family), 0);
    (void)hv_store(remote_hv, "node", 4, newSVpv(remote->node, 0), 0);
    (void)hv_store(remote_hv, "service", 7, newSVpv(remote->service, 0), 0);

    subject_av = newAV();
    for (i = 0 ; i < subject->nidentity ; i++) {
        HV *identity = newHV();
        (void)hv_store(identity, "type", 4, newSVpv(subject->identities[i].type, 0), 0);
        (void)hv_store(identity, "name", 4, newSVpv(subject->identities[i].name, 0), 0);

        av_push(subject_av, newRV_noinc((SV *)identity));
    }

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSViv(phase)));
    XPUSHs(newRV_noinc((SV*)local_hv));
    XPUSHs(newRV_noinc((SV*)remote_hv));
    XPUSHs(sv_2mortal(newSVpv(authScheme, 0)));
    XPUSHs(newRV_noinc((SV*)subject_av));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_domain_event_block_job_callback(virConnectPtr con,
                                 virDomainPtr dom,
                                 const char *path,
                                 int type,
                                 int status,
                                 void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    SV *domref;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    domref = sv_newmortal();
    sv_setref_pv(domref, "Sys::Virt::Domain", (void*)dom);
    virDomainRef(dom);
    XPUSHs(domref);
    XPUSHs(sv_2mortal(newSVpv(path, 0)));
    XPUSHs(sv_2mortal(newSViv(type)));
    XPUSHs(sv_2mortal(newSViv(status)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static void
_domain_event_free(void *opaque)
{
  SV *sv = opaque;
  SvREFCNT_dec(sv);
}


static int
_event_add_handle(int fd,
		  int events,
		  virEventHandleCallback cb,
		  void *opaque,
		  virFreeCallback ff)
{
    SV *cbref;
    SV *opaqueref;
    SV *ffref;
    int ret;
    int watch = 0;
    dSP;

    ENTER;
    SAVETMPS;

    cbref= sv_newmortal();
    opaqueref= sv_newmortal();
    ffref= sv_newmortal();

    sv_setref_pv(cbref, NULL, cb);
    sv_setref_pv(opaqueref, NULL, opaque);
    sv_setref_pv(ffref, NULL, ff);

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(fd)));
    XPUSHs(sv_2mortal(newSViv(events)));
    XPUSHs(cbref);
    XPUSHs(opaqueref);
    XPUSHs(ffref);
    PUTBACK;

    ret = call_pv("Sys::Virt::Event::_add_handle", G_SCALAR);

    SPAGAIN;

    if (ret == 1)
      watch = POPi;

    FREETMPS;
    LEAVE;

    if (ret != 1)
      return -1;

    return watch;
}


static void
_event_update_handle(int watch,
		     int events)
{
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(watch)));
    XPUSHs(sv_2mortal(newSViv(events)));
    PUTBACK;

    call_pv("Sys::Virt::Event::_update_handle", G_DISCARD);

    FREETMPS;
    LEAVE;
}


static int
_event_remove_handle(int watch)
{
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(watch)));
    PUTBACK;

    call_pv("Sys::Virt::Event::_remove_handle", G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
    return 0;
}


static int
_event_add_timeout(int interval,
		   virEventTimeoutCallback cb,
		   void *opaque,
		   virFreeCallback ff)
{
    SV *cbref;
    SV *opaqueref;
    SV *ffref;
    int ret;
    int timer = 0;
    dSP;

    ENTER;
    SAVETMPS;

    cbref = sv_newmortal();
    opaqueref = sv_newmortal();
    ffref = sv_newmortal();

    sv_setref_pv(cbref, NULL, cb);
    sv_setref_pv(opaqueref, NULL, opaque);
    sv_setref_pv(ffref, NULL, ff);

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(interval)));
    XPUSHs(cbref);
    XPUSHs(opaqueref);
    XPUSHs(ffref);
    PUTBACK;

    ret = call_pv("Sys::Virt::Event::_add_timeout", G_SCALAR);

    SPAGAIN;

    if (ret == 1)
      timer = POPi;

    FREETMPS;
    LEAVE;

    if (ret != 1)
      return -1;

    return timer;
}


static void
_event_update_timeout(int timer,
		      int interval)
{
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(timer)));
    XPUSHs(sv_2mortal(newSViv(interval)));
    PUTBACK;

    call_pv("Sys::Virt::Event::_update_timeout", G_DISCARD);

    FREETMPS;
    LEAVE;
}


static int
_event_remove_timeout(int timer)
{
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(timer)));
    PUTBACK;

    call_pv("Sys::Virt::Event::_remove_timeout", G_DISCARD);

    FREETMPS;
    LEAVE;

    return 0;
}


static int
_open_auth_callback(virConnectCredentialPtr cred,
		    unsigned int ncred,
		    void *cbdata)
{
  dSP;
  int i, ret, success = -1;
  AV *credlist;

  credlist = newAV();

  ENTER;
  SAVETMPS;
  PUSHMARK(SP);

  for (i = 0 ; i < ncred ; i++) {
      HV *credrec = newHV();

      (void)hv_store(credrec, "type", 4, newSViv(cred[i].type), 0);
      (void)hv_store(credrec, "prompt", 6, newSVpv(cred[i].prompt, 0), 0);
      (void)hv_store(credrec, "challenge", 9, newSVpv(cred[i].challenge, 0), 0);
      if (cred[i].defresult != NULL)
          (void)hv_store(credrec, "result", 6, newSVpv(cred[i].defresult, 0), 0);
      else
          (void)hv_fetch(credrec, "result", 6, 1);

      av_push(credlist, newRV_noinc((SV *)credrec));
  }
  SvREFCNT_inc((SV*)credlist);

  XPUSHs(newRV_noinc((SV*)credlist));
  PUTBACK;

  ret = call_sv((SV*)cbdata, G_SCALAR);

  SPAGAIN;

  if (ret == 1)
     success = POPi;

  for (i = 0 ; i < ncred ; i++) {
      SV **credsv = av_fetch(credlist, i, 0);
      HV *credrec = (HV*)SvRV(*credsv);
      SV **val = hv_fetch(credrec, "result", 6, 0);

      if (val && SvOK(*val)) {
	  STRLEN len;
	  char *result = SvPV(*val, len);
	  if (!(cred[i].result = malloc(len+1)))
	      abort();
	  memcpy(cred[i].result, result, len+1);
	  cred[i].resultlen = (unsigned int)len;
      } else {
	  cred[i].resultlen = 0;
	  cred[i].result = NULL;
      }
  }

  FREETMPS;
  LEAVE;

  return success;
}


static void
_event_handle_helper(int watch,
                     int fd,
                     int events,
                     void *opaque)
{
    SV *cb = opaque;
    dSP;

    SvREFCNT_inc(cb);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(watch)));
    XPUSHs(sv_2mortal(newSViv(fd)));
    XPUSHs(sv_2mortal(newSViv(events)));
    PUTBACK;

    call_sv(cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}


static void
_event_timeout_helper(int timer,
                      void *opaque)
{
    SV *cb = opaque;
    dSP;

    SvREFCNT_inc(cb);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(timer)));
    PUTBACK;

    call_sv(cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}


static void
_event_cb_free(void *opaque)
{
    SV *data = opaque;
    SvREFCNT_dec(data);
}


static void
_stream_event_callback(virStreamPtr st,
                       int events,
                       void *opaque)
{
    AV *data = opaque;
    SV **self;
    SV **cb;
    dSP;

    self = av_fetch(data, 0, 0);
    cb = av_fetch(data, 1, 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    XPUSHs(sv_2mortal(newSViv(events)));
    PUTBACK;

    call_sv(*cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}


static void
_stream_event_free(void *opaque)
{
    AV *data = opaque;
    SvREFCNT_dec(data);
}


static int
_stream_send_all_source(virStreamPtr st,
                        char *data,
                        size_t nbytes,
                        void *opaque)
{
    AV *av = opaque;
    SV **self;
    SV **handler;
    SV *datasv;
    int rv;
    int ret;
    dSP;

    self = av_fetch(av, 0, 0);
    handler = av_fetch(av, 1, 0);
    datasv = newSVpv("", 0);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    XPUSHs(datasv);
    XPUSHs(sv_2mortal(newSViv(nbytes)));
    PUTBACK;

    rv = call_sv((SV*)*handler, G_SCALAR);

    SPAGAIN;

    if (rv == 1) {
        ret = POPi;
    } else {
        ret = -1;
    }

    if (ret > 0) {
        const char *newdata = SvPV_nolen(datasv);
        if (ret > nbytes)
            ret = nbytes;
        strncpy(data, newdata, nbytes);
    }

    FREETMPS;
    LEAVE;

    SvREFCNT_dec(datasv);

    return ret;
}


static int
_stream_recv_all_sink(virStreamPtr st,
                      const char *data,
                      size_t nbytes,
                      void *opaque)
{
    AV *av = opaque;
    SV **self;
    SV **handler;
    SV *datasv;
    int rv;
    int ret;
    dSP;

    self = av_fetch(av, 0, 0);
    handler = av_fetch(av, 1, 0);
    datasv = newSVpv(data, nbytes);

    SvREFCNT_inc(*self);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(*self);
    XPUSHs(datasv);
    XPUSHs(sv_2mortal(newSViv(nbytes)));
    PUTBACK;

    rv = call_sv((SV*)*handler, G_SCALAR);

    SPAGAIN;

    if (rv == 1) {
        ret = POPi;
    } else {
        ret = -1;
    }

    FREETMPS;
    LEAVE;

    SvREFCNT_dec(datasv);

    return ret;
}


static HV *
vir_typed_param_to_hv(virTypedParameter *params, int nparams)
{
    HV *ret = (HV *)sv_2mortal((SV*)newHV());
    unsigned int i;
    const char *field;
    STRLEN val_length;

    for (i = 0 ; i < nparams ; i++) {
        SV *val = NULL;

        switch (params[i].type) {
        case VIR_TYPED_PARAM_INT:
            val = newSViv(params[i].value.i);
            break;

        case VIR_TYPED_PARAM_UINT:
            val = newSViv((int)params[i].value.ui);
            break;

        case VIR_TYPED_PARAM_LLONG:
            val = virt_newSVll(params[i].value.l);
            break;

        case VIR_TYPED_PARAM_ULLONG:
            val = virt_newSVull(params[i].value.ul);
            break;

        case VIR_TYPED_PARAM_DOUBLE:
            val = newSVnv(params[i].value.d);
            break;

        case VIR_TYPED_PARAM_BOOLEAN:
            val = newSViv(params[i].value.b);
            break;

        case VIR_TYPED_PARAM_STRING:
            val_length = strlen(params[i].value.s);
            val = newSVpv(params[i].value.s, val_length);
            break;

        }

        field = params[i].field;
        (void)hv_store(ret, field, strlen(params[i].field), val, 0);
    }

    return ret;
}


static int
vir_typed_param_from_hv(HV *newparams, virTypedParameter *params, int nparams)
{
    unsigned int i;
    char * ptr;
    STRLEN len;
    int needString = 0;

    for (i = 0 ; i < nparams ; i++) {
        SV **val;

        if (!hv_exists(newparams, params[i].field, strlen(params[i].field)))
            continue;

        val = hv_fetch (newparams, params[i].field, strlen(params[i].field), 0);

        switch (params[i].type) {
        case VIR_TYPED_PARAM_INT:
            params[i].value.i = SvIV(*val);
            break;

        case VIR_TYPED_PARAM_UINT:
            params[i].value.ui = SvIV(*val);
            break;

        case VIR_TYPED_PARAM_LLONG:
            params[i].value.l = virt_SvIVll(*val);
            break;

        case VIR_TYPED_PARAM_ULLONG:
            params[i].value.ul = virt_SvIVull(*val);
            break;

        case VIR_TYPED_PARAM_DOUBLE:
            params[i].value.d = SvNV(*val);
            break;

        case VIR_TYPED_PARAM_BOOLEAN:
            params[i].value.b = SvIV(*val);
            break;

        case VIR_TYPED_PARAM_STRING:
            needString = 1;
            ptr = SvPV(*val, len);
            params[i].value.s = (char *)ptr;
            break;
        }
    }
    return needString;
}


MODULE = Sys::Virt  PACKAGE = Sys::Virt

PROTOTYPES: ENABLE

virConnectPtr
_open(name, flags)
      SV *name;
      unsigned int flags;
PREINIT:
      const char *uri = NULL;
    CODE:
      if (SvOK(name))
	  uri = SvPV_nolen(name);

      if (!(RETVAL = virConnectOpenAuth(uri, NULL, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virConnectPtr
_open_auth(name, creds, cb, flags)
      SV *name;
      SV *creds;
      SV *cb;
      unsigned int flags;
PREINIT:
      AV *credlist;
      virConnectAuth auth;
      int i;
      const char *uri = NULL;
   CODE:
      if (SvOK(name))
	  uri = SvPV_nolen(name);

      if (SvOK(cb) && SvOK(creds)) {
	  memset(&auth, 0, sizeof auth);
	  credlist = (AV*)SvRV(creds);
	  auth.ncredtype = av_len(credlist) + 1;
	  Newx(auth.credtype, auth.ncredtype, int);
	  for (i = 0 ; i < auth.ncredtype ; i++) {
	    SV **type = av_fetch(credlist, i, 0);
	    auth.credtype[i] = SvIV(*type);
	  }

	  auth.cb = _open_auth_callback;
	  auth.cbdata = cb;
	  RETVAL = virConnectOpenAuth(uri,
				      &auth,
                                      flags);
	  Safefree(auth.credtype);
      } else {
	  RETVAL = virConnectOpenAuth(uri,
				      virConnectAuthPtrDefault,
                                      flags);
      }
      if (!RETVAL)
	_croak_error();
 OUTPUT:
      RETVAL


void
restore_domain(con, from, dxmlsv=&PL_sv_undef, flags=0)
      virConnectPtr con;
      const char *from;
      SV *dxmlsv;
      unsigned int flags;
 PREINIT:
      const char *dxml = NULL;
  PPCODE:
      if (SvOK(dxmlsv))
	  dxml = SvPV_nolen(dxmlsv);

      if (dxml || flags) {
          if (virDomainRestoreFlags(con, from, dxml, flags) < 0)
              _croak_error();
      } else {
          if (virDomainRestore(con, from) < 0)
              _croak_error();
      }


SV *
get_save_image_xml_description(con, file, flags=0)
      virConnectPtr con;
      const char *file;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virDomainSaveImageGetXMLDesc(con, file, flags)))
	 _croak_error();
      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
define_save_image_xml(con, file, xml, flags=0)
      virConnectPtr con;
      const char *file;
      const char *xml;
      unsigned int flags;
    PPCODE:
      if (virDomainSaveImageDefineXML(con, file, xml, flags) < 0)
          _croak_error();



unsigned long
_get_library_version(void)
 PREINIT:
      unsigned long version;
   CODE:
      if (virGetVersion(&version, NULL, NULL) < 0)
          _croak_error();
      RETVAL = version;
  OUTPUT:
      RETVAL


unsigned long
_get_conn_version(con)
      virConnectPtr con;
 PREINIT:
      unsigned long version;
   CODE:
      if (virConnectGetVersion(con, &version) < 0)
          _croak_error();
      RETVAL = version;
  OUTPUT:
      RETVAL


unsigned long
_get_conn_library_version(con)
      virConnectPtr con;
 PREINIT:
      unsigned long version;
   CODE:
      if (virConnectGetLibVersion(con, &version) < 0)
          _croak_error();
      RETVAL = version;
  OUTPUT:
      RETVAL


int
is_encrypted(conn)
      virConnectPtr conn;
    CODE:
      if ((RETVAL = virConnectIsEncrypted(conn)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_secure(conn)
      virConnectPtr conn;
    CODE:
      if ((RETVAL = virConnectIsSecure(conn)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_alive(conn)
      virConnectPtr conn;
    CODE:
      if ((RETVAL = virConnectIsAlive(conn)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
set_keep_alive(conn, interval, count)
      virConnectPtr conn;
      int interval;
      unsigned int count;
  PPCODE:
      if (virConnectSetKeepAlive(conn, interval, count) < 0)
          _croak_error();


const char *
get_type(con)
      virConnectPtr con;
   CODE:
      RETVAL = virConnectGetType(con);
 OUTPUT:
      RETVAL


char *
get_uri(con)
      virConnectPtr con;
   CODE:
      RETVAL = virConnectGetURI(con);
 OUTPUT:
      RETVAL


char *
get_sysinfo(con, flags=0)
      virConnectPtr con;
      unsigned int flags;
   CODE:
      RETVAL = virConnectGetSysinfo(con, flags);
 OUTPUT:
      RETVAL


HV *
get_node_info(con)
      virConnectPtr con;
  PREINIT:
      virNodeInfo info;
    CODE:
      if (virNodeGetInfo(con, &info) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "model", 5, newSVpv(info.model, 0), 0);
      (void)hv_store (RETVAL, "memory", 6, newSViv(info.memory), 0);
      (void)hv_store (RETVAL, "cpus", 4, newSViv(info.cpus), 0);
      (void)hv_store (RETVAL, "mhz", 3, newSViv(info.mhz), 0);
      (void)hv_store (RETVAL, "nodes", 5, newSViv(info.nodes), 0);
      (void)hv_store (RETVAL, "sockets", 7, newSViv(info.sockets), 0);
      (void)hv_store (RETVAL, "cores", 5, newSViv(info.cores), 0);
      (void)hv_store (RETVAL, "threads", 7, newSViv(info.threads), 0);
  OUTPUT:
      RETVAL


HV *
get_node_security_model(con)
      virConnectPtr con;
 PREINIT:
      virSecurityModel secmodel;
    CODE:
      if (virNodeGetSecurityModel(con, &secmodel) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "model", 5, newSVpv(secmodel.model, 0), 0);
      (void)hv_store (RETVAL, "doi", 3, newSVpv(secmodel.doi, 0), 0);
   OUTPUT:
      RETVAL


SV *
get_node_free_memory(con)
      virConnectPtr con;
PREINIT:
      unsigned long long mem;
   CODE:
      if ((mem = virNodeGetFreeMemory(con)) == 0)
          _croak_error();

      RETVAL = virt_newSVull(mem);
  OUTPUT:
      RETVAL


void
get_node_cells_free_memory(con, start, end)
      virConnectPtr con;
      int start;
      int end;
PREINIT:
      unsigned long long *mem;
      int i, num;
 PPCODE:
      Newx(mem, end-start, unsigned long long);
      if ((num = virNodeGetCellsFreeMemory(con, mem, start, end)) < 0) {
          Safefree(mem);
          _croak_error();
      }
      EXTEND(SP, num);
      for (i = 0 ; i < num ; i++) {
	SV *val = newSViv(mem[i]);
	PUSHs(sv_2mortal(val));
      }
      Safefree(mem);


HV *
get_node_cpu_stats(con, cpuNum=VIR_NODE_CPU_STATS_ALL_CPUS, flags=0)
      virConnectPtr con;
      int cpuNum;
      unsigned int flags;
PREINIT:
      virNodeCPUStatsPtr params;
      int nparams = 0;
      int i;
  CODE:
      if (virNodeGetCPUStats(con, cpuNum, NULL, &nparams, flags) < 0)
          _croak_error();

      Newx(params, nparams, virNodeCPUStats);
      if (virNodeGetCPUStats(con, cpuNum, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }
      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      for (i = 0 ; i < nparams ; i++) {
          if (strcmp(params[i].field, VIR_NODE_CPU_STATS_KERNEL) == 0) {
              (void)hv_store (RETVAL, "kernel", 6, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_CPU_STATS_USER) == 0) {
              (void)hv_store (RETVAL, "user", 4, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_CPU_STATS_IDLE) == 0) {
              (void)hv_store (RETVAL, "idle", 4, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_CPU_STATS_IOWAIT) == 0) {
              (void)hv_store (RETVAL, "iowait", 6, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_CPU_STATS_UTILIZATION) == 0) {
              (void)hv_store (RETVAL, "utilization", 11, virt_newSVull(params[i].value), 0);
          }
      }
      Safefree(params);
  OUTPUT:
      RETVAL


HV *
get_node_memory_stats(con, cellNum=VIR_NODE_MEMORY_STATS_ALL_CELLS, flags=0)
      virConnectPtr con;
      int cellNum;
      unsigned int flags;
PREINIT:
      virNodeMemoryStatsPtr params;
      int nparams = 0;
      int i;
  CODE:
      if (virNodeGetMemoryStats(con, cellNum, NULL, &nparams, flags) < 0)
          _croak_error();

      Newx(params, nparams, virNodeMemoryStats);
      if (virNodeGetMemoryStats(con, cellNum, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }
      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      for (i = 0 ; i < nparams ; i++) {
          if (strcmp(params[i].field, VIR_NODE_MEMORY_STATS_TOTAL) == 0) {
              (void)hv_store (RETVAL, "total", 6, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_MEMORY_STATS_FREE) == 0) {
              (void)hv_store (RETVAL, "free", 4, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_MEMORY_STATS_BUFFERS) == 0) {
              (void)hv_store (RETVAL, "buffers", 4, virt_newSVull(params[i].value), 0);
          } else if (strcmp(params[i].field, VIR_NODE_MEMORY_STATS_CACHED) == 0) {
              (void)hv_store (RETVAL, "cached", 6, virt_newSVull(params[i].value), 0);
          }
      }
      Safefree(params);
  OUTPUT:
      RETVAL


void
node_suspend_for_duration(conn, target, duration, flags)
      virConnectPtr conn;
      unsigned int target;
      SV *duration;
      unsigned int flags;
  PPCODE:
      if (virNodeSuspendForDuration(conn, target, virt_SvIVull(duration), flags) < 0)
          _croak_error();


char *
find_storage_pool_sources(con, type, srcspec, flags=0)
      virConnectPtr con;
      const char *type;
      const char *srcspec;
      unsigned int flags;
    CODE:
      if ((RETVAL = virConnectFindStoragePoolSources(con, type, srcspec, flags)) == NULL)
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_capabilities(con)
      virConnectPtr con;
PREINIT:
      char *xml;
   CODE:
      if (!(xml = virConnectGetCapabilities(con)))
          _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


SV *
compare_cpu(con, xml, flags=0)
      virConnectPtr con;
      char *xml;
      unsigned int flags;
PREINIT:
      int rc;
   CODE:
      if ((rc = virConnectCompareCPU(con, xml, flags)) < 0)
          _croak_error();

      RETVAL = newSViv(rc);
  OUTPUT:
      RETVAL


SV *
baseline_cpu(con, xml, flags=0)
      virConnectPtr con;
      SV *xml;
      unsigned int flags;
PREINIT:
      AV *xmllist;
      const char **xmlstr;
      int xmllen;
      int i;
      char *retxml;
   CODE:
      xmllist = (AV*)SvRV(xml);
      xmllen = av_len(xmllist) + 1;
      Newx(xmlstr, xmllen, const char *);
      for (i = 0 ; i < xmllen ; i++) {
          SV **doc = av_fetch(xmllist, i, 0);
          xmlstr[i] = SvPV_nolen(*doc);
      }

      if (!(retxml = virConnectBaselineCPU(con, xmlstr, xmllen, flags))) {
          Safefree(xmlstr);
          _croak_error();
      }

      Safefree(xmlstr);
      RETVAL = newSVpv(retxml, 0);
      free(retxml);
  OUTPUT:
      RETVAL


int
get_max_vcpus(con, type)
      virConnectPtr con;
      char *type;
    CODE:
      if ((RETVAL = virConnectGetMaxVcpus(con, type)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_hostname(con)
      virConnectPtr con;
 PREINIT:
      char *host;
    CODE:
      if (!(host = virConnectGetHostname(con)))
          _croak_error();

      RETVAL = newSVpv(host, 0);
      free(host);
  OUTPUT:
      RETVAL


int
num_of_domains(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfDomains(con)) < 0)
	_croak_error();
  OUTPUT:
      RETVAL


void
list_domain_ids(con, maxids)
      virConnectPtr con;
      int maxids
 PREINIT:
      int *ids;
      int i, nid;
  PPCODE:
      Newx(ids, maxids, int);
      if ((nid = virConnectListDomains(con, ids, maxids)) < 0) {
          Safefree(ids);
          _croak_error();
      }
      EXTEND(SP, nid);
      for (i = 0 ; i < nid ; i++) {
          PUSHs(sv_2mortal(newSViv(ids[i])));
      }
      Safefree(ids);


int
num_of_defined_domains(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfDefinedDomains(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_defined_domain_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int ndom;
      int i;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((ndom = virConnectListDefinedDomains(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, ndom);
      for (i = 0 ; i < ndom ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_networks(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfNetworks(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_network_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virConnectListNetworks(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_defined_networks(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfDefinedNetworks(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_defined_network_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int ndom;
      int i;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((ndom = virConnectListDefinedNetworks(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, ndom);
      for (i = 0 ; i < ndom ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_storage_pools(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfStoragePools(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_storage_pool_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virConnectListStoragePools(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_defined_storage_pools(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfDefinedStoragePools(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL

void
list_defined_storage_pool_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int ndom;
      int i;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((ndom = virConnectListDefinedStoragePools(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, ndom);
      for (i = 0 ; i < ndom ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_node_devices(con, cap, flags=0)
      virConnectPtr con;
      SV *cap;
      int flags
 PREINIT:
      const char *capname = NULL;
    CODE:
      if (SvOK(cap))
	  capname = SvPV_nolen(cap);
      if ((RETVAL = virNodeNumOfDevices(con, capname, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_node_device_names(con, cap, maxnames, flags=0)
      virConnectPtr con;
      SV *cap;
      int maxnames;
      int flags;
 PREINIT:
      char **names;
      int i, nnet;
      const char *capname = NULL;
  PPCODE:
      if (SvOK(cap))
	  capname = SvPV_nolen(cap);
      Newx(names, maxnames, char *);
      if ((nnet = virNodeListDevices(con, capname, names, maxnames, flags)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_interfaces(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfInterfaces(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_interface_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virConnectListInterfaces(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_defined_interfaces(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfDefinedInterfaces(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_defined_interface_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virConnectListDefinedInterfaces(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
num_of_secrets(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfSecrets(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_secret_uuids(con, maxuuids)
      virConnectPtr con;
      int maxuuids;
 PREINIT:
      char **uuids;
      int i, nsecret;
  PPCODE:
      Newx(uuids, maxuuids, char *);
      if ((nsecret = virConnectListSecrets(con, uuids, maxuuids)) < 0) {
          Safefree(uuids);
          _croak_error();
      }
      EXTEND(SP, nsecret);
      for (i = 0 ; i < nsecret ; i++) {
          PUSHs(sv_2mortal(newSVpv(uuids[i], 0)));
          free(uuids[i]);
      }
      Safefree(uuids);


int
num_of_nwfilters(con)
      virConnectPtr con;
    CODE:
      if ((RETVAL = virConnectNumOfNWFilters(con)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_nwfilter_names(con, maxnames)
      virConnectPtr con;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virConnectListNWFilters(con, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


SV *
domain_xml_from_native(con, configtype, configdata, flags=0)
      virConnectPtr con;
      const char *configtype;
      const char *configdata;
      unsigned int flags;
 PREINIT:
      char *xmldata;
    CODE:
      if (!(xmldata = virConnectDomainXMLFromNative(con, configtype, configdata, flags)))
          _croak_error();

      RETVAL = newSVpv(xmldata, 0);
      free(xmldata);
 OUTPUT:
      RETVAL


SV *
domain_xml_to_native(con, configtype, xmldata, flags=0)
      virConnectPtr con;
      const char *configtype;
      const char *xmldata;
      unsigned int flags;
 PREINIT:
      char *configdata;
    CODE:
      if (!(configdata = virConnectDomainXMLToNative(con, configtype, xmldata, flags)))
          _croak_error();

      RETVAL = newSVpv(configdata, 0);
      free(configdata);
 OUTPUT:
      RETVAL


void
domain_event_register(conref, cb)
      SV* conref;
      SV* cb;
PREINIT:
      AV *opaque;
      virConnectPtr con;
 PPCODE:
      con = (virConnectPtr)SvIV((SV*)SvRV(conref));
      opaque = newAV();
      SvREFCNT_inc(cb);
      SvREFCNT_inc(conref);
      av_push(opaque, conref);
      av_push(opaque, cb);
      if (virConnectDomainEventRegister(con, _domain_event_lifecycle_callback,
                                        opaque, _domain_event_free) < 0)
          _croak_error();


void
domain_event_deregister(con)
      virConnectPtr con;
 PPCODE:
      virConnectDomainEventDeregister(con, _domain_event_lifecycle_callback);


int
domain_event_register_any(conref, domref, eventID, cb)
      SV* conref;
      SV* domref;
      int eventID;
      SV* cb;
PREINIT:
      AV *opaque;
      virConnectPtr con;
      virDomainPtr dom;
      virConnectDomainEventGenericCallback callback;
    CODE:
      con = (virConnectPtr)SvIV((SV*)SvRV(conref));
      if (SvOK(domref)) {
          dom = (virDomainPtr)SvIV((SV*)SvRV(domref));
      } else {
          dom = NULL;
      }

      switch (eventID) {
      case VIR_DOMAIN_EVENT_ID_LIFECYCLE:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_lifecycle_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_REBOOT:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_generic_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_RTC_CHANGE:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_rtcchange_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_WATCHDOG:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_watchdog_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_IO_ERROR:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_io_error_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_IO_ERROR_REASON:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_io_error_reason_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_GRAPHICS:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_graphics_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_CONTROL_ERROR:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_generic_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_BLOCK_JOB:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_block_job_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_DISK_CHANGE:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_disk_change_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_TRAY_CHANGE:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_tray_change_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_PMSUSPEND:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_pmsuspend_callback);
          break;
      case VIR_DOMAIN_EVENT_ID_PMWAKEUP:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_pmwakeup_callback);
          break;
      default:
          callback = VIR_DOMAIN_EVENT_CALLBACK(_domain_event_generic_callback);
          break;
      }

      opaque = newAV();
      SvREFCNT_inc(cb);
      SvREFCNT_inc(conref);
      av_push(opaque, conref);
      av_push(opaque, cb);
      if ((RETVAL = virConnectDomainEventRegisterAny(con, dom, eventID, callback, opaque, _domain_event_free)) < 0)
          _croak_error();
OUTPUT:
      RETVAL


void
domain_event_deregister_any(con, callbackID)
      virConnectPtr con;
      int callbackID;
 PPCODE:
      virConnectDomainEventDeregisterAny(con, callbackID);


void
interface_change_begin(conn, flags=0)
      virConnectPtr conn;
      unsigned int flags;
    PPCODE:
      if (virInterfaceChangeBegin(conn, flags) < 0)
          _croak_error();


void
interface_change_commit(conn, flags=0)
      virConnectPtr conn;
      unsigned int flags;
    PPCODE:
      if (virInterfaceChangeCommit(conn, flags) < 0)
          _croak_error();


void
interface_change_rollback(conn, flags=0)
      virConnectPtr conn;
      unsigned int flags;
    PPCODE:
      if (virInterfaceChangeRollback(conn, flags) < 0)
          _croak_error();


void
DESTROY(con_rv)
      SV *con_rv;
 PREINIT:
      virConnectPtr con;
  PPCODE:
      con = (virConnectPtr)SvIV((SV*)SvRV(con_rv));
      if (con) {
	virConnectClose(con);
	sv_setiv((SV*)SvRV(con_rv), 0);
      }


MODULE = Sys::Virt::Domain  PACKAGE = Sys::Virt::Domain


virDomainPtr
_create(con, xml, flags=0)
      virConnectPtr con;
      const char *xml;
      unsigned int flags;
    CODE:
      if (flags) {
          if (!(RETVAL = virDomainCreateXML(con, xml, flags)))
              _croak_error();
      } else {
          if (!(RETVAL = virDomainCreateLinux(con, xml, 0)))
              _croak_error();
      }
  OUTPUT:
      RETVAL


virDomainPtr
_define_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virDomainDefineXML(con, xml)))
          _croak_error();
  OUTPUT:
      RETVAL


virDomainPtr
_lookup_by_id(con, id)
      virConnectPtr con;
      int id;
    CODE:
      if (!(RETVAL = virDomainLookupByID(con, id)))
          _croak_error();
  OUTPUT:
      RETVAL


virDomainPtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virDomainLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virDomainPtr
_lookup_by_uuid(con, uuid)
      virConnectPtr con;
      const unsigned char *uuid;
    CODE:
      if (!(RETVAL = virDomainLookupByUUID(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


virDomainPtr
_lookup_by_uuid_string(con, uuid)
      virConnectPtr con;
      const char *uuid;
    CODE:
      if (!(RETVAL = virDomainLookupByUUIDString(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


int
get_id(dom)
      virDomainPtr dom;
    CODE:
      RETVAL = virDomainGetID(dom);
  OUTPUT:
      RETVAL


SV *
get_uuid(dom)
      virDomainPtr dom;
  PREINIT:
      unsigned char rawuuid[VIR_UUID_BUFLEN];
    CODE:
      if ((virDomainGetUUID(dom, rawuuid)) < 0)
          _croak_error();

      RETVAL = newSVpv((char*)rawuuid, sizeof(rawuuid));
  OUTPUT:
      RETVAL


SV *
get_uuid_string(dom)
      virDomainPtr dom;
  PREINIT:
      char uuid[VIR_UUID_STRING_BUFLEN];
    CODE:
      if ((virDomainGetUUIDString(dom, uuid)) < 0)
          _croak_error();

      RETVAL = newSVpv(uuid, 0);
  OUTPUT:
      RETVAL


const char *
get_name(dom)
      virDomainPtr dom;
    CODE:
      if (!(RETVAL = virDomainGetName(dom)))
          _croak_error();
  OUTPUT:
      RETVAL


char *
get_metadata(dom, type, uri=&PL_sv_undef, flags=0)
      virDomainPtr dom;
      int type;
      SV *uri;
      unsigned int flags;
 PREINIT:
      const char *uristr = NULL;
    CODE:
      if (SvOK(uri))
	  uristr = SvPV_nolen(uri);

      if (!(RETVAL = virDomainGetMetadata(dom, type, uristr, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


void
set_metadata(dom, type, metadata=&PL_sv_undef, key=&PL_sv_undef, uri=&PL_sv_undef, flags=0)
      virDomainPtr dom;
      int type;
      SV *metadata;
      SV *key;
      SV *uri;
      unsigned int flags;
 PREINIT:
      const char *metadatastr = NULL;
      const char *keystr = NULL;
      const char *uristr = NULL;
  PPCODE:
      if (SvOK(metadata))
	  metadatastr = SvPV_nolen(metadata);
      if (SvOK(key))
	  keystr = SvPV_nolen(key);
      if (SvOK(uri))
	  uristr = SvPV_nolen(uri);

      if (virDomainSetMetadata(dom, type, metadatastr, keystr, uristr, flags) < 0)
          _croak_error();



int
is_active(dom)
      virDomainPtr dom;
    CODE:
      if ((RETVAL = virDomainIsActive(dom)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_persistent(dom)
      virDomainPtr dom;
    CODE:
      if ((RETVAL = virDomainIsPersistent(dom)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_updated(dom)
      virDomainPtr dom;
    CODE:
      if ((RETVAL = virDomainIsUpdated(dom)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
suspend(dom)
      virDomainPtr dom;
  PPCODE:
      if ((virDomainSuspend(dom)) < 0)
          _croak_error();


void
resume(dom)
      virDomainPtr dom;
  PPCODE:
      if ((virDomainResume(dom)) < 0)
          _croak_error();


void
pm_wakeup(dom, flags)
      virDomainPtr dom;
      unsigned int flags;
  PPCODE:
      if ((virDomainPMWakeup(dom, flags)) < 0)
          _croak_error();


void
save(dom, to, dxmlsv=&PL_sv_undef, flags=0)
      virDomainPtr dom;
      const char *to;
      SV *dxmlsv;
      unsigned int flags;
PREINIT:
      const char *dxml = NULL;
  PPCODE:
      if (SvOK(dxmlsv))
	  dxml = SvPV_nolen(dxmlsv);

      if (dxml || flags) {
          if ((virDomainSaveFlags(dom, to, dxml, flags)) < 0)
              _croak_error();
      } else {
          if ((virDomainSave(dom, to)) < 0)
              _croak_error();
      }


void
managed_save(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PPCODE:
      if ((virDomainManagedSave(dom, flags)) < 0)
          _croak_error();


int
has_managed_save_image(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    CODE:
      if ((RETVAL = virDomainHasManagedSaveImage(dom, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
managed_save_remove(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PPCODE:
      if ((virDomainManagedSaveRemove(dom, flags)) < 0)
          _croak_error();


void
core_dump(dom, to, flags=0)
      virDomainPtr dom;
      const char *to
      unsigned int flags;
    PPCODE:
      if (virDomainCoreDump(dom, to, flags) < 0)
          _croak_error();


HV *
get_info(dom)
      virDomainPtr dom;
  PREINIT:
      virDomainInfo info;
    CODE:
      if (virDomainGetInfo(dom, &info) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "state", 5, newSViv(info.state), 0);
      (void)hv_store (RETVAL, "maxMem", 6, newSViv(info.maxMem), 0);
      (void)hv_store (RETVAL, "memory", 6, newSViv(info.memory), 0);
      (void)hv_store (RETVAL, "nrVirtCpu", 9, newSViv(info.nrVirtCpu), 0);
      (void)hv_store (RETVAL, "cpuTime", 7, virt_newSVull(info.cpuTime), 0);
  OUTPUT:
      RETVAL


HV *
get_control_info(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PREINIT:
      virDomainControlInfo info;
    CODE:
      if (virDomainGetControlInfo(dom, &info, flags) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "state", 5, newSViv(info.state), 0);
      (void)hv_store (RETVAL, "details", 7, newSViv(info.details), 0);
      (void)hv_store (RETVAL, "stateTime", 9, virt_newSVull(info.stateTime), 0);
  OUTPUT:
      RETVAL


void
get_state(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
PREINIT:
      int state;
      int reason;
 PPCODE:
      if (virDomainGetState(dom, &state, &reason, flags) < 0)
          _croak_error();

      XPUSHs(sv_2mortal(newSViv(state)));
      XPUSHs(sv_2mortal(newSViv(reason)));


void
open_console(dom, st, devname, flags=0)
      virDomainPtr dom;
      virStreamPtr st;
      SV *devname;
      unsigned int flags;
 PREINIT:
      const char *devnamestr = NULL;
  PPCODE:
      if (SvOK(devname))
          devnamestr = SvPV_nolen(devname);

      if (virDomainOpenConsole(dom, devnamestr, st, flags) < 0)
          _croak_error();


void
open_graphics(dom, idx, fd, flags=0)
      virDomainPtr dom;
      unsigned int idx;
      int fd;
      unsigned int flags;
  PPCODE:
      if (virDomainOpenGraphics(dom, idx, fd, flags) < 0)
          _croak_error();


void
screenshot(dom, st, screen, flags=0)
      virDomainPtr dom;
      virStreamPtr st;
      unsigned int screen;
      unsigned int flags;
  PPCODE:
      if (virDomainScreenshot(dom, st, screen, flags) < 0)
          _croak_error();


HV *
get_block_info(dom, dev, flags=0)
      virDomainPtr dom;
      const char *dev;
      unsigned int flags;
  PREINIT:
      virDomainBlockInfo info;
    CODE:
      if (virDomainGetBlockInfo(dom, dev, &info, flags) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "capacity", 8, virt_newSVull(info.capacity), 0);
      (void)hv_store (RETVAL, "allocation", 10, virt_newSVull(info.allocation), 0);
      (void)hv_store (RETVAL, "physical", 8, virt_newSVull(info.physical), 0);
  OUTPUT:
      RETVAL


HV *
get_job_info(dom)
      virDomainPtr dom;
  PREINIT:
      virDomainJobInfo info;
    CODE:
      if (virDomainGetJobInfo(dom, &info) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "type", 4, newSViv(info.type), 0);
      (void)hv_store (RETVAL, "timeElapsed", 11, virt_newSVull(info.timeElapsed), 0);
      (void)hv_store (RETVAL, "timeRemaining", 13, virt_newSVull(info.timeRemaining), 0);
      (void)hv_store (RETVAL, "dataTotal", 9, virt_newSVull(info.dataTotal), 0);
      (void)hv_store (RETVAL, "dataProcessed", 13, virt_newSVull(info.dataProcessed), 0);
      (void)hv_store (RETVAL, "dataRemaining", 13, virt_newSVull(info.dataRemaining), 0);
      (void)hv_store (RETVAL, "memTotal", 8, virt_newSVull(info.memTotal), 0);
      (void)hv_store (RETVAL, "memProcessed", 12, virt_newSVull(info.memProcessed), 0);
      (void)hv_store (RETVAL, "memRemaining", 12, virt_newSVull(info.memRemaining), 0);
      (void)hv_store (RETVAL, "fileTotal", 9, virt_newSVull(info.fileTotal), 0);
      (void)hv_store (RETVAL, "fileProcessed", 13, virt_newSVull(info.fileProcessed), 0);
      (void)hv_store (RETVAL, "fileRemaining", 13, virt_newSVull(info.fileRemaining), 0);
  OUTPUT:
      RETVAL


void
abort_job(dom)
      virDomainPtr dom;
    PPCODE:
      if (virDomainAbortJob(dom) < 0)
          _croak_error();


void
abort_block_job(dom, path, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned int flags;
    PPCODE:
      if (virDomainBlockJobAbort(dom, path, flags) < 0)
          _croak_error();


HV *
get_block_job_info(dom, path, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned int flags;
  PREINIT:
      virDomainBlockJobInfo info;
    CODE:
      if (virDomainGetBlockJobInfo(dom, path, &info, flags) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "type", 4, newSViv(info.type), 0);
      (void)hv_store (RETVAL, "bandwidth", 9, virt_newSVull(info.bandwidth), 0);
      (void)hv_store (RETVAL, "cur", 3, virt_newSVull(info.cur), 0);
      (void)hv_store (RETVAL, "end", 3, virt_newSVull(info.end), 0);
  OUTPUT:
      RETVAL


void
set_block_job_speed(dom, path, bandwidth, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned long bandwidth;
      unsigned int flags;
    PPCODE:
      if (virDomainBlockJobSetSpeed(dom, path, bandwidth, flags) < 0)
          _croak_error();


void
block_pull(dom, path, bandwidth, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned long bandwidth;
      unsigned int flags;
    PPCODE:
      if (virDomainBlockPull(dom, path, bandwidth, flags) < 0)
          _croak_error();


void
block_rebase(dom, path, base, bandwidth, flags=0)
      virDomainPtr dom;
      const char *path;
      const char *base;
      unsigned long bandwidth;
      unsigned int flags;
    PPCODE:
      if (virDomainBlockRebase(dom, path, base, bandwidth, flags) < 0)
          _croak_error();


void
get_disk_errors(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
 PREINIT:
      virDomainDiskErrorPtr errors;
      unsigned int maxerrors;
      int ret;
      int i;
  PPCODE:
      if ((ret = virDomainGetDiskErrors(dom, NULL, 0, 0)) < 0)
          _croak_error();
      maxerrors = ret;
      Newx(errors, maxerrors, virDomainDiskError);
      if ((ret = virDomainGetDiskErrors(dom, errors, maxerrors, flags)) < 0) {
          Safefree(errors);
          _croak_error();
      }
      EXTEND(SP, ret);
      for (i = 0 ; i < ret ; i++) {
          HV *rec = newHV();
          (void)hv_store(rec, "path", 4, newSVpv(errors[i].disk, 0), 0);
          (void)hv_store(rec, "error", 5, newSViv(errors[i].error), 0);
          PUSHs(newRV_noinc((SV *)rec));
      }

      Safefree(errors);


HV *
get_scheduler_parameters(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
      char *type;
    CODE:
      if (!(type = virDomainGetSchedulerType(dom, &nparams)))
          _croak_error();

      free(type);
      Newx(params, nparams, virTypedParameter);
      if (flags) {
          if (virDomainGetSchedulerParametersFlags(dom, params, &nparams, flags) < 0) {
              Safefree(params);
              _croak_error();
          }
      } else {
          if (virDomainGetSchedulerParameters(dom, params, &nparams) < 0) {
              Safefree(params);
              _croak_error();
          }
      }
      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_scheduler_parameters(dom, newparams, flags=0)
      virDomainPtr dom;
      HV *newparams;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
      char *type;
    PPCODE:
      if (!(type = virDomainGetSchedulerType(dom, &nparams)))
          _croak_error();

      free(type);
      Newx(params, nparams, virTypedParameter);
      if (flags) {
          if (virDomainGetSchedulerParametersFlags(dom, params, &nparams, flags) < 0) {
              Safefree(params);
              _croak_error();
          }
      } else {
          if (virDomainGetSchedulerParameters(dom, params, &nparams) < 0) {
              Safefree(params);
              _croak_error();
          }
      }
      vir_typed_param_from_hv(newparams, params, nparams);
      if (flags) {
          if (virDomainSetSchedulerParametersFlags(dom, params, nparams, flags) < 0)
              _croak_error();
      } else {
          if (virDomainSetSchedulerParameters(dom, params, nparams) < 0)
              _croak_error();
      }
      Safefree(params);


HV *
get_memory_parameters(dom)
      virDomainPtr dom;
  PREINIT:
      virMemoryParameter *params;
      int nparams;
    CODE:
      nparams = 0;
      if (virDomainGetMemoryParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virMemoryParameter);

      if (virDomainGetMemoryParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_memory_parameters(dom, newparams)
      virDomainPtr dom;
      HV *newparams;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    PPCODE:
      nparams = 0;
      if (virDomainGetMemoryParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virMemoryParameter);

      if (virDomainGetMemoryParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      vir_typed_param_from_hv(newparams, params, nparams);

      if (virDomainSetMemoryParameters(dom, params, nparams, 0) < 0)
          _croak_error();
      Safefree(params);


HV *
get_numa_parameters(dom)
      virDomainPtr dom;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    CODE:
      nparams = 0;
      if (virDomainGetNumaParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virTypedParameter);

      if (virDomainGetNumaParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_numa_parameters(dom, newparams)
      virDomainPtr dom;
      HV *newparams;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    PPCODE:
      nparams = 0;
      if (virDomainGetNumaParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virTypedParameter);

      if (virDomainGetNumaParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      vir_typed_param_from_hv(newparams, params, nparams);

      if (virDomainSetNumaParameters(dom, params, nparams, 0) < 0)
          _croak_error();
      Safefree(params);


HV *
get_blkio_parameters(dom)
      virDomainPtr dom;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    CODE:
      nparams = 0;
      if (virDomainGetBlkioParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virBlkioParameter);

      if (virDomainGetBlkioParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_blkio_parameters(dom, newparams)
      virDomainPtr dom;
      HV *newparams;
  PREINIT:
      virTypedParameter *params;
      int nparams;
      int needString;
    PPCODE:
      nparams = 0;
      if (virDomainGetBlkioParameters(dom, NULL, &nparams, 0) < 0)
          _croak_error();

      Newx(params, nparams, virBlkioParameter);

      if (virDomainGetBlkioParameters(dom, params, &nparams, 0) < 0) {
          Safefree(params);
          _croak_error();
      }

      needString = vir_typed_param_from_hv(newparams, params, nparams);

      if (virDomainSetBlkioParameters(dom, params, nparams,
                                      needString ? VIR_TYPED_PARAM_STRING_OKAY: 0) < 0)
          _croak_error();
      Safefree(params);


unsigned long
get_max_memory(dom)
      virDomainPtr dom;
    CODE:
      if (!(RETVAL = virDomainGetMaxMemory(dom)))
          _croak_error();
  OUTPUT:
      RETVAL


void
set_max_memory(dom, val)
      virDomainPtr dom;
      unsigned long val;
  PPCODE:
      if (virDomainSetMaxMemory(dom, val) < 0)
	_croak_error();


void
set_memory(dom, val, flags=0)
      virDomainPtr dom;
      unsigned long val;
      unsigned int flags;
  PPCODE:
      if (flags) {
          if (virDomainSetMemoryFlags(dom, val, flags) < 0)
              _croak_error();
      } else {
          if (virDomainSetMemory(dom, val) < 0)
              _croak_error();
      }


int
get_max_vcpus(dom)
      virDomainPtr dom;
    CODE:
      if (!(RETVAL = virDomainGetMaxVcpus(dom)))
          _croak_error();
  OUTPUT:
      RETVAL


void
set_vcpus(dom, num, flags=0)
      virDomainPtr dom;
      int num;
      int flags;
  PPCODE:
      if (flags) {
          if (virDomainSetVcpusFlags(dom, num, flags) < 0)
              _croak_error();
      } else {
          if (virDomainSetVcpus(dom, num) < 0)
              _croak_error();
      }


int
get_vcpus(dom, flags=0)
    virDomainPtr dom;
    int flags;
  CODE:
    if ((RETVAL = virDomainGetVcpusFlags(dom, flags)) < 0)
        _croak_error();
OUTPUT:
    RETVAL


void
set_autostart(dom, autostart)
      virDomainPtr dom;
      int autostart;
  PPCODE:
      if (virDomainSetAutostart(dom, autostart) < 0)
          _croak_error();


int
get_autostart(dom)
      virDomainPtr dom;
 PREINIT:
      int autostart;
    CODE:
      if (virDomainGetAutostart(dom, &autostart) < 0)
          _croak_error();
      RETVAL = autostart;
  OUTPUT:
      RETVAL


char *
get_scheduler_type(dom)
      virDomainPtr dom;
PREINIT:
      int nparams;
    CODE:
      if ((RETVAL = virDomainGetSchedulerType(dom, &nparams)) == NULL)
          _croak_error();
   OUTPUT:
      RETVAL


SV *
get_os_type(dom)
      virDomainPtr dom;
  PREINIT:
      char *type;
    CODE:
      if (!(type = virDomainGetOSType(dom)))
          _croak_error();

      RETVAL = newSVpv(type, 0);
      free(type);
  OUTPUT:
      RETVAL


SV *
get_xml_description(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virDomainGetXMLDesc(dom, flags)))
          _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
shutdown(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (flags) {
          if (virDomainShutdownFlags(dom, flags) < 0)
              _croak_error();
      } else {
          if (virDomainShutdown(dom) < 0)
              _croak_error();
      }


void
reboot(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (virDomainReboot(dom, flags) < 0)
          _croak_error();


void
pm_suspend_for_duration(dom, target, duration, flags)
      virDomainPtr dom;
      unsigned int target;
      SV *duration;
      unsigned int flags;
  PPCODE:
      if (virDomainPMSuspendForDuration(dom, target, virt_SvIVull(duration), flags) < 0)
          _croak_error();


void
reset(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (virDomainReset(dom, flags) < 0)
          _croak_error();


void
inject_nmi(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (virDomainInjectNMI(dom, flags) < 0)
          _croak_error();


void
undefine(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (flags) {
          if (virDomainUndefineFlags(dom, flags) < 0)
              _croak_error();
      } else {
          if (virDomainUndefine(dom) < 0)
              _croak_error();
      }


void
create(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    PPCODE:
      if (flags) {
          if (virDomainCreateWithFlags(dom, flags) < 0)
              _croak_error();
      } else {
          if (virDomainCreate(dom) < 0)
              _croak_error();
      }


virDomainPtr
migrate(dom, destcon, flags=0, dname=&PL_sv_undef, uri=&PL_sv_undef, bandwidth=0)
     virDomainPtr dom;
     virConnectPtr destcon;
     unsigned long flags;
     SV *dname;
     SV *uri;
     unsigned long bandwidth;
PREINIT:
     const char *dnamestr = NULL;
     const char *uristr = NULL;
   CODE:
     if (SvOK(dname))
         dnamestr = SvPV_nolen(dname);
     if (SvOK(uri))
         uristr = SvPV_nolen(uri);

     if ((RETVAL = virDomainMigrate(dom, destcon, flags, dnamestr, uristr, bandwidth)) == NULL)
         _croak_error();
 OUTPUT:
     RETVAL


void
migrate_to_uri(dom, desturi, flags=0, dname=&PL_sv_undef, bandwidth=0)
     virDomainPtr dom;
     const char *desturi;
     unsigned long flags;
     SV *dname;
     unsigned long bandwidth;
PREINIT:
     const char *dnamestr = NULL;
  PPCODE:
     if (SvOK(dname))
         dnamestr = SvPV_nolen(dname);

     if (virDomainMigrateToURI(dom, desturi, flags, dnamestr, bandwidth) < 0)
         _croak_error();


virDomainPtr
migrate2(dom, destcon, dxml=&PL_sv_undef, flags=0, dname=&PL_sv_undef, uri=&PL_sv_undef, bandwidth=0)
     virDomainPtr dom;
     virConnectPtr destcon;
     SV *dxml;
     unsigned long flags;
     SV *dname;
     SV *uri;
     unsigned long bandwidth;
PREINIT:
     const char *dnamestr = NULL;
     const char *uristr = NULL;
     const char *dxmlstr = NULL;
   CODE:
     if (SvOK(dxml))
         dxmlstr = SvPV_nolen(dxml);
     if (SvOK(dname))
         dnamestr = SvPV_nolen(dname);
     if (SvOK(uri))
         uristr = SvPV_nolen(uri);

     if ((RETVAL = virDomainMigrate2(dom, destcon, dxmlstr,
                                     flags, dnamestr, uristr, bandwidth)) == NULL)
       _croak_error();
 OUTPUT:
     RETVAL


void
migrate_to_uri2(dom, dconnuri, miguri=&PL_sv_undef, dxml=&PL_sv_undef, flags=0, dname=&PL_sv_undef, bandwidth=0)
     virDomainPtr dom;
     const char *dconnuri;
     SV *miguri;
     SV *dxml;
     unsigned long flags;
     SV *dname;
     unsigned long bandwidth;
PREINIT:
     const char *miguristr = NULL;
     const char *dxmlstr = NULL;
     const char *dnamestr = NULL;
  PPCODE:
     if (SvOK(dxml))
         dxmlstr = SvPV_nolen(dxml);
     if (SvOK(miguri))
         miguristr = SvPV_nolen(miguri);
     if (SvOK(dname))
         dnamestr = SvPV_nolen(dname);

     if (virDomainMigrateToURI2(dom, dconnuri, miguristr, dxmlstr,
                                flags, dnamestr, bandwidth) < 0)
         _croak_error();


void
migrate_set_max_downtime(dom, downtime, flags=0)
     virDomainPtr dom;
     SV *downtime;
     unsigned int flags;
 PREINIT:
     unsigned long long downtimeVal;
  PPCODE:
     downtimeVal = virt_SvIVull(downtime);
     if (virDomainMigrateSetMaxDowntime(dom, downtimeVal, flags) < 0)
         _croak_error();


void
migrate_set_max_speed(dom, bandwidth, flags=0)
     virDomainPtr dom;
     unsigned long bandwidth;
     unsigned int flags;
  PPCODE:
     if (virDomainMigrateSetMaxSpeed(dom, bandwidth, flags) < 0)
         _croak_error();


unsigned long
migrate_get_max_speed(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PREINIT:
      unsigned long speed;
    CODE:
      if (virDomainMigrateGetMaxSpeed(dom, &speed, flags) < 0)
          _croak_error();

      RETVAL = speed;
  OUTPUT:
      RETVAL


void
attach_device(dom, xml, flags=0)
      virDomainPtr dom;
      const char *xml;
      unsigned int flags;
    PPCODE:
      if (flags) {
          if (virDomainAttachDeviceFlags(dom, xml, flags) < 0)
              _croak_error();
      } else {
          if (virDomainAttachDevice(dom, xml) < 0)
              _croak_error();
      }


void
detach_device(dom, xml, flags=0)
      virDomainPtr dom;
      const char *xml;
      unsigned int flags;
    PPCODE:
      if (flags) {
          if (virDomainDetachDeviceFlags(dom, xml, flags) < 0)
              _croak_error();
      } else {
          if (virDomainDetachDevice(dom, xml) < 0)
              _croak_error();
      }


void
update_device(dom, xml, flags=0)
      virDomainPtr dom;
      const char *xml;
      unsigned int flags;
    PPCODE:
      if (virDomainUpdateDeviceFlags(dom, xml, flags) < 0)
          _croak_error();


HV *
get_block_iotune(dom, disk, flags=0)
      virDomainPtr dom;
      const char *disk;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    CODE:
      nparams = 0;
      RETVAL = NULL;
      if (virDomainGetBlockIoTune(dom, disk, NULL, &nparams, flags) < 0)
          _croak_error();

      Newx(params, nparams, virTypedParameter);
      if (virDomainGetBlockIoTune(dom, disk, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }

      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_block_iotune(dom, disk, newparams, flags=0)
      virDomainPtr dom;
      const char *disk;
      HV *newparams;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
  PPCODE:
      nparams = 0;
      if (virDomainGetBlockIoTune(dom, disk, NULL, &nparams, flags) < 0)
          _croak_error();
      Newx(params, nparams, virTypedParameter);

      if (virDomainGetBlockIoTune(dom, disk, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }

      vir_typed_param_from_hv(newparams, params, nparams);
      if (virDomainSetBlockIoTune(dom, disk, params, nparams, flags) < 0)
          _croak_error();


HV *
get_interface_parameters(dom, intf, flags=0)
      virDomainPtr dom;
      const char *intf;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
    CODE:
      nparams = 0;
      RETVAL = NULL;
      if (virDomainGetInterfaceParameters(dom, intf, NULL, &nparams, flags) < 0)
          _croak_error();

      Newx(params, nparams, virTypedParameter);
      if (virDomainGetInterfaceParameters(dom, intf, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }

      RETVAL = vir_typed_param_to_hv(params, nparams);
      Safefree(params);
  OUTPUT:
      RETVAL


void
set_interface_parameters(dom, intf, newparams, flags=0)
      virDomainPtr dom;
      const char *intf;
      HV *newparams;
      unsigned int flags;
  PREINIT:
      virTypedParameter *params;
      int nparams;
  PPCODE:
      nparams = 0;
      if (virDomainGetInterfaceParameters(dom, intf, NULL, &nparams, flags) < 0)
          _croak_error();
      Newx(params, nparams, virTypedParameter);

      if (virDomainGetInterfaceParameters(dom, intf, params, &nparams, flags) < 0) {
          Safefree(params);
          _croak_error();
      }

      vir_typed_param_from_hv(newparams, params, nparams);
      if (virDomainSetInterfaceParameters(dom, intf, params, nparams, flags) < 0)
          _croak_error();


HV *
block_stats(dom, path, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned int flags;
  PREINIT:
      virDomainBlockStatsStruct stats;
      virTypedParameter *params;
      int nparams;
      unsigned int i;
      const char *field;
    CODE:
      nparams = 0;
      RETVAL = NULL;
      if (virDomainBlockStatsFlags(dom, path, NULL, &nparams, flags) < 0) {
          virErrorPtr err = virGetLastError();
          if (err && err->code == VIR_ERR_NO_SUPPORT && !flags) {
              if (virDomainBlockStats(dom, path, &stats, sizeof(stats)) < 0)
                  _croak_error();

              RETVAL = (HV *)sv_2mortal((SV*)newHV());
              (void)hv_store (RETVAL, "rd_req", 6, virt_newSVll(stats.rd_req), 0);
              (void)hv_store (RETVAL, "rd_bytes", 8, virt_newSVll(stats.rd_bytes), 0);
              (void)hv_store (RETVAL, "wr_req", 6, virt_newSVll(stats.wr_req), 0);
              (void)hv_store (RETVAL, "wr_bytes", 8, virt_newSVll(stats.wr_bytes), 0);
              (void)hv_store (RETVAL, "errs", 4, virt_newSVll(stats.errs), 0);
          } else {
              _croak_error();
          }
      } else {
          Newx(params, nparams, virTypedParameter);

          if (virDomainBlockStatsFlags(dom, path, params, &nparams, flags) < 0) {
              Safefree(params);
              _croak_error();
          }

          RETVAL = vir_typed_param_to_hv(params, nparams);
          for (i = 0 ; i < nparams ; i++) {
              field = NULL;
              /* For back compat with previous hash above */
              if (strcmp(params[i].field, "rd_operations") == 0)
                  field = "rd_reqs";
              else if (strcmp(params[i].field, "wr_operations") == 0)
                  field = "wr_reqs";
              else if (strcmp(params[i].field, "flush_operations") == 0)
                  field = "flush_reqs";
              if (field) {
                  SV *val = hv_delete(RETVAL, params[i].field, strlen(params[i].field), 0);
                  SvREFCNT_inc(val);
                  (void)hv_store(RETVAL, field, strlen(field), val, 0);
              }
          }
          Safefree(params);
      }
  OUTPUT:
      RETVAL


HV *
interface_stats(dom, path)
      virDomainPtr dom;
      const char *path;
  PREINIT:
      virDomainInterfaceStatsStruct stats;
    CODE:
      if (virDomainInterfaceStats(dom, path, &stats, sizeof(stats)) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "rx_bytes", 8, virt_newSVll(stats.rx_bytes), 0);
      (void)hv_store (RETVAL, "rx_packets", 10, virt_newSVll(stats.rx_packets), 0);
      (void)hv_store (RETVAL, "rx_errs", 7, virt_newSVll(stats.rx_errs), 0);
      (void)hv_store (RETVAL, "rx_drop", 7, virt_newSVll(stats.rx_drop), 0);
      (void)hv_store (RETVAL, "tx_bytes", 8, virt_newSVll(stats.tx_bytes), 0);
      (void)hv_store (RETVAL, "tx_packets", 10, virt_newSVll(stats.tx_packets), 0);
      (void)hv_store (RETVAL, "tx_errs", 7, virt_newSVll(stats.tx_errs), 0);
      (void)hv_store (RETVAL, "tx_drop", 7, virt_newSVll(stats.tx_drop), 0);
  OUTPUT:
      RETVAL


HV *
memory_stats(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
  PREINIT:
      virDomainMemoryStatPtr stats;
      int i, got;
    CODE:
      Newx(stats, VIR_DOMAIN_MEMORY_STAT_NR, virDomainMemoryStatStruct);
      if ((got = virDomainMemoryStats(dom, stats, VIR_DOMAIN_MEMORY_STAT_NR, flags)) < 0) {
          Safefree(stats);
          _croak_error();
      }
      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      for (i = 0 ; i < got ; i++) {
          switch (stats[i].tag) {
          case VIR_DOMAIN_MEMORY_STAT_SWAP_IN:
              (void)hv_store (RETVAL, "swap_in", 7, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_SWAP_OUT:
              (void)hv_store (RETVAL, "swap_out", 8, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_MAJOR_FAULT:
              (void)hv_store (RETVAL, "major_fault", 11, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_MINOR_FAULT:
              (void)hv_store (RETVAL, "minor_fault", 11, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_UNUSED:
              (void)hv_store (RETVAL, "unused", 6, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_AVAILABLE:
              (void)hv_store (RETVAL, "available", 9, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_ACTUAL_BALLOON:
              (void)hv_store (RETVAL, "actual_balloon", 14, virt_newSVll(stats[i].val), 0);
              break;

          case VIR_DOMAIN_MEMORY_STAT_RSS:
              (void)hv_store (RETVAL, "rss", 14, virt_newSVll(stats[i].val), 0);
              break;
          }
      }
      Safefree(stats);
  OUTPUT:
      RETVAL


void
send_key(dom, codeset, holdtime, keycodesSV, flags=0)
      virDomainPtr dom;
      unsigned int codeset;
      unsigned int holdtime;
      SV *keycodesSV;
      unsigned int flags;
PREINIT:
      AV *keycodesAV;
      unsigned int *keycodes;
      int nkeycodes;
      int i;
   PPCODE:
      if (!SvROK(keycodesSV))
          return;
      keycodesAV = (AV*)SvRV(keycodesSV);
      nkeycodes = av_len(keycodesAV) + 1;
      Newx(keycodes, nkeycodes, unsigned int);

      for (i = 0 ; i < nkeycodes ; i++) {
          SV **code = av_fetch(keycodesAV, i, 0);
          keycodes[i] = SvIV(*code);
      }

      if (virDomainSendKey(dom, codeset, holdtime, keycodes, nkeycodes, flags) < 0) {
          Safefree(keycodes);
          _croak_error();
      }

      Safefree(keycodes);


void
block_resize(dom, disk, size, flags=0)
      virDomainPtr dom;
      const char *disk;
      SV *size;
      unsigned int flags;
  PPCODE:
      if (virDomainBlockResize(dom, disk, virt_SvIVull(size), flags) < 0)
          _croak_error();


SV *
block_peek(dom, path, offset, size, flags=0)
      virDomainPtr dom;
      const char *path;
      unsigned int offset;
      size_t size;
      unsigned int flags;
  PREINIT:
      char *buf;
    CODE:
      Newx(buf, size, char);
      if (virDomainBlockPeek(dom, path, offset, size, buf, flags) < 0) {
          Safefree(buf);
          _croak_error();
      }
      RETVAL = newSVpvn(buf, size);
  OUTPUT:
      RETVAL


SV *
memory_peek(dom, offset, size, flags=0)
      virDomainPtr dom;
      unsigned int offset;
      size_t size;
      unsigned int flags;
  PREINIT:
      char *buf;
    CODE:
      Newx(buf, size, char);
      if (virDomainMemoryPeek(dom, offset, size, buf, flags) < 0) {
          Safefree(buf);
          _croak_error();
      }
      RETVAL = newSVpvn(buf, size);
  OUTPUT:
      RETVAL


HV *
get_security_label(dom)
      virDomainPtr dom;
 PREINIT:
      virSecurityLabel seclabel;
    CODE:
      if (virDomainGetSecurityLabel(dom, &seclabel) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "label", 5, newSVpv(seclabel.label, 0), 0);
      (void)hv_store (RETVAL, "enforcing", 9, newSViv(seclabel.enforcing), 0);
   OUTPUT:
      RETVAL


void
get_cpu_stats(dom, start_cpu, ncpus, flags=0)
      virDomainPtr dom;
      int start_cpu;
      unsigned int ncpus;
      unsigned int flags;
 PREINIT:
      virTypedParameterPtr params;
      unsigned int nparams;
      int ret;
      int i;
   PPCODE:
      if ((ret = virDomainGetCPUStats(dom, NULL, 0, 0, 1, 0)) < 0)
          _croak_error();
      nparams = ret;

      if (ncpus == 0) {
          if ((ret = virDomainGetCPUStats(dom, NULL, 0, 0, 0, 0)) < 0)
              _croak_error();
          ncpus = ret;
      }

      Newx(params, ncpus * nparams, virTypedParameter);
      if ((ret = virDomainGetCPUStats(dom, params, nparams, start_cpu, ncpus, flags)) < 0) {
          Safefree(params);
          _croak_error();
      }

      EXTEND(SP, ret);
      for (i = 0 ; i < ret ; i++) {
          HV *rec = vir_typed_param_to_hv(params + (i * nparams), nparams);
          PUSHs(newRV_noinc((SV *)rec));
      }

      Safefree(params);


void
get_vcpu_info(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
 PREINIT:
      virVcpuInfoPtr info;
      unsigned char *cpumaps;
      int maplen;
      virNodeInfo nodeinfo;
      virDomainInfo dominfo;
      int nvCpus;
      int i;
   PPCODE:
      if (virNodeGetInfo(virDomainGetConnect(dom), &nodeinfo) < 0)
          _croak_error();
      if (virDomainGetInfo(dom, &dominfo) < 0)
          _croak_error();

      maplen = VIR_CPU_MAPLEN(VIR_NODEINFO_MAXCPUS(nodeinfo));
      Newx(cpumaps, dominfo.nrVirtCpu * maplen, unsigned char);
      if (flags && (flags & VIR_DOMAIN_AFFECT_CONFIG)) {
          Newx(info, dominfo.nrVirtCpu, virVcpuInfo);
          if ((nvCpus = virDomainGetVcpus(dom, info, dominfo.nrVirtCpu, cpumaps, maplen)) < 0) {
              Safefree(info);
              Safefree(cpumaps);
              _croak_error();
          }
      } else {
          info = NULL;
          if ((nvCpus = virDomainGetVcpuPinInfo(dom, dominfo.nrVirtCpu, cpumaps, maplen, flags)) < 0) {
              Safefree(cpumaps);
              _croak_error();
          }
      }

      EXTEND(SP, nvCpus);
      for (i = 0 ; i < nvCpus ; i++) {
          HV *rec = newHV();
          (void)hv_store(rec, "number", 6, newSViv(i), 0);
          if (info) {
              (void)hv_store(rec, "state", 5, newSViv(info[i].state), 0);
              (void)hv_store(rec, "cpuTime", 7, virt_newSVull(info[i].cpuTime), 0);
              (void)hv_store(rec, "cpu", 3, newSViv(info[i].cpu), 0);
          }
          (void)hv_store(rec, "affinity", 8, newSVpvn((char*)cpumaps + (i *maplen), maplen), 0);
          PUSHs(newRV_noinc((SV *)rec));
      }

      if (info)
          Safefree(info);
      Safefree(cpumaps);


void
pin_vcpu(dom, vcpu, mask, flags=0)
     virDomainPtr dom;
     unsigned int vcpu;
     SV *mask;
     unsigned int flags;
PREINIT:
     STRLEN masklen;
     unsigned char *maps;
 PPCODE:
     maps = (unsigned char *)SvPV(mask, masklen);
     if (flags) {
         if (virDomainPinVcpuFlags(dom, vcpu, maps, masklen, flags) < 0)
             _croak_error();
     } else {
         if (virDomainPinVcpu(dom, vcpu, maps, masklen) < 0)
             _croak_error();
     }


int
num_of_snapshots(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    CODE:
      if ((RETVAL = virDomainSnapshotNum(dom, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_snapshot_names(dom, maxnames, flags=0)
      virDomainPtr dom;
      int maxnames;
      unsigned int flags;
 PREINIT:
      char **names;
      int nsnap;
      int i;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nsnap = virDomainSnapshotListNames(dom, names, maxnames, flags)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nsnap);
      for (i = 0 ; i < nsnap ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


int
has_current_snapshot(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    CODE:
      if ((RETVAL = virDomainHasCurrentSnapshot(dom, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


virDomainSnapshotPtr
current_snapshot(dom, flags=0)
      virDomainPtr dom;
      unsigned int flags;
    CODE:
      if ((RETVAL = virDomainSnapshotCurrent(dom, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
destroy(dom_rv, flags=0)
      SV *dom_rv;
      unsigned int flags;
 PREINIT:
      virDomainPtr dom;
  PPCODE:
      dom = (virDomainPtr)SvIV((SV*)SvRV(dom_rv));
      if (flags) {
          if (virDomainDestroyFlags(dom, flags) < 0)
              _croak_error();
      } else {
          if (virDomainDestroy(dom) < 0)
              _croak_error();
      }


void
DESTROY(dom_rv)
      SV *dom_rv;
 PREINIT:
      virDomainPtr dom;
  PPCODE:
      dom = (virDomainPtr)SvIV((SV*)SvRV(dom_rv));
      if (dom) {
	virDomainFree(dom);
	sv_setiv((SV*)SvRV(dom_rv), 0);
      }


MODULE = Sys::Virt::Network  PACKAGE = Sys::Virt::Network


virNetworkPtr
_create_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virNetworkCreateXML(con, xml)))
          _croak_error();
  OUTPUT:
      RETVAL


virNetworkPtr
_define_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virNetworkDefineXML(con, xml)))
          _croak_error();
  OUTPUT:
      RETVAL


virNetworkPtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virNetworkLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virNetworkPtr
_lookup_by_uuid(con, uuid)
      virConnectPtr con;
      const unsigned char *uuid;
    CODE:
      if (!(RETVAL = virNetworkLookupByUUID(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


virNetworkPtr
_lookup_by_uuid_string(con, uuid)
      virConnectPtr con;
      const char *uuid;
    CODE:
      if (!(RETVAL = virNetworkLookupByUUIDString(con, uuid)))
          _croak_error();

  OUTPUT:
      RETVAL


SV *
get_uuid(net)
      virNetworkPtr net;
  PREINIT:
      unsigned char rawuuid[VIR_UUID_BUFLEN];
    CODE:
      if ((virNetworkGetUUID(net, rawuuid)) < 0)
          _croak_error();

      RETVAL = newSVpv((char*)rawuuid, sizeof(rawuuid));
  OUTPUT:
      RETVAL


SV *
get_uuid_string(net)
      virNetworkPtr net;
  PREINIT:
      char uuid[VIR_UUID_STRING_BUFLEN];
    CODE:
      if ((virNetworkGetUUIDString(net, uuid)) < 0)
          _croak_error();

      RETVAL = newSVpv(uuid, 0);
  OUTPUT:
      RETVAL


const char *
get_name(net)
      virNetworkPtr net;
    CODE:
      if (!(RETVAL = virNetworkGetName(net)))
          _croak_error();
  OUTPUT:
      RETVAL


int
is_active(net)
      virNetworkPtr net;
    CODE:
      if ((RETVAL = virNetworkIsActive(net)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_persistent(net)
      virNetworkPtr net;
    CODE:
      if ((RETVAL = virNetworkIsPersistent(net)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_bridge_name(net)
      virNetworkPtr net;
  PREINIT:
      char *name;
    CODE:
      if (!(name = virNetworkGetBridgeName(net)))
          _croak_error();

      RETVAL = newSVpv(name, 0);
      free(name);
  OUTPUT:
      RETVAL


SV *
get_xml_description(net, flags=0)
      virNetworkPtr net;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virNetworkGetXMLDesc(net, flags)))
	 _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
undefine(net)
      virNetworkPtr net;
    PPCODE:
      if (virNetworkUndefine(net) < 0)
          _croak_error();


void
create(net)
      virNetworkPtr net;
    PPCODE:
      if (virNetworkCreate(net) < 0)
          _croak_error();


void
set_autostart(net, autostart)
      virNetworkPtr net;
      int autostart;
  PPCODE:
      if (virNetworkSetAutostart(net, autostart) < 0)
          _croak_error();


int
get_autostart(net)
      virNetworkPtr net;
 PREINIT:
      int autostart;
    CODE:
      if (virNetworkGetAutostart(net, &autostart) < 0)
          _croak_error();

      RETVAL = autostart;
  OUTPUT:
      RETVAL


void
destroy(net_rv)
      SV *net_rv;
 PREINIT:
      virNetworkPtr net;
  PPCODE:
      net = (virNetworkPtr)SvIV((SV*)SvRV(net_rv));
      if (virNetworkDestroy(net) < 0)
          _croak_error();


void
DESTROY(net_rv)
      SV *net_rv;
 PREINIT:
      virNetworkPtr net;
  PPCODE:
      net = (virNetworkPtr)SvIV((SV*)SvRV(net_rv));
      if (net) {
	virNetworkFree(net);
	sv_setiv((SV*)SvRV(net_rv), 0);
      }


MODULE = Sys::Virt::StoragePool  PACKAGE = Sys::Virt::StoragePool


virStoragePoolPtr
_create_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virStoragePoolCreateXML(con, xml, 0)))
          _croak_error();

  OUTPUT:
      RETVAL


virStoragePoolPtr
_define_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virStoragePoolDefineXML(con, xml, 0)))
          _croak_error();
  OUTPUT:
      RETVAL


virStoragePoolPtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virStoragePoolLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virStoragePoolPtr
_lookup_by_uuid(con, uuid)
      virConnectPtr con;
      const unsigned char *uuid;
    CODE:
      if (!(RETVAL = virStoragePoolLookupByUUID(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


virStoragePoolPtr
_lookup_by_uuid_string(con, uuid)
      virConnectPtr con;
      const char *uuid;
    CODE:
      if (!(RETVAL = virStoragePoolLookupByUUIDString(con, uuid)))
	_croak_error();
  OUTPUT:
      RETVAL


virStoragePoolPtr
_lookup_by_volume(vol)
      virStorageVolPtr vol;
    CODE:
      if (!(RETVAL = virStoragePoolLookupByVolume(vol)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_uuid(pool)
      virStoragePoolPtr pool;
  PREINIT:
      unsigned char rawuuid[VIR_UUID_BUFLEN];
    CODE:
      if ((virStoragePoolGetUUID(pool, rawuuid)) < 0)
          _croak_error();

      RETVAL = newSVpv((char*)rawuuid, sizeof(rawuuid));
  OUTPUT:
      RETVAL


SV *
get_uuid_string(pool)
      virStoragePoolPtr pool;
  PREINIT:
      char uuid[VIR_UUID_STRING_BUFLEN];
    CODE:
      if ((virStoragePoolGetUUIDString(pool, uuid)) < 0)
          _croak_error();

      RETVAL = newSVpv(uuid, 0);
  OUTPUT:
      RETVAL


const char *
get_name(pool)
      virStoragePoolPtr pool;
    CODE:
      if (!(RETVAL = virStoragePoolGetName(pool)))
          _croak_error();
  OUTPUT:
      RETVAL


int
is_active(pool)
      virStoragePoolPtr pool;
    CODE:
      if ((RETVAL = virStoragePoolIsActive(pool)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


int
is_persistent(pool)
      virStoragePoolPtr pool;
    CODE:
      if ((RETVAL = virStoragePoolIsPersistent(pool)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(pool, flags=0)
      virStoragePoolPtr pool;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virStoragePoolGetXMLDesc(pool, flags)))
          _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
undefine(pool)
      virStoragePoolPtr pool;
    PPCODE:
      if (virStoragePoolUndefine(pool) < 0)
          _croak_error();


void
create(pool)
      virStoragePoolPtr pool;
    PPCODE:
      if (virStoragePoolCreate(pool, 0) < 0)
          _croak_error();


void
refresh(pool, flags=0)
      virStoragePoolPtr pool;
      int flags;
    PPCODE:
      if (virStoragePoolRefresh(pool, flags) < 0)
          _croak_error();


void
build(pool, flags=0)
      virStoragePoolPtr pool;
      int flags;
    PPCODE:
      if (virStoragePoolBuild(pool, flags) < 0)
          _croak_error();


void
delete(pool, flags=0)
      virStoragePoolPtr pool;
      int flags;
    PPCODE:
      if (virStoragePoolDelete(pool, flags) < 0)
          _croak_error();


void
set_autostart(pool, autostart)
      virStoragePoolPtr pool;
      int autostart;
  PPCODE:
      if (virStoragePoolSetAutostart(pool, autostart) < 0)
          _croak_error();


int
get_autostart(pool)
      virStoragePoolPtr pool;
 PREINIT:
      int autostart;
    CODE:
      if (virStoragePoolGetAutostart(pool, &autostart) < 0)
          _croak_error();

      RETVAL = autostart;
  OUTPUT:
      RETVAL


HV *
get_info(pool)
      virStoragePoolPtr pool;
  PREINIT:
      virStoragePoolInfo info;
    CODE:
      if (virStoragePoolGetInfo(pool, &info) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "state", 5, newSViv(info.state), 0);
      (void)hv_store (RETVAL, "capacity", 8, virt_newSVull(info.capacity), 0);
      (void)hv_store (RETVAL, "allocation", 10, virt_newSVull(info.allocation), 0);
      (void)hv_store (RETVAL, "available", 9, virt_newSVull(info.available), 0);
  OUTPUT:
      RETVAL


void
destroy(pool_rv)
      SV *pool_rv;
 PREINIT:
      virStoragePoolPtr pool;
  PPCODE:
      pool = (virStoragePoolPtr)SvIV((SV*)SvRV(pool_rv));
      if (virStoragePoolDestroy(pool) < 0)
          _croak_error();


int
num_of_storage_volumes(pool)
      virStoragePoolPtr pool;
    CODE:
      if ((RETVAL = virStoragePoolNumOfVolumes(pool)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_storage_vol_names(pool, maxnames)
      virStoragePoolPtr pool;
      int maxnames;
 PREINIT:
      char **names;
      int i, nnet;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nnet = virStoragePoolListVolumes(pool, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


void
DESTROY(pool_rv)
      SV *pool_rv;
 PREINIT:
      virStoragePoolPtr pool;
  PPCODE:
      pool = (virStoragePoolPtr)SvIV((SV*)SvRV(pool_rv));
      if (pool) {
          virStoragePoolFree(pool);
          sv_setiv((SV*)SvRV(pool_rv), 0);
      }


MODULE = Sys::Virt::StorageVol  PACKAGE = Sys::Virt::StorageVol


virStorageVolPtr
_create_xml(pool, xml, flags=0)
      virStoragePoolPtr pool;
      const char *xml;
      int flags;
    CODE:
      if (!(RETVAL = virStorageVolCreateXML(pool, xml, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virStorageVolPtr
_create_xml_from(pool, xml, clone, flags=0)
      virStoragePoolPtr pool;
      const char *xml;
      virStorageVolPtr clone;
      int flags;
    CODE:
      if (!(RETVAL = virStorageVolCreateXMLFrom(pool, xml, clone, flags)))
	_croak_error();
  OUTPUT:
      RETVAL


virStorageVolPtr
_lookup_by_name(pool, name)
      virStoragePoolPtr pool;
      const char *name;
    CODE:
      if (!(RETVAL = virStorageVolLookupByName(pool, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virStorageVolPtr
_lookup_by_key(con, key)
      virConnectPtr con;
      const char *key;
    CODE:
      if (!(RETVAL = virStorageVolLookupByKey(con, key)))
          _croak_error();
  OUTPUT:
      RETVAL


virStorageVolPtr
_lookup_by_path(con, path)
      virConnectPtr con;
      const char *path;
    CODE:
      if (!(RETVAL = virStorageVolLookupByPath(con, path)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_name(vol)
      virStorageVolPtr vol;
    CODE:
      if (!(RETVAL = virStorageVolGetName(vol)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_key(vol)
      virStorageVolPtr vol;
    CODE:
      if (!(RETVAL = virStorageVolGetKey(vol)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_path(vol)
      virStorageVolPtr vol;
    CODE:
      if (!(RETVAL = virStorageVolGetPath(vol)))
          _croak_error();
  OUTPUT:
      RETVAL


void
resize(vol, capacity, flags=0)
      virStorageVolPtr vol;
      SV *capacity;
      unsigned int flags;
  PPCODE:
      if (virStorageVolResize(vol, virt_SvIVull(capacity), flags) < 0)
          _croak_error();


SV *
get_xml_description(vol, flags=0)
      virStorageVolPtr vol;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virStorageVolGetXMLDesc(vol, flags)))
	 _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
delete(vol, flags=0)
      virStorageVolPtr vol;
      unsigned int flags;
    PPCODE:
      if (virStorageVolDelete(vol, flags) < 0)
          _croak_error();


void
wipe(vol, flags=0)
      virStorageVolPtr vol;
      unsigned int flags;
    PPCODE:
      if (virStorageVolWipe(vol, flags) < 0)
          _croak_error();


void
wipe_pattern(vol, algorithm, flags=0)
      virStorageVolPtr vol;
      unsigned int algorithm
      unsigned int flags;
    PPCODE:
      if (virStorageVolWipePattern(vol, algorithm, flags) < 0)
          _croak_error();


HV *
get_info(vol)
      virStorageVolPtr vol;
  PREINIT:
      virStorageVolInfo info;
    CODE:
      if (virStorageVolGetInfo(vol, &info) < 0)
          _croak_error();

      RETVAL = (HV *)sv_2mortal((SV*)newHV());
      (void)hv_store (RETVAL, "type", 4, newSViv(info.type), 0);
      (void)hv_store (RETVAL, "capacity", 8, virt_newSVull(info.capacity), 0);
      (void)hv_store (RETVAL, "allocation", 10, virt_newSVull(info.allocation), 0);
  OUTPUT:
      RETVAL


void
download(vol, st, offsetsv, lengthsv, flags=0)
      virStorageVolPtr vol;
      virStreamPtr st;
      SV *offsetsv;
      SV *lengthsv;
      unsigned int flags;
 PREINIT:
      unsigned long long offset;
      unsigned long long length;
  PPCODE:
      offset = virt_SvIVull(offsetsv);
      length = virt_SvIVull(lengthsv);

      if (virStorageVolDownload(vol, st, offset, length, flags) < 0)
          _croak_error();


void
upload(vol, st, offsetsv, lengthsv, flags=0)
      virStorageVolPtr vol;
      virStreamPtr st;
      SV *offsetsv;
      SV *lengthsv;
      unsigned int flags;
 PREINIT:
      unsigned long long offset;
      unsigned long long length;
  PPCODE:
      offset = virt_SvIVull(offsetsv);
      length = virt_SvIVull(lengthsv);

      if (virStorageVolUpload(vol, st, offset, length, flags) < 0)
          _croak_error();


void
DESTROY(vol_rv)
      SV *vol_rv;
 PREINIT:
      virStorageVolPtr vol;
  PPCODE:
      vol = (virStorageVolPtr)SvIV((SV*)SvRV(vol_rv));
      if (vol) {
          virStorageVolFree(vol);
          sv_setiv((SV*)SvRV(vol_rv), 0);
      }


MODULE = Sys::Virt::NodeDevice  PACKAGE = Sys::Virt::NodeDevice


virNodeDevicePtr
_create_xml(con, xml, flags=0)
      virConnectPtr con;
      const char *xml;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virNodeDeviceCreateXML(con, xml, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virNodeDevicePtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virNodeDeviceLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_name(dev)
      virNodeDevicePtr dev;
    CODE:
      if (!(RETVAL = virNodeDeviceGetName(dev)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_parent(dev)
      virNodeDevicePtr dev;
    CODE:
      if (!(RETVAL = virNodeDeviceGetParent(dev)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(dev, flags=0)
      virNodeDevicePtr dev;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virNodeDeviceGetXMLDesc(dev, flags)))
          _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
dettach(dev)
      virNodeDevicePtr dev;
    PPCODE:
      if (virNodeDeviceDettach(dev) < 0)
          _croak_error();


void
reattach(dev)
      virNodeDevicePtr dev;
    PPCODE:
      if (virNodeDeviceReAttach(dev) < 0)
	_croak_error();


void
reset(dev)
      virNodeDevicePtr dev;
    PPCODE:
      if (virNodeDeviceReset(dev) < 0)
          _croak_error();


void
list_capabilities(dev)
      virNodeDevicePtr dev;
 PREINIT:
      int maxnames;
      char **names;
      int i, nnet;
  PPCODE:
      if ((maxnames = virNodeDeviceNumOfCaps(dev)) < 0)
          _croak_error();

      Newx(names, maxnames, char *);
      if ((nnet = virNodeDeviceListCaps(dev, names, maxnames)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nnet);
      for (i = 0 ; i < nnet ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


void
destroy(dev_rv)
      SV *dev_rv;
 PREINIT:
      virNodeDevicePtr dev;
  PPCODE:
      dev = (virNodeDevicePtr)SvIV((SV*)SvRV(dev_rv));
      if (virNodeDeviceDestroy(dev) < 0)
          _croak_error();


void
DESTROY(dev_rv)
      SV *dev_rv;
 PREINIT:
      virNodeDevicePtr dev;
  PPCODE:
      dev = (virNodeDevicePtr)SvIV((SV*)SvRV(dev_rv));
      if (dev) {
          virNodeDeviceFree(dev);
          sv_setiv((SV*)SvRV(dev_rv), 0);
      }


MODULE = Sys::Virt::Interface  PACKAGE = Sys::Virt::Interface

virInterfacePtr
_define_xml(con, xml, flags = 0)
      virConnectPtr con;
      const char *xml;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virInterfaceDefineXML(con, xml, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virInterfacePtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virInterfaceLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virInterfacePtr
_lookup_by_mac(con, mac)
      virConnectPtr con;
      const char *mac;
    CODE:
      if (!(RETVAL = virInterfaceLookupByMACString(con, mac)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_mac(iface)
      virInterfacePtr iface;
    CODE:
      if (!(RETVAL = virInterfaceGetMACString(iface)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_name(iface)
      virInterfacePtr iface;
    CODE:
      if (!(RETVAL = virInterfaceGetName(iface)))
          _croak_error();
  OUTPUT:
      RETVAL


int
is_active(iface)
      virInterfacePtr iface;
    CODE:
      if ((RETVAL = virInterfaceIsActive(iface)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(iface, flags=0)
      virInterfacePtr iface;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virInterfaceGetXMLDesc(iface, flags)))
          _croak_error();
      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
undefine(iface)
      virInterfacePtr iface;
    PPCODE:
      if (virInterfaceUndefine(iface) < 0)
          _croak_error();


void
create(iface, flags=0)
      virInterfacePtr iface;
      unsigned int flags;
    PPCODE:
      if (virInterfaceCreate(iface, flags) < 0)
          _croak_error();


void
destroy(iface_rv, flags=0)
      SV *iface_rv;
      unsigned int flags;
 PREINIT:
      virInterfacePtr iface;
  PPCODE:
      iface = (virInterfacePtr)SvIV((SV*)SvRV(iface_rv));
      if (virInterfaceDestroy(iface, flags) < 0)
          _croak_error();


void
DESTROY(iface_rv)
      SV *iface_rv;
 PREINIT:
      virInterfacePtr iface;
  PPCODE:
      iface = (virInterfacePtr)SvIV((SV*)SvRV(iface_rv));
      if (iface) {
          virInterfaceFree(iface);
          sv_setiv((SV*)SvRV(iface_rv), 0);
      }


MODULE = Sys::Virt::Secret  PACKAGE = Sys::Virt::Secret


virSecretPtr
_define_xml(con, xml, flags=0)
      virConnectPtr con;
      const char *xml;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virSecretDefineXML(con, xml, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virSecretPtr
_lookup_by_usage(con, usageType, usageID)
      virConnectPtr con;
      int usageType;
      const char *usageID;
    CODE:
      if (!(RETVAL = virSecretLookupByUsage(con, usageType, usageID))) {
	_croak_error();
      }
  OUTPUT:
      RETVAL


virSecretPtr
_lookup_by_uuid(con, uuid)
      virConnectPtr con;
      const unsigned char *uuid;
    CODE:
      if (!(RETVAL = virSecretLookupByUUID(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


virSecretPtr
_lookup_by_uuid_string(con, uuid)
      virConnectPtr con;
      const char *uuid;
    CODE:
      if (!(RETVAL = virSecretLookupByUUIDString(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_uuid(sec)
      virSecretPtr sec;
  PREINIT:
      unsigned char rawuuid[VIR_UUID_BUFLEN];
    CODE:
      if ((virSecretGetUUID(sec, rawuuid)) < 0)
          _croak_error();

      RETVAL = newSVpv((char*)rawuuid, sizeof(rawuuid));
  OUTPUT:
      RETVAL


SV *
get_uuid_string(sec)
      virSecretPtr sec;
  PREINIT:
      char uuid[VIR_UUID_STRING_BUFLEN];
    CODE:
      if ((virSecretGetUUIDString(sec, uuid)) < 0)
          _croak_error();

      RETVAL = newSVpv(uuid, 0);
  OUTPUT:
      RETVAL


const char *
get_usage_id(sec)
      virSecretPtr sec;
    CODE:
      if (!(RETVAL = virSecretGetUsageID(sec)))
          _croak_error();
  OUTPUT:
      RETVAL


int
get_usage_type(sec)
      virSecretPtr sec;
    CODE:
      if (!(RETVAL = virSecretGetUsageType(sec)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(sec, flags=0)
      virSecretPtr sec;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virSecretGetXMLDesc(sec, flags)))
          _croak_error();
      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
undefine(sec)
      virSecretPtr sec;
    PPCODE:
      if (virSecretUndefine(sec) < 0)
          _croak_error();


void
set_value(sec, value, flags=0)
      virSecretPtr sec;
      SV *value;
      unsigned int flags;
PREINIT:
      unsigned char *bytes;
      STRLEN len;
 PPCODE:
      bytes = (unsigned char *)SvPV(value, len);
      if (virSecretSetValue(sec, bytes, len, flags) < 0)
          _croak_error();


SV *
get_value(sec, flags=0)
      virSecretPtr sec;
      unsigned int flags;
PREINIT:
      unsigned char *bytes;
      size_t len;
    CODE:
      if ((bytes = virSecretGetValue(sec, &len, flags)) == NULL)
          _croak_error();

      RETVAL = newSVpv((char*)bytes, len);
  OUTPUT:
      RETVAL



void
DESTROY(sec_rv)
      SV *sec_rv;
 PREINIT:
      virSecretPtr sec;
  PPCODE:
      sec = (virSecretPtr)SvIV((SV*)SvRV(sec_rv));
      if (sec) {
          virSecretFree(sec);
          sv_setiv((SV*)SvRV(sec_rv), 0);
      }


MODULE = Sys::Virt::NWFilter  PACKAGE = Sys::Virt::NWFilter


virNWFilterPtr
_define_xml(con, xml)
      virConnectPtr con;
      const char *xml;
    CODE:
      if (!(RETVAL = virNWFilterDefineXML(con, xml)))
          _croak_error();
  OUTPUT:
      RETVAL


virNWFilterPtr
_lookup_by_name(con, name)
      virConnectPtr con;
      const char *name;
    CODE:
      if (!(RETVAL = virNWFilterLookupByName(con, name)))
          _croak_error();
  OUTPUT:
      RETVAL


virNWFilterPtr
_lookup_by_uuid(con, uuid)
      virConnectPtr con;
      const unsigned char *uuid;
    CODE:
      if (!(RETVAL = virNWFilterLookupByUUID(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


virNWFilterPtr
_lookup_by_uuid_string(con, uuid)
      virConnectPtr con;
      const char *uuid;
    CODE:
      if (!(RETVAL = virNWFilterLookupByUUIDString(con, uuid)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_uuid(filter)
      virNWFilterPtr filter;
  PREINIT:
      unsigned char rawuuid[VIR_UUID_BUFLEN];
    CODE:
      if ((virNWFilterGetUUID(filter, rawuuid)) < 0)
          _croak_error();

      RETVAL = newSVpv((char*)rawuuid, sizeof(rawuuid));
  OUTPUT:
      RETVAL


SV *
get_uuid_string(filter)
      virNWFilterPtr filter;
  PREINIT:
      char uuid[VIR_UUID_STRING_BUFLEN];
    CODE:
      if ((virNWFilterGetUUIDString(filter, uuid)) < 0)
          _croak_error();

      RETVAL = newSVpv(uuid, 0);
  OUTPUT:
      RETVAL


const char *
get_name(filter)
      virNWFilterPtr filter;
    CODE:
      if (!(RETVAL = virNWFilterGetName(filter)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(filter, flags=0)
      virNWFilterPtr filter;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virNWFilterGetXMLDesc(filter, flags)))
          _croak_error();

      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
undefine(filter)
      virNWFilterPtr filter;
    PPCODE:
      if (virNWFilterUndefine(filter) < 0)
          _croak_error();

void
DESTROY(filter_rv)
      SV *filter_rv;
 PREINIT:
      virNWFilterPtr filter;
  PPCODE:
      filter = (virNWFilterPtr)SvIV((SV*)SvRV(filter_rv));
      if (filter) {
          virNWFilterFree(filter);
          sv_setiv((SV*)SvRV(filter_rv), 0);
      }


MODULE = Sys::Virt::DomainSnapshot  PACKAGE = Sys::Virt::DomainSnapshot


virDomainSnapshotPtr
_create_xml(dom, xml, flags=0)
      virDomainPtr dom;
      const char *xml;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virDomainSnapshotCreateXML(dom, xml, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


virDomainSnapshotPtr
_lookup_by_name(dom, name, flags=0)
      virDomainPtr dom;
      const char *name;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virDomainSnapshotLookupByName(dom, name, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


const char *
get_name(domss)
      virDomainSnapshotPtr domss;
    CODE:
      if (!(RETVAL = virDomainSnapshotGetName(domss)))
          _croak_error();
  OUTPUT:
      RETVAL


SV *
get_xml_description(domss, flags=0)
      virDomainSnapshotPtr domss;
      unsigned int flags;
  PREINIT:
      char *xml;
    CODE:
      if (!(xml = virDomainSnapshotGetXMLDesc(domss, flags)))
          _croak_error();
      RETVAL = newSVpv(xml, 0);
      free(xml);
  OUTPUT:
      RETVAL


void
revert_to(domss, flags=0)
      virDomainSnapshotPtr domss;
      unsigned int flags;
  PPCODE:
      if (virDomainRevertToSnapshot(domss, flags) < 0)
          _croak_error();


void
delete(domss, flags=0)
      virDomainSnapshotPtr domss;
      unsigned int flags;
  PPCODE:
      if (virDomainSnapshotDelete(domss, flags) < 0)
          _croak_error();


virDomainSnapshotPtr
get_parent(domss, flags=0)
      virDomainSnapshotPtr domss;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virDomainSnapshotGetParent(domss, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


int
num_of_child_snapshots(domss, flags=0)
      virDomainSnapshotPtr domss;
      unsigned int flags;
    CODE:
      if ((RETVAL = virDomainSnapshotNumChildren(domss, flags)) < 0)
          _croak_error();
  OUTPUT:
      RETVAL


void
list_child_snapshot_names(domss, maxnames, flags=0)
      virDomainSnapshotPtr domss;
      int maxnames;
      unsigned int flags;
 PREINIT:
      char **names;
      int nsnap;
      int i;
  PPCODE:
      Newx(names, maxnames, char *);
      if ((nsnap = virDomainSnapshotListChildrenNames(domss, names, maxnames, flags)) < 0) {
          Safefree(names);
          _croak_error();
      }
      EXTEND(SP, nsnap);
      for (i = 0 ; i < nsnap ; i++) {
          PUSHs(sv_2mortal(newSVpv(names[i], 0)));
          free(names[i]);
      }
      Safefree(names);


void
DESTROY(domss_rv)
      SV *domss_rv;
 PREINIT:
      virDomainSnapshotPtr domss;
  PPCODE:
      domss = (virDomainSnapshotPtr)SvIV((SV*)SvRV(domss_rv));
      if (domss) {
          virDomainSnapshotFree(domss);
          sv_setiv((SV*)SvRV(domss_rv), 0);
      }


MODULE = Sys::Virt::Event  PACKAGE = Sys::Virt::Event


PROTOTYPES: ENABLE


void
_register_impl()
 PPCODE:
      virEventRegisterImpl(_event_add_handle,
			   _event_update_handle,
			   _event_remove_handle,
			   _event_add_timeout,
			   _event_update_timeout,
			   _event_remove_timeout);


void
register_default()
  PPCODE:
      virEventRegisterDefaultImpl();


void
run_default()
  PPCODE:
      virEventRunDefaultImpl();


int
add_handle(fd, events, coderef)
      int fd;
      int events;
      SV *coderef;
PREINIT:
      int watch;
  CODE:
      SvREFCNT_inc(coderef);

      if ((watch = virEventAddHandle(fd, events, _event_handle_helper, coderef, _event_cb_free)) < 0) {
          SvREFCNT_dec(coderef);
          _croak_error();
      }
      RETVAL = watch;
 OUTPUT:
      RETVAL


void
update_handle(watch, events)
      int watch;
      int events;
  PPCODE:
      virEventUpdateHandle(watch, events);


void
remove_handle(watch)
      int watch;
  PPCODE:
      if (virEventRemoveHandle(watch) < 0)
          _croak_error();


int
add_timeout(frequency, coderef)
      int frequency;
      SV *coderef;
PREINIT:
      int timer;
  CODE:
      SvREFCNT_inc(coderef);

      if ((timer = virEventAddTimeout(frequency, _event_timeout_helper, coderef, _event_cb_free)) < 0) {
          SvREFCNT_dec(coderef);
          _croak_error();
      }
      RETVAL = timer;
 OUTPUT:
      RETVAL


void
update_timeout(timer, frequency)
      int timer;
      int frequency;
  PPCODE:
      virEventUpdateTimeout(timer, frequency);


void
remove_timeout(timer)
      int timer;
  PPCODE:
      if (virEventRemoveTimeout(timer) < 0)
          _croak_error();


void
_run_handle_callback_helper(watch, fd, event, cbref, opaqueref)
      int watch;
      int fd;
      int event;
      SV *cbref;
      SV *opaqueref;
 PREINIT:
      virEventHandleCallback cb;
      void *opaque;
  PPCODE:
      cb = (virEventHandleCallback)SvIV((SV*)SvRV(cbref));
      opaque = (void*)SvIV((SV*)SvRV(opaqueref));

      cb(watch, fd, event, opaque);


void
_run_timeout_callback_helper(timer, cbref, opaqueref)
      int timer;
      SV *cbref;
      SV *opaqueref;
 PREINIT:
      virEventTimeoutCallback cb;
      void *opaque;
  PPCODE:
      cb = (virEventTimeoutCallback)SvIV((SV*)SvRV(cbref));
      opaque = (void*)SvIV((SV*)SvRV(opaqueref));

      cb(timer, opaque);


void
_free_callback_opaque_helper(ffref, opaqueref)
      SV *ffref;
      SV *opaqueref;
PREINIT:
      virFreeCallback ff;
      void *opaque;
  PPCODE:
      opaque = SvOK(opaqueref) ? (void*)SvIV((SV*)SvRV(opaqueref)) : NULL;
      ff = SvOK(ffref) ? (virFreeCallback)SvIV((SV*)SvRV(ffref)) : NULL;

      if (opaque != NULL && ff != NULL)
        ff(opaque);



MODULE = Sys::Virt::Stream  PACKAGE = Sys::Virt::Stream

virStreamPtr
_new_obj(con, flags=0)
      virConnectPtr con;
      unsigned int flags;
    CODE:
      if (!(RETVAL = virStreamNew(con, flags)))
          _croak_error();
  OUTPUT:
      RETVAL


int
send(st, data, nbytes)
      virStreamPtr st;
      SV *data;
      size_t nbytes;
 PREINIT:
      const char *rawdata;
      STRLEN len;
    CODE:
      if (SvOK(data)) {
	  rawdata = SvPV(data, len);
          if (nbytes < 0 || nbytes > len)
              nbytes = len;
      } else {
          rawdata = "";
          nbytes = 0;
      }

      if ((RETVAL = virStreamSend(st, rawdata, nbytes)) < 0 &&
          RETVAL != -2)
          _croak_error();
  OUTPUT:
      RETVAL


int
recv(st, data, nbytes)
      virStreamPtr st;
      SV *data;
      size_t nbytes;
 PREINIT:
      char *rawdata;
    CODE:
      Newx(rawdata, nbytes, char);
      if ((RETVAL = virStreamRecv(st, rawdata, nbytes)) < 0 &&
          RETVAL != -2) {
          Safefree(rawdata);
          _croak_error();
      }
      if (RETVAL > 0) {
          sv_setpvn(data, rawdata, RETVAL);
      }
      Safefree(rawdata);
  OUTPUT:
      RETVAL


void
send_all(stref, handler)
      SV *stref;
      SV *handler;
 PREINIT:
      AV *opaque;
      virStreamPtr st;
    CODE:
      st = (virStreamPtr)SvIV((SV*)SvRV(stref));

      opaque = newAV();
      SvREFCNT_inc(handler);
      SvREFCNT_inc(stref);
      av_push(opaque, stref);
      av_push(opaque, handler);

      if (virStreamSendAll(st, _stream_send_all_source, opaque) < 0)
          _croak_error();

      SvREFCNT_dec(opaque);


void
recv_all(stref, handler)
      SV *stref;
      SV *handler;
 PREINIT:
      AV *opaque;
      virStreamPtr st;
    CODE:
      st = (virStreamPtr)SvIV((SV*)SvRV(stref));

      opaque = newAV();
      SvREFCNT_inc(handler);
      SvREFCNT_inc(stref);
      av_push(opaque, stref);
      av_push(opaque, handler);

      if (virStreamRecvAll(st, _stream_recv_all_sink, opaque) < 0)
          _croak_error();

      SvREFCNT_dec(opaque);


void
add_callback(stref, events, cb)
      SV* stref;
      int events;
      SV* cb;
 PREINIT:
      AV *opaque;
      virStreamPtr st;
  PPCODE:
      st = (virStreamPtr)SvIV((SV*)SvRV(stref));

      opaque = newAV();
      SvREFCNT_inc(cb);
      SvREFCNT_inc(stref);
      av_push(opaque, stref);
      av_push(opaque, cb);
      if (virStreamEventAddCallback(st, events, _stream_event_callback, opaque, _stream_event_free) < 0)
          _croak_error();


void
update_callback(st, events)
      virStreamPtr st;
      int events;
   PPCODE:
      if (virStreamEventUpdateCallback(st, events) < 0)
          _croak_error();


void
remove_callback(st)
      virStreamPtr st;
   PPCODE:
      if (virStreamEventRemoveCallback(st) < 0)
          _croak_error();


void
finish(st)
      virStreamPtr st;
  PPCODE:
      if (virStreamFinish(st) < 0)
          _croak_error();


void
abort(st)
      virStreamPtr st;
  PPCODE:
      if (virStreamAbort(st) < 0)
          _croak_error();


void
DESTROY(st_rv)
      SV *st_rv;
 PREINIT:
      virStreamPtr st;
  PPCODE:
      st = (virStreamPtr)SvIV((SV*)SvRV(st_rv));
      if (st) {
	virStreamFree(st);
	sv_setiv((SV*)SvRV(st_rv), 0);
      }


MODULE = Sys::Virt  PACKAGE = Sys::Virt


PROTOTYPES: ENABLE


BOOT:
    {
      HV *stash;

      virSetErrorFunc(NULL, ignoreVirErrorFunc);
      virInitialize();

      stash = gv_stashpv( "Sys::Virt", TRUE );

      REGISTER_CONSTANT(VIR_CONNECT_RO, CONNECT_RO);
      REGISTER_CONSTANT(VIR_CONNECT_NO_ALIASES, CONNECT_NO_ALIASES);

      REGISTER_CONSTANT(VIR_CRED_USERNAME, CRED_USERNAME);
      REGISTER_CONSTANT(VIR_CRED_AUTHNAME, CRED_AUTHNAME);
      REGISTER_CONSTANT(VIR_CRED_LANGUAGE, CRED_LANGUAGE);
      REGISTER_CONSTANT(VIR_CRED_CNONCE, CRED_CNONCE);
      REGISTER_CONSTANT(VIR_CRED_PASSPHRASE, CRED_PASSPHRASE);
      REGISTER_CONSTANT(VIR_CRED_ECHOPROMPT, CRED_ECHOPROMPT);
      REGISTER_CONSTANT(VIR_CRED_NOECHOPROMPT, CRED_NOECHOPROMPT);
      REGISTER_CONSTANT(VIR_CRED_REALM, CRED_REALM);
      REGISTER_CONSTANT(VIR_CRED_EXTERNAL, CRED_EXTERNAL);


      /* Don't bother with VIR_CPU_COMPARE_ERROR since we die in that case */
      REGISTER_CONSTANT(VIR_CPU_COMPARE_INCOMPATIBLE, CPU_COMPARE_INCOMPATIBLE);
      REGISTER_CONSTANT(VIR_CPU_COMPARE_IDENTICAL, CPU_COMPARE_IDENTICAL);
      REGISTER_CONSTANT(VIR_CPU_COMPARE_SUPERSET, CPU_COMPARE_SUPERSET);


      REGISTER_CONSTANT(VIR_NODE_SUSPEND_TARGET_MEM, NODE_SUSPEND_TARGET_MEM);
      REGISTER_CONSTANT(VIR_NODE_SUSPEND_TARGET_DISK, NODE_SUSPEND_TARGET_DISK);
      REGISTER_CONSTANT(VIR_NODE_SUSPEND_TARGET_HYBRID, NODE_SUSPEND_TARGET_HYBRID);


      REGISTER_CONSTANT(VIR_NODE_CPU_STATS_ALL_CPUS, NODE_CPU_STATS_ALL_CPUS);
      REGISTER_CONSTANT(VIR_NODE_MEMORY_STATS_ALL_CELLS, NODE_MEMORY_STATS_ALL_CELLS);


      stash = gv_stashpv( "Sys::Virt::Event", TRUE );

      REGISTER_CONSTANT(VIR_EVENT_HANDLE_READABLE, HANDLE_READABLE);
      REGISTER_CONSTANT(VIR_EVENT_HANDLE_WRITABLE, HANDLE_WRITABLE);
      REGISTER_CONSTANT(VIR_EVENT_HANDLE_ERROR, HANDLE_ERROR);
      REGISTER_CONSTANT(VIR_EVENT_HANDLE_HANGUP, HANDLE_HANGUP);


      stash = gv_stashpv( "Sys::Virt::Domain", TRUE );
      REGISTER_CONSTANT(VIR_DOMAIN_NOSTATE, STATE_NOSTATE);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING, STATE_RUNNING);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCKED, STATE_BLOCKED);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED, STATE_PAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN, STATE_SHUTDOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF, STATE_SHUTOFF);
      REGISTER_CONSTANT(VIR_DOMAIN_CRASHED, STATE_CRASHED);
      REGISTER_CONSTANT(VIR_DOMAIN_PMSUSPENDED, STATE_PMSUSPENDED);

      REGISTER_CONSTANT(VIR_DUMP_CRASH, DUMP_CRASH);
      REGISTER_CONSTANT(VIR_DUMP_LIVE, DUMP_LIVE);
      REGISTER_CONSTANT(VIR_DUMP_BYPASS_CACHE, DUMP_BYPASS_CACHE);
      REGISTER_CONSTANT(VIR_DUMP_RESET, DUMP_RESET);

      REGISTER_CONSTANT(VIR_DOMAIN_SAVE_BYPASS_CACHE, SAVE_BYPASS_CACHE);
      REGISTER_CONSTANT(VIR_DOMAIN_SAVE_RUNNING, SAVE_RUNNING);
      REGISTER_CONSTANT(VIR_DOMAIN_SAVE_PAUSED, SAVE_PAUSED);

      REGISTER_CONSTANT(VIR_DOMAIN_UNDEFINE_MANAGED_SAVE, UNDEFINE_MANAGED_SAVE);
      REGISTER_CONSTANT(VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA, UNDEFINE_SNAPSHOTS_METADATA);

      REGISTER_CONSTANT(VIR_DOMAIN_START_PAUSED, START_PAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_START_AUTODESTROY, START_AUTODESTROY);
      REGISTER_CONSTANT(VIR_DOMAIN_START_BYPASS_CACHE, START_BYPASS_CACHE);
      REGISTER_CONSTANT(VIR_DOMAIN_START_FORCE_BOOT, START_FORCE_BOOT);

      REGISTER_CONSTANT(VIR_DOMAIN_NOSTATE_UNKNOWN, STATE_NOSTATE_UNKNOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_UNKNOWN, STATE_RUNNING_UNKNOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_BOOTED, STATE_RUNNING_BOOTED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_MIGRATED, STATE_RUNNING_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_RESTORED, STATE_RUNNING_RESTORED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_FROM_SNAPSHOT, STATE_RUNNING_FROM_SNAPSHOT);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_UNPAUSED, STATE_RUNNING_UNPAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_MIGRATION_CANCELED, STATE_RUNNING_MIGRATION_CANCELED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_SAVE_CANCELED, STATE_RUNNING_SAVE_CANCELED);
      REGISTER_CONSTANT(VIR_DOMAIN_RUNNING_WAKEUP, STATE_RUNNING_WAKEUP);

      REGISTER_CONSTANT(VIR_DOMAIN_BLOCKED_UNKNOWN, STATE_RUNNING_UNKNOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_UNKNOWN, STATE_PAUSED_UNKNOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_USER, STATE_PAUSED_USER);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_MIGRATION, STATE_PAUSED_MIGRATION);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_SAVE, STATE_PAUSED_SAVE);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_DUMP, STATE_PAUSED_DUMP);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_IOERROR, STATE_PAUSED_IOERROR);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_WATCHDOG, STATE_PAUSED_WATCHDOG);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_FROM_SNAPSHOT, STATE_PAUSED_FROM_SNAPSHOT);
      REGISTER_CONSTANT(VIR_DOMAIN_PAUSED_SHUTTING_DOWN, STATE_PAUSED_SHUTTING_DOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN_UNKNOWN, STATE_SHUTDOWN_UNKNOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN_USER, STATE_SHUTDOWN_USER);

      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_UNKNOWN, STATE_SHUTOFF_UNKNOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_SHUTDOWN, STATE_SHUTOFF_SHUTDOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_DESTROYED, STATE_SHUTOFF_DESTROYED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_CRASHED, STATE_SHUTOFF_CRASHED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_MIGRATED, STATE_SHUTOFF_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_SAVED, STATE_SHUTOFF_SAVED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_FAILED, STATE_SHUTOFF_FAILED);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTOFF_FROM_SNAPSHOT, STATE_SHUTOFF_FROM_SNAPSHOT);

      REGISTER_CONSTANT(VIR_DOMAIN_CRASHED_UNKNOWN, STATE_CRASHED_UNKNOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_PMSUSPENDED_UNKNOWN, STATE_PMSUSPENDED_UNKNOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_OPEN_GRAPHICS_SKIPAUTH, OPEN_GRAPHICS_SKIPAUTH);

      REGISTER_CONSTANT(VIR_DOMAIN_CONSOLE_FORCE, OPEN_CONSOLE_FORCE);
      REGISTER_CONSTANT(VIR_DOMAIN_CONSOLE_SAFE, OPEN_CONSOLE_SAFE);

      /* NB: skip VIR_DOMAIN_SCHED_FIELD_* constants, because
         those are not used from Perl code - handled internally
         in the XS layer */

      REGISTER_CONSTANT(VIR_MIGRATE_LIVE, MIGRATE_LIVE);
      REGISTER_CONSTANT(VIR_MIGRATE_PEER2PEER, MIGRATE_PEER2PEER);
      REGISTER_CONSTANT(VIR_MIGRATE_TUNNELLED, MIGRATE_TUNNELLED);
      REGISTER_CONSTANT(VIR_MIGRATE_PERSIST_DEST, MIGRATE_PERSIST_DEST);
      REGISTER_CONSTANT(VIR_MIGRATE_UNDEFINE_SOURCE, MIGRATE_UNDEFINE_SOURCE);
      REGISTER_CONSTANT(VIR_MIGRATE_PAUSED, MIGRATE_PAUSED);
      REGISTER_CONSTANT(VIR_MIGRATE_NON_SHARED_DISK, MIGRATE_NON_SHARED_DISK);
      REGISTER_CONSTANT(VIR_MIGRATE_NON_SHARED_INC, MIGRATE_NON_SHARED_INC);
      REGISTER_CONSTANT(VIR_MIGRATE_CHANGE_PROTECTION, MIGRATE_CHANGE_PROTECTION);
      REGISTER_CONSTANT(VIR_MIGRATE_UNSAFE, MIGRATE_UNSAFE);


      REGISTER_CONSTANT(VIR_DOMAIN_XML_SECURE, XML_SECURE);
      REGISTER_CONSTANT(VIR_DOMAIN_XML_INACTIVE, XML_INACTIVE);
      REGISTER_CONSTANT(VIR_DOMAIN_XML_UPDATE_CPU, XML_UPDATE_CPU);


      REGISTER_CONSTANT(VIR_MEMORY_VIRTUAL, MEMORY_VIRTUAL);
      REGISTER_CONSTANT(VIR_MEMORY_PHYSICAL, MEMORY_PHYSICAL);


      REGISTER_CONSTANT(VIR_VCPU_OFFLINE, VCPU_OFFLINE);
      REGISTER_CONSTANT(VIR_VCPU_RUNNING, VCPU_RUNNING);
      REGISTER_CONSTANT(VIR_VCPU_BLOCKED, VCPU_BLOCKED);


      REGISTER_CONSTANT(VIR_KEYCODE_SET_LINUX, KEYCODE_SET_LINUX);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_XT, KEYCODE_SET_XT);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_ATSET1, KEYCODE_SET_ATSET1);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_ATSET2, KEYCODE_SET_ATSET2);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_ATSET3, KEYCODE_SET_ATSET3);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_OSX, KEYCODE_SET_OSX);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_XT_KBD, KEYCODE_SET_XT_KBD);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_USB, KEYCODE_SET_USB);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_WIN32, KEYCODE_SET_WIN32);
      REGISTER_CONSTANT(VIR_KEYCODE_SET_RFB, KEYCODE_SET_RFB);


      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_DEFINED, EVENT_DEFINED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_UNDEFINED, EVENT_UNDEFINED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED, EVENT_STARTED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED, EVENT_SUSPENDED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_RESUMED, EVENT_RESUMED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED, EVENT_STOPPED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SHUTDOWN, EVENT_SHUTDOWN);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_DEFINED_ADDED, EVENT_DEFINED_ADDED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_DEFINED_UPDATED, EVENT_DEFINED_UPDATED);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_UNDEFINED_REMOVED, EVENT_UNDEFINED_REMOVED);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED_BOOTED, EVENT_STARTED_BOOTED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED_MIGRATED, EVENT_STARTED_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED_RESTORED, EVENT_STARTED_RESTORED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED_FROM_SNAPSHOT, EVENT_STARTED_FROM_SNAPSHOT);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STARTED_WAKEUP, EVENT_STARTED_WAKEUP);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_PAUSED, EVENT_SUSPENDED_PAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_MIGRATED, EVENT_SUSPENDED_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_IOERROR, EVENT_SUSPENDED_IOERROR);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_WATCHDOG, EVENT_SUSPENDED_WATCHDOG);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_RESTORED, EVENT_SUSPENDED_RESTORED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SUSPENDED_FROM_SNAPSHOT, EVENT_SUSPENDED_FROM_SNAPSHOT);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_RESUMED_UNPAUSED, EVENT_RESUMED_UNPAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_RESUMED_MIGRATED, EVENT_RESUMED_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_RESUMED_FROM_SNAPSHOT, EVENT_RESUMED_FROM_SNAPSHOT);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_SHUTDOWN, EVENT_STOPPED_SHUTDOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_DESTROYED, EVENT_STOPPED_DESTROYED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_CRASHED, EVENT_STOPPED_CRASHED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_MIGRATED, EVENT_STOPPED_MIGRATED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_SAVED, EVENT_STOPPED_SAVED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_FAILED, EVENT_STOPPED_FAILED);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_STOPPED_FROM_SNAPSHOT, EVENT_STOPPED_FROM_SNAPSHOT);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_SHUTDOWN_FINISHED, EVENT_SHUTDOWN_FINISHED);


      REGISTER_CONSTANT(VIR_DOMAIN_CONTROL_OK, CONTROL_OK);
      REGISTER_CONSTANT(VIR_DOMAIN_CONTROL_JOB, CONTROL_JOB);
      REGISTER_CONSTANT(VIR_DOMAIN_CONTROL_OCCUPIED, CONTROL_OCCUPIED);
      REGISTER_CONSTANT(VIR_DOMAIN_CONTROL_ERROR, CONTROL_ERROR);


      REGISTER_CONSTANT(VIR_DOMAIN_DEVICE_MODIFY_CURRENT, DEVICE_MODIFY_CURRENT);
      REGISTER_CONSTANT(VIR_DOMAIN_DEVICE_MODIFY_LIVE, DEVICE_MODIFY_LIVE);
      REGISTER_CONSTANT(VIR_DOMAIN_DEVICE_MODIFY_CONFIG, DEVICE_MODIFY_CONFIG);
      REGISTER_CONSTANT(VIR_DOMAIN_DEVICE_MODIFY_FORCE, DEVICE_MODIFY_FORCE);


      REGISTER_CONSTANT(VIR_DOMAIN_MEM_CURRENT, MEM_CURRENT);
      REGISTER_CONSTANT(VIR_DOMAIN_MEM_LIVE, MEM_LIVE);
      REGISTER_CONSTANT(VIR_DOMAIN_MEM_CONFIG, MEM_CONFIG);
      REGISTER_CONSTANT(VIR_DOMAIN_MEM_MAXIMUM, MEM_MAXIMUM);


      REGISTER_CONSTANT(VIR_DOMAIN_AFFECT_CURRENT, AFFECT_CURRENT);
      REGISTER_CONSTANT(VIR_DOMAIN_AFFECT_LIVE, AFFECT_LIVE);
      REGISTER_CONSTANT(VIR_DOMAIN_AFFECT_CONFIG, AFFECT_CONFIG);


      REGISTER_CONSTANT(VIR_DOMAIN_JOB_NONE, JOB_NONE);
      REGISTER_CONSTANT(VIR_DOMAIN_JOB_BOUNDED, JOB_BOUNDED);
      REGISTER_CONSTANT(VIR_DOMAIN_JOB_UNBOUNDED, JOB_UNBOUNDED);
      REGISTER_CONSTANT(VIR_DOMAIN_JOB_COMPLETED, JOB_COMPLETED);
      REGISTER_CONSTANT(VIR_DOMAIN_JOB_FAILED, JOB_FAILED);
      REGISTER_CONSTANT(VIR_DOMAIN_JOB_CANCELLED, JOB_CANCELLED);

      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_TYPE_UNKNOWN, BLOCK_JOB_TYPE_UNKNOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_TYPE_PULL, BLOCK_JOB_TYPE_PULL);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_TYPE_COPY, BLOCK_JOB_TYPE_COPY);

      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_COMPLETED, BLOCK_JOB_COMPLETED);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_FAILED, BLOCK_JOB_FAILED);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_CANCELED, BLOCK_JOB_CANCELED);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_LIFECYCLE, EVENT_ID_LIFECYCLE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_REBOOT, EVENT_ID_REBOOT);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_RTC_CHANGE, EVENT_ID_RTC_CHANGE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_WATCHDOG, EVENT_ID_WATCHDOG);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_IO_ERROR, EVENT_ID_IO_ERROR);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_GRAPHICS, EVENT_ID_GRAPHICS);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_IO_ERROR_REASON, EVENT_ID_IO_ERROR_REASON);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_CONTROL_ERROR, EVENT_ID_CONTROL_ERROR);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_BLOCK_JOB, EVENT_ID_BLOCK_JOB);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_DISK_CHANGE, EVENT_ID_DISK_CHANGE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_PMSUSPEND, EVENT_ID_PMSUSPEND);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_PMWAKEUP, EVENT_ID_PMWAKEUP);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_ID_TRAY_CHANGE, EVENT_ID_TRAY_CHANGE);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_NONE, EVENT_WATCHDOG_NONE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_PAUSE, EVENT_WATCHDOG_PAUSE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_RESET, EVENT_WATCHDOG_RESET);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_POWEROFF, EVENT_WATCHDOG_POWEROFF);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_SHUTDOWN, EVENT_WATCHDOG_SHUTDOWN);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_WATCHDOG_DEBUG, EVENT_WATCHDOG_DEBUG);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_IO_ERROR_NONE, EVENT_IO_ERROR_NONE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_IO_ERROR_PAUSE, EVENT_IO_ERROR_PAUSE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_IO_ERROR_REPORT, EVENT_IO_ERROR_REPORT);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_CONNECT, EVENT_GRAPHICS_CONNECT);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_INITIALIZE, EVENT_GRAPHICS_INITIALIZE);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_DISCONNECT, EVENT_GRAPHICS_DISCONNECT);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_ADDRESS_IPV4, EVENT_GRAPHICS_ADDRESS_IPV4);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_ADDRESS_IPV6, EVENT_GRAPHICS_ADDRESS_IPV6);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_GRAPHICS_ADDRESS_UNIX, EVENT_GRAPHICS_ADDRESS_UNIX);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_DISK_CHANGE_MISSING_ON_START, EVENT_DISK_CHANGE_MISSING_ON_START);

      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_TRAY_CHANGE_OPEN, EVENT_TRAY_CHANGE_OPEN);
      REGISTER_CONSTANT(VIR_DOMAIN_EVENT_TRAY_CHANGE_CLOSE, EVENT_TRAY_CHANGE_CLOSE);

      REGISTER_CONSTANT_STR(VIR_DOMAIN_MEMORY_HARD_LIMIT, MEMORY_HARD_LIMIT);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_MEMORY_SOFT_LIMIT, MEMORY_SOFT_LIMIT);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_MEMORY_MIN_GUARANTEE, MEMORY_MIN_GUARANTEE);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_MEMORY_SWAP_HARD_LIMIT, MEMORY_SWAP_HARD_LIMIT);
      REGISTER_CONSTANT_ULL(VIR_DOMAIN_MEMORY_PARAM_UNLIMITED, MEMORY_PARAM_UNLIMITED);

      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLKIO_WEIGHT, BLKIO_WEIGHT);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLKIO_DEVICE_WEIGHT, BLKIO_DEVICE_WEIGHT);

      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_CPU_SHARES, SCHEDULER_CPU_SHARES);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_VCPU_PERIOD, SCHEDULER_VCPU_PERIOD);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_VCPU_QUOTA, SCHEDULER_VCPU_QUOTA);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_WEIGHT, SCHEDULER_WEIGHT);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_CAP, SCHEDULER_CAP);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_LIMIT, SCHEDULER_LIMIT);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_RESERVATION, SCHEDULER_RESERVATION);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_SCHEDULER_SHARES, SCHEDULER_SHARES);


      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_SWAP_IN, MEMORY_STAT_SWAP_IN);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_SWAP_OUT, MEMORY_STAT_SWAP_OUT);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_MAJOR_FAULT, MEMORY_STAT_MAJOR_FAULT);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_MINOR_FAULT, MEMORY_STAT_MINOR_FAULT);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_UNUSED, MEMORY_STAT_UNUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_AVAILABLE, MEMORY_STAT_AVAILABLE);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_ACTUAL_BALLOON, MEMORY_STAT_ACTUAL_BALLOON);
      REGISTER_CONSTANT(VIR_DOMAIN_MEMORY_STAT_RSS, MEMORY_STAT_RSS);


      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_TOTAL_BYTES_SEC, BLOCK_IOTUNE_TOTAL_BYTES_SEC);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_READ_BYTES_SEC, BLOCK_IOTUNE_READ_BYTES_SEC);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_WRITE_BYTES_SEC, BLOCK_IOTUNE_WRITE_BYTES_SEC);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_TOTAL_IOPS_SEC, BLOCK_IOTUNE_TOTAL_BYTES_SEC);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_READ_IOPS_SEC, BLOCK_IOTUNE_READ_BYTES_SEC);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BLOCK_IOTUNE_WRITE_IOPS_SEC, BLOCK_IOTUNE_WRITE_BYTES_SEC);


      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_RESIZE_BYTES, BLOCK_RESIZE_BYTES);


      REGISTER_CONSTANT_STR(VIR_DOMAIN_NUMA_NODESET, NUMA_NODESET);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_NUMA_MODE, NUMA_MODE);

      REGISTER_CONSTANT(VIR_DOMAIN_NUMATUNE_MEM_STRICT, NUMATUNE_MEM_STRICT);
      REGISTER_CONSTANT(VIR_DOMAIN_NUMATUNE_MEM_PREFERRED, NUMATUNE_MEM_PREFERRED);
      REGISTER_CONSTANT(VIR_DOMAIN_NUMATUNE_MEM_INTERLEAVE, NUMATUNE_MEM_INTERLEAVE);


      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_IN_AVERAGE, BANDWIDTH_IN_AVERAGE);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_IN_PEAK, BANDWIDTH_IN_PEAK);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_IN_BURST, BANDWIDTH_IN_BURST);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_OUT_AVERAGE, BANDWIDTH_OUT_AVERAGE);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_OUT_PEAK, BANDWIDTH_OUT_PEAK);
      REGISTER_CONSTANT_STR(VIR_DOMAIN_BANDWIDTH_OUT_BURST, BANDWIDTH_OUT_BURST);


      REGISTER_CONSTANT(VIR_DOMAIN_VCPU_CURRENT, VCPU_CURRENT);
      REGISTER_CONSTANT(VIR_DOMAIN_VCPU_LIVE, VCPU_LIVE);
      REGISTER_CONSTANT(VIR_DOMAIN_VCPU_CONFIG, VCPU_CONFIG);
      REGISTER_CONSTANT(VIR_DOMAIN_VCPU_MAXIMUM, VCPU_MAXIMUM);


      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN_DEFAULT, SHUTDOWN_DEFAULT);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN_ACPI_POWER_BTN, SHUTDOWN_ACPI_POWER_BTN);
      REGISTER_CONSTANT(VIR_DOMAIN_SHUTDOWN_GUEST_AGENT, SHUTDOWN_GUEST_AGENT);


      REGISTER_CONSTANT(VIR_DOMAIN_REBOOT_DEFAULT, REBOOT_DEFAULT);
      REGISTER_CONSTANT(VIR_DOMAIN_REBOOT_ACPI_POWER_BTN, REBOOT_ACPI_POWER_BTN);
      REGISTER_CONSTANT(VIR_DOMAIN_REBOOT_GUEST_AGENT, REBOOT_GUEST_AGENT);


      REGISTER_CONSTANT(VIR_DOMAIN_DESTROY_DEFAULT, DESTROY_DEFAULT);
      REGISTER_CONSTANT(VIR_DOMAIN_DESTROY_GRACEFUL, DESTROY_GRACEFUL);


      REGISTER_CONSTANT(VIR_DOMAIN_METADATA_DESCRIPTION, METADATA_DESCRIPTION);
      REGISTER_CONSTANT(VIR_DOMAIN_METADATA_TITLE, METADATA_TITLE);
      REGISTER_CONSTANT(VIR_DOMAIN_METADATA_ELEMENT, METADATA_ELEMENT);

      REGISTER_CONSTANT(VIR_DOMAIN_DISK_ERROR_NONE, DISK_ERROR_NONE);
      REGISTER_CONSTANT(VIR_DOMAIN_DISK_ERROR_NO_SPACE, DISK_ERROR_NO_SPACE);
      REGISTER_CONSTANT(VIR_DOMAIN_DISK_ERROR_UNSPEC, DISK_ERROR_UNSPEC);


      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_ABORT_ASYNC, BLOCK_JOB_ABORT_ASYNC);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_JOB_ABORT_PIVOT, BLOCK_JOB_ABORT_PIVOT);

      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_REBASE_SHALLOW, BLOCK_REBASE_SHALLOW);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_REBASE_REUSE_EXT, BLOCK_REBASE_REUSE_EXT);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_REBASE_COPY_RAW, BLOCK_REBASE_COPY_RAW);
      REGISTER_CONSTANT(VIR_DOMAIN_BLOCK_REBASE_COPY, BLOCK_REBASE_COPY);


      stash = gv_stashpv( "Sys::Virt::DomainSnapshot", TRUE );
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_DELETE_CHILDREN, DELETE_CHILDREN);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_DELETE_METADATA_ONLY, DELETE_METADATA_ONLY);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_DELETE_CHILDREN_ONLY, DELETE_CHILDREN_ONLY);

      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_REDEFINE, CREATE_REDEFINE);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_CURRENT, CREATE_CURRENT);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_NO_METADATA, CREATE_NO_METADATA);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_HALT, CREATE_HALT);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_DISK_ONLY, CREATE_DISK_ONLY);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_REUSE_EXT, CREATE_REUSE_EXT);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_QUIESCE, CREATE_QUIESCE);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_CREATE_ATOMIC, CREATE_ATOMIC);

      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_LIST_ROOTS, LIST_ROOTS);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_LIST_DESCENDANTS, LIST_DESCENDANTS);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_LIST_METADATA, LIST_METADATA);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_LIST_LEAVES, LIST_LEAVES);

      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_REVERT_RUNNING, REVERT_RUNNING);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_REVERT_PAUSED, REVERT_PAUSED);
      REGISTER_CONSTANT(VIR_DOMAIN_SNAPSHOT_REVERT_FORCE, REVERT_FORCE);

      stash = gv_stashpv( "Sys::Virt::StoragePool", TRUE );
      REGISTER_CONSTANT(VIR_STORAGE_POOL_INACTIVE, STATE_INACTIVE);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILDING, STATE_BUILDING);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_RUNNING, STATE_RUNNING);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_DEGRADED, STATE_DEGRADED);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_INACCESSIBLE, STATE_INACCESSIBLE);

      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILD_NEW, BUILD_NEW);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILD_REPAIR, BUILD_REPAIR);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILD_RESIZE, BUILD_RESIZE);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILD_NO_OVERWRITE, BUILD_NO_OVERWRITE);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_BUILD_OVERWRITE, BUILD_OVERWRITE);

      REGISTER_CONSTANT(VIR_STORAGE_POOL_DELETE_NORMAL, DELETE_NORMAL);
      REGISTER_CONSTANT(VIR_STORAGE_POOL_DELETE_ZEROED, DELETE_ZEROED);


      stash = gv_stashpv( "Sys::Virt::Network", TRUE );
      REGISTER_CONSTANT(VIR_NETWORK_XML_INACTIVE, XML_INACTIVE);


      stash = gv_stashpv( "Sys::Virt::Interface", TRUE );
      REGISTER_CONSTANT(VIR_INTERFACE_XML_INACTIVE, XML_INACTIVE);


      stash = gv_stashpv( "Sys::Virt::StorageVol", TRUE );
      REGISTER_CONSTANT(VIR_STORAGE_VOL_FILE, TYPE_FILE);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_BLOCK, TYPE_BLOCK);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_DIR, TYPE_DIR);

      REGISTER_CONSTANT(VIR_STORAGE_VOL_DELETE_NORMAL, DELETE_NORMAL);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_DELETE_ZEROED, DELETE_ZEROED);


      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_ZERO, WIPE_ALG_ZERO);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_NNSA, WIPE_ALG_NNSA);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_DOD, WIPE_ALG_DOD);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_BSI, WIPE_ALG_BSI);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_GUTMANN, WIPE_ALG_GUTMANN);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_SCHNEIER, WIPE_ALG_SCHNEIER);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_PFITZNER7, WIPE_ALG_PFITZNER7);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_PFITZNER33, WIPE_ALG_PFITZNER33);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_WIPE_ALG_RANDOM, WIPE_ALG_RANDOM);

      REGISTER_CONSTANT(VIR_STORAGE_VOL_RESIZE_ALLOCATE, RESIZE_ALLOCATE);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_RESIZE_DELTA, RESIZE_DELTA);
      REGISTER_CONSTANT(VIR_STORAGE_VOL_RESIZE_SHRINK, RESIZE_SHRINK);


      stash = gv_stashpv( "Sys::Virt::Secret", TRUE );
      REGISTER_CONSTANT(VIR_SECRET_USAGE_TYPE_NONE, USAGE_TYPE_NONE);
      REGISTER_CONSTANT(VIR_SECRET_USAGE_TYPE_VOLUME, USAGE_TYPE_VOLUME);
      REGISTER_CONSTANT(VIR_SECRET_USAGE_TYPE_CEPH, USAGE_TYPE_CEPH);



      stash = gv_stashpv( "Sys::Virt::Stream", TRUE );
      REGISTER_CONSTANT(VIR_STREAM_NONBLOCK, NONBLOCK);

      REGISTER_CONSTANT(VIR_STREAM_EVENT_READABLE, EVENT_READABLE);
      REGISTER_CONSTANT(VIR_STREAM_EVENT_WRITABLE, EVENT_WRITABLE);
      REGISTER_CONSTANT(VIR_STREAM_EVENT_ERROR, EVENT_ERROR);
      REGISTER_CONSTANT(VIR_STREAM_EVENT_HANGUP, EVENT_HANGUP);



      stash = gv_stashpv( "Sys::Virt::Error", TRUE );

      REGISTER_CONSTANT(VIR_ERR_NONE, LEVEL_NONE);
      REGISTER_CONSTANT(VIR_ERR_WARNING, LEVEL_WARNING);
      REGISTER_CONSTANT(VIR_ERR_ERROR, LEVEL_ERROR);

      REGISTER_CONSTANT(VIR_FROM_NONE, FROM_NONE);
      REGISTER_CONSTANT(VIR_FROM_XEN, FROM_XEN);
      REGISTER_CONSTANT(VIR_FROM_XEND, FROM_XEND);
      REGISTER_CONSTANT(VIR_FROM_XENSTORE, FROM_XENSTORE);
      REGISTER_CONSTANT(VIR_FROM_SEXPR, FROM_SEXPR);
      REGISTER_CONSTANT(VIR_FROM_XML, FROM_XML);
      REGISTER_CONSTANT(VIR_FROM_DOM, FROM_DOM);
      REGISTER_CONSTANT(VIR_FROM_RPC, FROM_RPC);
      REGISTER_CONSTANT(VIR_FROM_PROXY, FROM_PROXY);
      REGISTER_CONSTANT(VIR_FROM_CONF, FROM_CONF);
      REGISTER_CONSTANT(VIR_FROM_QEMU, FROM_QEMU);
      REGISTER_CONSTANT(VIR_FROM_NET, FROM_NET);
      REGISTER_CONSTANT(VIR_FROM_TEST, FROM_TEST);
      REGISTER_CONSTANT(VIR_FROM_REMOTE, FROM_REMOTE);
      REGISTER_CONSTANT(VIR_FROM_OPENVZ, FROM_OPENVZ);
      REGISTER_CONSTANT(VIR_FROM_XENXM, FROM_XENXM);
      REGISTER_CONSTANT(VIR_FROM_STATS_LINUX, FROM_STATS_LINUX);
      REGISTER_CONSTANT(VIR_FROM_LXC, FROM_LXC);
      REGISTER_CONSTANT(VIR_FROM_STORAGE, FROM_STORAGE);
      REGISTER_CONSTANT(VIR_FROM_NETWORK, FROM_NETWORK);
      REGISTER_CONSTANT(VIR_FROM_DOMAIN, FROM_DOMAIN);
      REGISTER_CONSTANT(VIR_FROM_UML, FROM_UML);
      REGISTER_CONSTANT(VIR_FROM_NODEDEV, FROM_NODEDEV);
      REGISTER_CONSTANT(VIR_FROM_XEN_INOTIFY, FROM_XEN_INOTIFY);
      REGISTER_CONSTANT(VIR_FROM_SECURITY, FROM_SECURITY);
      REGISTER_CONSTANT(VIR_FROM_VBOX, FROM_VBOX);
      REGISTER_CONSTANT(VIR_FROM_INTERFACE, FROM_INTERFACE);
      REGISTER_CONSTANT(VIR_FROM_ONE, FROM_ONE);
      REGISTER_CONSTANT(VIR_FROM_ESX, FROM_ESX);
      REGISTER_CONSTANT(VIR_FROM_PHYP, FROM_PHYP);
      REGISTER_CONSTANT(VIR_FROM_SECRET, FROM_SECRET);
      REGISTER_CONSTANT(VIR_FROM_CPU, FROM_CPU);
      REGISTER_CONSTANT(VIR_FROM_XENAPI, FROM_XENAPI);
      REGISTER_CONSTANT(VIR_FROM_NWFILTER, FROM_NWFILTER);
      REGISTER_CONSTANT(VIR_FROM_HOOK, FROM_HOOK);
      REGISTER_CONSTANT(VIR_FROM_DOMAIN_SNAPSHOT, FROM_DOMAIN_SNAPSHOT);
      REGISTER_CONSTANT(VIR_FROM_AUDIT, FROM_AUDIT);
      REGISTER_CONSTANT(VIR_FROM_SYSINFO, FROM_SYSINFO);
      REGISTER_CONSTANT(VIR_FROM_STREAMS, FROM_STREAMS);
      REGISTER_CONSTANT(VIR_FROM_VMWARE, FROM_VMWARE);
      REGISTER_CONSTANT(VIR_FROM_EVENT, FROM_EVENT);
      REGISTER_CONSTANT(VIR_FROM_LIBXL, FROM_LIBXL);
      REGISTER_CONSTANT(VIR_FROM_LOCKING, FROM_LOCKING);
      REGISTER_CONSTANT(VIR_FROM_HYPERV, FROM_HYPERV);
      REGISTER_CONSTANT(VIR_FROM_CAPABILITIES, FROM_CAPABILITIES);
      REGISTER_CONSTANT(VIR_FROM_AUTH, FROM_AUTH);
      REGISTER_CONSTANT(VIR_FROM_URI, FROM_URI);
      REGISTER_CONSTANT(VIR_FROM_DBUS, FROM_DBUS);


      REGISTER_CONSTANT(VIR_ERR_OK, ERR_OK);
      REGISTER_CONSTANT(VIR_ERR_INTERNAL_ERROR, ERR_INTERNAL_ERROR);
      REGISTER_CONSTANT(VIR_ERR_NO_MEMORY, ERR_NO_MEMORY);
      REGISTER_CONSTANT(VIR_ERR_NO_SUPPORT, ERR_NO_SUPPORT);
      REGISTER_CONSTANT(VIR_ERR_UNKNOWN_HOST, ERR_UNKNOWN_HOST);
      REGISTER_CONSTANT(VIR_ERR_NO_CONNECT, ERR_NO_CONNECT);
      REGISTER_CONSTANT(VIR_ERR_INVALID_CONN, ERR_INVALID_CONN);
      REGISTER_CONSTANT(VIR_ERR_INVALID_DOMAIN, ERR_INVALID_DOMAIN);
      REGISTER_CONSTANT(VIR_ERR_INVALID_ARG, ERR_INVALID_ARG);
      REGISTER_CONSTANT(VIR_ERR_OPERATION_FAILED, ERR_OPERATION_FAILED);
      REGISTER_CONSTANT(VIR_ERR_GET_FAILED, ERR_GET_FAILED);
      REGISTER_CONSTANT(VIR_ERR_POST_FAILED, ERR_POST_FAILED);
      REGISTER_CONSTANT(VIR_ERR_HTTP_ERROR, ERR_HTTP_ERROR);
      REGISTER_CONSTANT(VIR_ERR_SEXPR_SERIAL, ERR_SEXPR_SERIAL);
      REGISTER_CONSTANT(VIR_ERR_NO_XEN, ERR_NO_XEN);
      REGISTER_CONSTANT(VIR_ERR_XEN_CALL, ERR_XEN_CALL);
      REGISTER_CONSTANT(VIR_ERR_OS_TYPE, ERR_OS_TYPE);
      REGISTER_CONSTANT(VIR_ERR_NO_KERNEL, ERR_NO_KERNEL);
      REGISTER_CONSTANT(VIR_ERR_NO_ROOT, ERR_NO_ROOT);
      REGISTER_CONSTANT(VIR_ERR_NO_SOURCE, ERR_NO_SOURCE);
      REGISTER_CONSTANT(VIR_ERR_NO_TARGET, ERR_NO_TARGET);
      REGISTER_CONSTANT(VIR_ERR_NO_NAME, ERR_NO_NAME);
      REGISTER_CONSTANT(VIR_ERR_NO_OS, ERR_NO_OS);
      REGISTER_CONSTANT(VIR_ERR_NO_DEVICE, ERR_NO_DEVICE);
      REGISTER_CONSTANT(VIR_ERR_NO_XENSTORE, ERR_NO_XENSTORE);
      REGISTER_CONSTANT(VIR_ERR_DRIVER_FULL, ERR_DRIVER_FULL);
      REGISTER_CONSTANT(VIR_ERR_CALL_FAILED, ERR_CALL_FAILED);
      REGISTER_CONSTANT(VIR_ERR_XML_ERROR, ERR_XML_ERROR);
      REGISTER_CONSTANT(VIR_ERR_DOM_EXIST, ERR_DOM_EXIST);
      REGISTER_CONSTANT(VIR_ERR_OPERATION_DENIED, ERR_OPERATIONED_DENIED);
      REGISTER_CONSTANT(VIR_ERR_OPEN_FAILED, ERR_OPEN_FAILED);
      REGISTER_CONSTANT(VIR_ERR_READ_FAILED, ERR_READ_FAILED);
      REGISTER_CONSTANT(VIR_ERR_PARSE_FAILED, ERR_PARSE_FAILED);
      REGISTER_CONSTANT(VIR_ERR_CONF_SYNTAX, ERR_CONF_SYNTAX);
      REGISTER_CONSTANT(VIR_ERR_WRITE_FAILED, ERR_WRITE_FAILED);
      REGISTER_CONSTANT(VIR_ERR_XML_DETAIL, ERR_XML_DETAIL);
      REGISTER_CONSTANT(VIR_ERR_INVALID_NETWORK, ERR_INVALID_NETWORK);
      REGISTER_CONSTANT(VIR_ERR_NETWORK_EXIST, ERR_NETWORK_EXIST);
      REGISTER_CONSTANT(VIR_ERR_SYSTEM_ERROR, ERR_SYSTEM_ERROR);
      REGISTER_CONSTANT(VIR_ERR_RPC, ERR_RPC);
      REGISTER_CONSTANT(VIR_ERR_GNUTLS_ERROR, ERR_GNUTLS_ERROR);
      REGISTER_CONSTANT(VIR_WAR_NO_NETWORK, WAR_NO_NETWORK);
      REGISTER_CONSTANT(VIR_ERR_NO_DOMAIN, ERR_NO_DOMAIN);
      REGISTER_CONSTANT(VIR_ERR_NO_NETWORK, ERR_NO_NETWORK);
      REGISTER_CONSTANT(VIR_ERR_INVALID_MAC, ERR_INVALID_MAC);
      REGISTER_CONSTANT(VIR_ERR_AUTH_FAILED, ERR_AUTH_FAILED);
      REGISTER_CONSTANT(VIR_ERR_INVALID_STORAGE_POOL, ERR_INVALID_STORAGE_POOL);
      REGISTER_CONSTANT(VIR_ERR_INVALID_STORAGE_VOL, ERR_INVALID_STORAGE_VOL);
      REGISTER_CONSTANT(VIR_WAR_NO_STORAGE, WAR_NO_STORAGE);
      REGISTER_CONSTANT(VIR_ERR_NO_STORAGE_POOL, ERR_NO_STORAGE_POOL);
      REGISTER_CONSTANT(VIR_ERR_NO_STORAGE_VOL, ERR_NO_STORAGE_VOL);
      REGISTER_CONSTANT(VIR_WAR_NO_NODE, WAR_NO_NODE);
      REGISTER_CONSTANT(VIR_ERR_INVALID_NODE_DEVICE, ERR_INVALID_NODE_DEVICE);
      REGISTER_CONSTANT(VIR_ERR_NO_NODE_DEVICE, ERR_NO_NODE_DEVICE);
      REGISTER_CONSTANT(VIR_ERR_NO_SECURITY_MODEL, ERR_NO_SECURITY_MODEL);
      REGISTER_CONSTANT(VIR_ERR_OPERATION_INVALID, ERR_OPERATION_INVALID);
      REGISTER_CONSTANT(VIR_WAR_NO_INTERFACE, WAR_NO_INTERFACE);
      REGISTER_CONSTANT(VIR_ERR_NO_INTERFACE, ERR_NO_INTERFACE);
      REGISTER_CONSTANT(VIR_ERR_INVALID_INTERFACE, ERR_INVALID_INTERFACE);
      REGISTER_CONSTANT(VIR_ERR_MULTIPLE_INTERFACES, ERR_MULTIPLE_INTERFACES);
      REGISTER_CONSTANT(VIR_WAR_NO_NWFILTER, WAR_NO_NWFILTER);
      REGISTER_CONSTANT(VIR_ERR_INVALID_NWFILTER, ERR_INVALID_NWFILTER);
      REGISTER_CONSTANT(VIR_ERR_NO_NWFILTER, ERR_NO_NWFILTER);
      REGISTER_CONSTANT(VIR_ERR_BUILD_FIREWALL, ERR_BUILD_FIREWALL);
      REGISTER_CONSTANT(VIR_WAR_NO_SECRET, WAR_NO_SECRET);
      REGISTER_CONSTANT(VIR_ERR_INVALID_SECRET, ERR_INVALID_SECRET);
      REGISTER_CONSTANT(VIR_ERR_NO_SECRET, ERR_NO_SECRET);
      REGISTER_CONSTANT(VIR_ERR_CONFIG_UNSUPPORTED, ERR_CONFIG_UNSUPPORTED);
      REGISTER_CONSTANT(VIR_ERR_OPERATION_TIMEOUT, ERR_OPERATION_TIMEOUT);
      REGISTER_CONSTANT(VIR_ERR_MIGRATE_PERSIST_FAILED, ERR_MIGRATE_PERSIST_FAILED);
      REGISTER_CONSTANT(VIR_ERR_HOOK_SCRIPT_FAILED, ERR_HOOK_SCRIPT_FAILED);
      REGISTER_CONSTANT(VIR_ERR_INVALID_DOMAIN_SNAPSHOT, ERR_INVALID_DOMAIN_SNAPSHOT);
      REGISTER_CONSTANT(VIR_ERR_NO_DOMAIN_SNAPSHOT, ERR_NO_DOMAIN_SNAPSHOT);
      REGISTER_CONSTANT(VIR_ERR_INVALID_STREAM, ERR_INVALID_STREAM);
      REGISTER_CONSTANT(VIR_ERR_ARGUMENT_UNSUPPORTED, ERR_ARGUMENT_UNSUPPORTED);
      REGISTER_CONSTANT(VIR_ERR_STORAGE_PROBE_FAILED, ERR_STORAGE_PROBE_FAILED);
      REGISTER_CONSTANT(VIR_ERR_STORAGE_POOL_BUILT, ERR_STORAGE_POOL_BUILT);
      REGISTER_CONSTANT(VIR_ERR_SNAPSHOT_REVERT_RISKY, ERR_SNAPSHOT_REVERT_RISKY);
      REGISTER_CONSTANT(VIR_ERR_OPERATION_ABORTED, ERR_OPERATION_ABORTED);
      REGISTER_CONSTANT(VIR_ERR_AUTH_CANCELLED, ERR_AUTH_CANCELLED);
      REGISTER_CONSTANT(VIR_ERR_NO_DOMAIN_METADATA, ERR_NO_DOMAIN_METADATA);
      REGISTER_CONSTANT(VIR_ERR_MIGRATE_UNSAFE, ERR_MIGRATE_UNSAFE);
      REGISTER_CONSTANT(VIR_ERR_OVERFLOW, ERR_OVERFLOW);
      REGISTER_CONSTANT(VIR_ERR_BLOCK_COPY_ACTIVE, ERR_BLOCK_COPY_ACTIVE);
    }
