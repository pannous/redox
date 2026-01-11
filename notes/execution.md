
There seem to be at least two problems with script execution: 
• they cannot be invoked via . 
• they cannot be invoked via path (only via source)
• they cannot be invoked Cross-device

root:/scheme/9p.hostshare# ll write-test.sh
-777     1134 write-test.sh  # ok - has execute permissions for all

root:/scheme/9p.hostshare# cat write-test.sh
# Creating files on the share currently creates the wrong permissions
cd /scheme/9p.hostshare/
echo "Writing three tests files can take a little while. "
echo test1 > test1
# sleep 1    Currently broken in Redox!!!
cat test1
echo test2 >> test2
# sleep 1
cat test2
echo test3 | tee test3
# sleep 1
cat test3

root:~/share# ./write-test.sh
ion: Operation not permitted (os error 1)

root:~/share# ~/share/write-test.sh
ion: command not found: /root/share/write-test.sh
root:/scheme/9p.hostshare# ll /root/share/write-test.sh
ls: cannot access '/root/share/write-test.sh': Cross-device link (os error 18)
root:/scheme/9p.hostshare# source ~/share/write-test.sh
ion: failed to open /root/share/write-test.sh

root:~/share# pwd
/scheme/9p.hostshare
root:/scheme/9p.hostshare# . write-test.sh
ion: pipeline execution error: command exec error: Exec format error (os error 8)
root:/scheme/9p.hostshare# ./write-test.sh
ion: pipeline execution error: command exec error: Argument list too long (os error 7)
root:~/share# /scheme/9p.hostshare/write-test.sh
ion: pipeline execution error: command exec error: Argument list too long (os error 7)

root:~/share# source /scheme/9p.hostshare/write-test.sh
Writing three tests files can take a little while. 
cat: test1: I/O error (os error 5)
cat: test2: I/O error (os error 5)
test3
cat: test3: I/O error (os error 5)
-240        6 test1
-240        6 test2
-240        6 test3

