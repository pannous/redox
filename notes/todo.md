lets do a
Full rebuild - Set up build for new relibc binaries
Full rebuild of all relibc binaries

root:/scheme/9p.hostshare# bash
relibc getrlimit(7, 0x7ffffffffb70): not implemented
bash-5.2# ls
ok  simple-sync  ba  simple-echo  hi  hello  
bash-5.2# . ba
bash: ba: I/O error
TODO: Broken utilities on current image: coreutils suite is corrupted (commands behave like `ls` and emit `ls:` errors); observed `sleep` and `stat` acting as `ls`, and `killall` is missing.



root:/scheme/9p.hostshare# df
Path            Size      Used      Free Use%
/scheme/memory   1422356    192756   1229600  13%
/scheme/logging   1422356    192756   1229600  13%
1970-01-01T00-05-26.968Z [@inputd:208 ERROR] invalid path ''