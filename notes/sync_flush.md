Syncing to and fro the share works live and effortlessly without explicit sync command. 
To do: Give the share a better name like:
alias s="ln -s /scheme/9p.hostshare/ /root/share"
Which we don't want to do every startup. 
Be careful, the ln command is only available late in the init process. 

Syncing to and fro the Main file system was broken, rolled back and is currently deactivated via 
CACHE="cache=none,snapshot=on"

Last attempt of implementation:
eb14773fa 2026-01-11 01:32 docs: document complete sync flush implementation


