# Origami Service Makefile
# ------------------------
# This section of the Makefile should not be modified, it includes
# commands from the Origami service Makefile.
# https://github.com/Financial-Times/origami-service-makefile
node_modules/%/index.mk: package.json ; npm install $* ; touch $@
-include node_modules/@financial-times/origami-service-makefile/index.mk
# [edit below this line]
# ------------------------
