Summary:  Postgresql audit module
Name:     %{RELEASE_NAME}
Version:  %{MAJOR_RELEASE}
Release:  %{MINOR_RELEASE}
License:  GPL
BuildArch:  x86_64
#BuildRequires: postgresql-devel

%description
PostgresSQL module for auditing user queries

%build
mkdir -p %{_builddir}/changetable
cp -rv $CI_PROJECT_DIR/extension/* %{_builddir}/changetable
(cd changetable && make USE_PGXS=1)

%install
mkdir -p $RPM_BUILD_ROOT/%{POSTGRES_LIB_DIR}
mkdir -p $RPM_BUILD_ROOT/%{POSTGRES_EXT_DIR}
mkdir -p $RPM_BUILD_ROOT/usr/local/bin

cp %{_builddir}/changetable/changetable.so $RPM_BUILD_ROOT/%{POSTGRES_LIB_DIR}
cp %{_builddir}/changetable/changetable.control $RPM_BUILD_ROOT/%{POSTGRES_EXT_DIR}
cp %{_builddir}/changetable/changetable--*.sql $RPM_BUILD_ROOT/%{POSTGRES_EXT_DIR}
cp %{_builddir}/changetable/changetable-hook $RPM_BUILD_ROOT/usr/local/bin

%files
%attr(755,root,root) %{POSTGRES_LIB_DIR}/changetable.so
%attr(644,root,root) %{POSTGRES_EXT_DIR}/changetable.control
%attr(644,root,root) %{POSTGRES_EXT_DIR}/changetable--*.sql
%attr(755,root,root) %config(noreplace) /usr/local/bin/changetable-hook
