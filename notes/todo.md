Creating files on the share with currently creates the wrong permissions on the host system. 
echo test > test
cat test
echo test >> test2
cat test2
echo test | tee test3
cat test3
/scheme/9p.hostshare/test-write.sh

There is a little problem with the cat command or prompt in that it cuts off the last line if it doesn't end with a newline. (\r Prompt ?)

/opt/other/redox/share/ cat ok
na
ja
was
root:/scheme/9p.hostshare# cat ok
na
ja
root:/scheme/9p.hostshare# echo jaaa >> ok
root:/scheme/9p.hostshare# cat ok
jaaa

was

chmod has no effect


@notes/execution.md
There seem to be at least two problems with script execution: 
• they cannot be invoked via . 
• they cannot be invoked via path (only via source)
• they cannot be invoked Cross-device


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


root:/scheme/9p.hostshare# echo ja >> ok
Overwrites the content instead of appending. 