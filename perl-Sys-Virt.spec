# Automatically generated by perl-Sys-Virt.spec.PL

Name:           perl-Sys-Virt
Version:        0.9.5
Release:        1%{?dist}%{?extra_release}
Summary:        Represent and manage a libvirt hypervisor connection
License:        GPLv2+ or Artistic
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/Sys-Virt/
Source0:        http://www.cpan.org/authors/id/D/DA/DANBERR/Sys-Virt-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(Test::Pod)
BuildRequires:  perl(Test::Pod::Coverage)
BuildRequires:  perl(XML::XPath)
BuildRequires:  libvirt-devel >= 0.9.5
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
The Sys::Virt module provides a Perl XS binding to the libvirt virtual
machine management APIs. This allows machines running within arbitrary
virtualization containers to be managed with a consistent API.

%prep
%setup -q -n Sys-Virt-%{version}

sed -i -e '/Sys-Virt\.spec/d' Makefile.PL
sed -i -e '/\.spec\.PL$/d' MANIFEST
rm -f *.spec.PL

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor OPTIMIZE="$RPM_OPT_FLAGS"
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f \( -name .packlist -o -name '*.bs' -empty \) |
	xargs rm -f
find $RPM_BUILD_ROOT -depth -type d -empty -exec rmdir {} \;

%{_fixperms} $RPM_BUILD_ROOT/*

%check
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc AUTHORS CHANGES LICENSE README examples/
%{perl_vendorarch}/auto/*
%{perl_vendorarch}/Sys*
%{_mandir}/man3/*

%changelog
