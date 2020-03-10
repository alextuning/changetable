#
# yum install postgresql-devel
# 
EXTENSION = changetable
MODULE_big = changetable
DATA = changetable--0.1.14.sql
OBJS = main.o audit.o misc.o config.o
PG_CONFIG = pg_config

headers_version = 92

ifeq ($(shell test -d /usr/pgsql-9.5/include 2> /dev/null; echo $$?), 0)
  headers_version=95
endif

ifeq ($(shell test -d /usr/pgsql-9.6/include 2> /dev/null; echo $$?), 0)
  headers_version=96
endif

ifeq ($(shell test -d /usr/pgsql-10/include 2> /dev/null; echo $$?), 0)
  headers_version=10
endif

PG_CPPFLAGS = -DBUILD_PG_VER_$(headers_version) -std=c99
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

