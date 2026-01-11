# qemu wrapper script to launch img with specific parameters
# hardwired: build/aarch64/${CONFIG_NAME}/harddrive.img
# /usr/local/bin/redox-vm
# /opt/other/redox/redox-vm
# multipass-like interface
# Usage: ./redox-vm launch|shell|stop|list|delete [options]
redox-vm launch --mem 4G --name redox-me --mount $HOME:/Users/me
redox-vm shell redox-me