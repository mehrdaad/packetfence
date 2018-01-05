DOCBOOK_XSL := /usr/share/xml/docbook/stylesheet/docbook-xsl
UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
	DOCBOOK_XSL := /opt/local/share/xsl/docbook-xsl
else ifneq ("$(wildcard /etc/redhat-release)","")
	DOCBOOK_XSL := /usr/share/sgml/docbook/xsl-stylesheets
endif

all:
	@echo "Please chose which documentation to build:"
	@echo ""
	@echo " 'pdf' will build all guides using the PDF format"
	@echo " 'PacketFence_Administration_Guide.pdf' will build the Administration guide in PDF"
	@echo " 'PacketFence_Developers_Guide.pdf' will build the Develoeprs guide in PDF"
	@echo " 'PacketFence_Network_Devices_Configuration_Guide.pdf' will build the Network Devices Configuration guide in PDF"

pdf: docs/docbook/xsl/titlepage-fo.xsl docs/docbook/xsl/import-fo.xsl $(patsubst %.asciidoc,%.pdf,$(notdir $(wildcard docs/PacketFence_*.asciidoc)))

docs/docbook/xsl/titlepage-fo.xsl: docs/docbook/xsl/titlepage-fo.xml
	xsltproc \
		-o docs/docbook/xsl/titlepage-fo.xsl \
		$(DOCBOOK_XSL)/template/titlepage.xsl \
		docs/docbook/xsl/titlepage-fo.xml

docs/docbook/xsl/import-fo.xsl:
	@echo "<?xml version='1.0'?> \
	<xsl:stylesheet   \
	  xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\" \
	  xmlns:fo=\"http://www.w3.org/1999/XSL/Format\" \
	  version=\"1.0\"> \
	  <xsl:import href=\"${DOCBOOK_XSL}/fo/docbook.xsl\"/> \
	</xsl:stylesheet>" \
	> docs/docbook/xsl/import-fo.xsl

%.pdf : docs/%.asciidoc
	asciidoc \
		-a docinfo2 \
		-b docbook \
		-d book \
		-o docs/docbook/$(notdir $<).docbook \
		$<
	xsltproc \
		-o $<.fo \
		docs/docbook/xsl/packetfence-fo.xsl \
		docs/docbook/$(notdir $<).docbook
	fop \
		-c docs/fonts/fop-config.xml \
		$<.fo \
		-pdf docs/$@

html: $(patsubst %.asciidoc,%.html,$(notdir $(wildcard docs/PacketFence_*.asciidoc)))

%.html : docs/%.asciidoc
	asciidoctor \
		-D docs/html \
		-n \
		$<

html/pfappserver/root/static/doc:
	make html
	mkdir -p docs/html/docs/images/
	cp -a docs/images/* docs/html/docs/images/
	mv docs/html html/pfappserver/root/static/doc

pfcmd.help:
	/usr/local/pf/bin/pfcmd help > docs/pfcmd.help

.PHONY: configurations

configurations:
	find -type f -name '*.example' -print0 | while read -d $$'\0' file; do cp -n $$file "$$(dirname $$file)/$$(basename $$file .example)"; done
	touch /usr/local/pf/conf/pf.conf

# server certs and keys
# the | in the prerequisites ensure the target is not created if it already exists
# see https://www.gnu.org/software/make/manual/make.html#Prerequisite-Types
conf/ssl/server.pem: | conf/ssl/server.key conf/ssl/server.crt conf/ssl/server.pem 
	cat conf/ssl/server.crt conf/ssl/server.key > conf/ssl/server.pem

conf/ssl/server.crt: | conf/ssl/server.crt
	openssl req -new -x509 -days 365 \
	-out /usr/local/pf/conf/ssl/server.crt \
	-key /usr/local/pf/conf/ssl/server.key \
	-config /usr/local/pf/conf/openssl.cnf

conf/ssl/server.key: | conf/ssl/server.key
	openssl genrsa -out /usr/local/pf/conf/ssl/server.key 2048

conf/pf_omapi_key:
	/usr/bin/openssl rand -base64 -out /usr/local/pf/conf/pf_omapi_key 32

conf/local_secret:
	date +%s | sha256sum | base64 | head -c 32 > /usr/local/pf/conf/local_secret

bin/pfcmd: src/pfcmd.c
	$(CC) -O2 -g -std=c99  -Wall $< -o $@

bin/ntlm_auth_wrapper: src/ntlm_auth_wrap.c
	cc -g -std=c99  -Wall  src/ntlm_auth_wrap.c -o bin/ntlm_auth_wrapper

.PHONY:permissions

/etc/sudoers.d/packetfence.sudoers: packetfence.sudoers
	cp packetfence.sudoers /etc/sudoers.d/packetfence.sudoers

.PHONY: sudo

sudo: /etc/sudoers.d/packetfence.sudoers


permissions:
	./bin/pfcmd fixpermissions

raddb/certs/server.crt:
	cd raddb/certs; make

.PHONY: raddb-sites-enabled

raddb/sites-enabled:
	mkdir raddb/sites-enabled
	cd raddb/sites-enabled;\
	for f in packetfence packetfence-tunnel dynamic-clients;\
		do ln -s ../sites-available/$$f $$f;\
	done

.PHONY: translation

translation:
	for TRANSLATION in de en es fr he_IL it nl pl_PL pt_BR; do\
		/usr/bin/msgfmt conf/locale/$$TRANSLATION/LC_MESSAGES/packetfence.po\
		  --output-file conf/locale/$$TRANSLATION/LC_MESSAGES/packetfence.mo;\
	done

.PHONY: mysql-schema

mysql-schema:
	ln -f -s /usr/local/pf/db/pf-schema-X.Y.Z.sql /usr/local/pf/db/pf-schema.sql;

.PHONY: chown_pf

chown_pf:
	chown -R pf:pf *

.PHONY: fingerbank

fingerbank:
	rm -f /usr/local/pf/lib/fingerbank
	ln -s /usr/local/fingerbank/lib/fingerbank /usr/local/pf/lib/fingerbank \

.PHONY: pf-dal

pf-dal:
	perl /usr/local/pf/addons/dev-helpers/bin/generator-data-access-layer.pl

devel: configurations conf/ssl/server.crt conf/pf_omapi_key conf/local_secret bin/pfcmd raddb/certs/server.crt sudo translation mysql-schema raddb/sites-enabled fingerbank chown_pf permissions bin/ntlm_auth_wrapper html/pfappserver/root/static/doc

test:
	cd t && ./smoke.t
