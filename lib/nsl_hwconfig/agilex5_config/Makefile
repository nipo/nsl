ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += agilex5_config.pkg.vhd

# The speed grade sits inside the ordering code, after the package:
# A5EB013BB23BE4SCS is a -4S part, the E or I before it being the
# temperature range.  A part number none of these branches claims
# leaves the package body out, and the design then fails to build
# rather than silently taking some other grade's limits.
ifneq ($(findstring E1V,$(target_part))$(findstring I1V,$(target_part))$(findstring E4S,$(target_part))$(findstring I4S,$(target_part)),)
vhdl-sources += agilex5_config_1v4s.vhd
else ifneq ($(findstring E2V,$(target_part))$(findstring I2V,$(target_part))$(findstring E2E,$(target_part))$(findstring I2E,$(target_part))$(findstring E5S,$(target_part))$(findstring I5S,$(target_part)),)
vhdl-sources += agilex5_config_2v2e5s.vhd
else ifneq ($(findstring E3V,$(target_part))$(findstring I3V,$(target_part))$(findstring E6S,$(target_part))$(findstring I6S,$(target_part))$(findstring E6X,$(target_part))$(findstring I6X,$(target_part)),)
vhdl-sources += agilex5_config_3v6s6x.vhd
endif
endif
