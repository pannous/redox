# check open files in the mount;
echo "⚠️ the Main file system outside of share is currently configured as snapshot, so any changes outside /scheme/9p.hostshare/ will be lost upon shutdown. On the other hand, it means we never need to unmount."
input "Press Enter to continue unmounting ./mount..."
mount | grep redox
lsof +D /opt/other/mount/ 
# mount | rg '/opt/other/mount'
# lsof | rg '/opt/other/mount'
ps -axo pid,command | rg '/opt/other/mount'
# echo "just killing redoxfs process would DAMAGE img:"
# echo "ERROR redoxfs::transaction] READ_BLOCK: INCORRECT HASH"
# qemu-img convert -O raw build/aarch64/pure-rust.iso build/aarch64/pure-rust.img
# sudo killall -SIGKILL redoxfs ⚠️ can break img HASH
# PID = $(lsof +D /opt/other/redox/mount/ | awk 'NR==2 {print $2}')
# kill $PID
umount /opt/other/redox/mount/ || diskutil unmount force /opt/other/redox/mount || hdiutil detach /opt/other/redox/redox-force