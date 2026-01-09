echo "Saving output..."
echo "=== OUTPUT ===" > /scheme/9p.hostshare/output.txt
echo "1. MAC:" >> /scheme/9p.hostshare/output.txt
xxd /scheme/network.pci-00-00-03.0_virtio_net/mac >> /scheme/9p.hostshare/output.txt
echo "" >> /scheme/9p.hostshare/output.txt
echo "2. netcfg dir:" >> /scheme/9p.hostshare/output.txt
ls /scheme/netcfg/ >> /scheme/9p.hostshare/output.txt
echo "" >> /scheme/9p.hostshare/output.txt
echo "3. ifaces dir:" >> /scheme/9p.hostshare/output.txt
ls /scheme/netcfg/ifaces/ >> /scheme/9p.hostshare/output.txt
echo "" >> /scheme/9p.hostshare/output.txt
echo "4. network dir:" >> /scheme/9p.hostshare/output.txt
ls /scheme/network.pci-00-00-03.0_virtio_net/ >> /scheme/9p.hostshare/output.txt
echo "" >> /scheme/9p.hostshare/output.txt
echo "5. smolnetd proc:" >> /scheme/9p.hostshare/output.txt
ps aux | grep smol >> /scheme/9p.hostshare/output.txt
echo "=== DONE ===" >> /scheme/9p.hostshare/output.txt
echo "Output saved to /scheme/9p.hostshare/output.txt"
