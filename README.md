# PercApps

a container project for all my standalone apps for percussa ssp/xmx.

this is a release tool, basically collect together various projects, allow to be built
then combine with a setup that combines together and provider user with instructions on how to install etc.

note:
the XMX and SSP are different binary formats, and also have different hardware layouts,
so binaries and configurations cannot generally.

resources fall into therefore 3 categories

ssp specific
xmx specitic
common



sub projects, linked as sub modules into external

PercCmd
Dependancies : None
a small utility application, allow a user to select standalone at boot time via buttons.
it falls back safely to the default SYNTHOR app

Plugins
Dependancies : None
all my plugins for use in Synthor or TraxHost

TraxHost
a standalone host for plugins, by default we configure for Trax plugin
Dependancies : PercCmd, Plugins

Er301
a standalone app emulating the er301, we are only interested in the percussa target
Dependancies : PercCmd



# using 
git submodule update --init --recursive  

How to build:
# Configure (only needs to happen once)
cmake -B build -DCMAKE_BUILD_TYPE=Release

# Build everything (both platforms)
cmake --build build

# Or build a single platform
cmake --build build --target ssp
cmake --build build --target xmx