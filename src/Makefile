# simple Gnu-Makefile for ltcltk. Works for Linux, MacOS X, probably other unixen
#
# Gunnar Zötl <gz@tset.de>, 2011.
# Released under MIT/X11 license. See file LICENSE for details.

# try some automatic discovery
OS = $(shell uname -s)
LUAVERSION = $(shell lua -v 2>&1|awk '{split($$2, a, "."); print a[1] "." a[2]}')
LUADIR = $(shell dirname `which lua`)
LUAROOT = $(shell dirname $(LUADIR))
BINDIR=/usr/local/bin

LUA_INC_DIR=-I$(LUAROOT)/include
TCL_INC_DIR=-I/usr/include/tk -I/usr/include
LUA_LIB_DIR=-L$(LUAROOT)/lib
TCL_LIB_DIR=-L/usr/include
TCL_LIB=tcl8.5

INC_DIRS=${LUA_INC_DIR} ${TCL_INC_DIR}
LIB_DIRS=${LUA_LIB_DIR} ${TCL_LIB_DIR}

# Defaults
CC = gcc
TARGET = ltcl.so
DEBUG= #-g -lefence
CFLAGS=-O2 -fPIC $(DEBUG)
INCDIRS=-I$(LUAROOT)/include
LIBDIRS=-L$(LUAROOT)/lib
LDFLAGS=-shared $(DEBUG)

INSTALL_ROOT=/usr/local
SO_INST_ROOT=$(INSTALL_ROOT)/lib/lua/$(LUAVERSION)
LUA_INST_ROOT=$(INSTALL_ROOT)/share/lua/$(LUAVERSION)

# OS specialities
ifeq ($(OS),Darwin)
LDFLAGS=-bundle -undefined dynamic_lookup -all_load
endif

all:	$(TARGET)

ltcl.o: ltcl.c
	$(CC) $(CFLAGS) ${INC_DIRS} -c $< -o $@

$(TARGET): ltcl.o
	$(CC) $(LDFLAGS) -o $@ ${LIB_DIRS} $< -l${TCL_LIB}

install: all ltk.lua
	cp ltcl.so ${SO_INST_ROOT}
	cp ltk.lua ${LUA_INST_ROOT}
	cp ltksh ${BINDIR}
	chmod 755 $(BINDIR)/ltksh

clean:
	find . -name "*~" -exec rm {} \;
	rm -f *.o *.so *.func *.ps core
	for dir in . doc samples; \
	do \
		rm -f $dir/.DS_Store; \
		rm -f $dir/._*; \
	done

