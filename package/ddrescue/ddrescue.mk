################################################################################
#
# DDRESCUE
#
################################################################################

DDRESCUE_VERSION = 1.21
DDRESCUE_SITE = file://$(TOPDIR)/z_customfiles
DDRESCUE_DEPENDENCIES = host-bison host-flex
DDRESCUE_CONF_OPTS = --shared
DDRESCUE_LICENSE = GPLv2

define DDRESCUE_BUILD_CMDS
	cd $(@D) && $(TARGET_MAKE_ENV) ./configure && cd $(TOPDIR)
        $(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define DDRESCUE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ddrescue $(TARGET_DIR)/usr/sbin/ddrescue
endef

$(eval $(generic-package))
