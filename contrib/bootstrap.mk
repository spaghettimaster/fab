#!/usr/bin/make -f

ifndef FAB_PATH
$(error FAB_PATH not defined - needed for default paths)
endif

ifndef RELEASE
$(warning RELEASE not defined - default paths such as POOL may break)
endif

# default locations
POOL ?= $(FAB_PATH)/pools/$(RELEASE)
BOOTSTRAP_LIBEXEC ?= /turnkey/private/fab/contrib/bootstrap

# build output path
O ?= build

STAMPS_DIR = $O/stamps

all: $O/bootstrap

#clean
define clean/body 
	-rm -rf $O/*.spec $O/bootstrap $O/repo $(STAMPS_DIR)
endef

clean:
	$(clean/pre)
	$(clean/body)
	$(clean/post)

#required.spec
required.spec/deps ?= plan/required
define required.spec/body
	fab-plan-resolve --output=$O/required.spec --pool=$(POOL) plan/required
endef

#base.spec
base.spec/deps ?= plan/base $(STAMPS_DIR)/required.spec
define base.spec/body
	fab-plan-resolve --output=$O/base.full.spec --pool=$(POOL) plan/base
	$(BOOTSTRAP_LIBEXEC)/exclude_spec.py $O/base.full.spec $O/required.spec > $O/base.spec
endef

#bootstrap.spec
bootstrap.spec/deps ?= $(STAMPS_DIR)/required.spec $(STAMPS_DIR)/base.spec
define bootstrap.spec/body
	echo "# REQUIRED" > $O/bootstrap.spec
	cat $O/required.spec >> $O/bootstrap.spec

	echo "# BASE" >> $O/bootstrap.spec
	cat $O/base.spec >> $O/bootstrap.spec
endef

#repo
repo/deps ?= $(STAMPS_DIR)/bootstrap.spec
define repo/body
	mkdir -p $O/repo/pool/main
	POOL_DIR=$(POOL) pool-get -s -t -i $O/bootstrap.spec $O/repo/pool/main

	$(BOOTSTRAP_LIBEXEC)/repo_index.sh $(RELEASE) main $O/repo
	$(BOOTSTRAP_LIBEXEC)/repo_release.sh $(RELEASE) main `pwd`/$O/repo
endef

#bootstrap
bootstrap/deps ?= $(STAMPS_DIR)/repo $(STAMPS_DIR)/bootstrap.spec
define bootstrap/body
	$(BOOTSTRAP_LIBEXEC)/bootstrap_spec.py $(RELEASE) $O/bootstrap `pwd`/$O/repo $O/bootstrap.spec

	rm -rf $O/bootstrap/var/cache/apt/archives/*.deb
	echo "do_initrd = Yes" > $O/bootstrap/etc/kernel-img.conf
endef

$O/bootstrap: $(bootstrap/deps) $(bootstrap/deps/extra)
	$(bootstrap/pre)
	$(bootstrap/body)
	$(bootstrap/post)

bootstrap: $O/bootstrap

# construct target rules
define _stamped_target
$1: $(STAMPS_DIR)/$1

$(STAMPS_DIR)/$1: $$($1/deps) $$($1/deps/extra)
	@mkdir -p $(STAMPS_DIR)
	$$($1/pre)
	$$($1/body)
	$$($1/post)
	touch $$@
endef

STAMPED_TARGETS := required.spec base.spec bootstrap.spec repo
$(foreach target,$(STAMPED_TARGETS),$(eval $(call _stamped_target,$(target))))

.PHONY: clean $(STAMP_TARGETS)

