echo "=== smolnetd Debug ==="
echo "1. Process:"
ps aux | grep smol
echo ""
echo "2. Schemes exist:"
ls /scheme/ip /scheme/tcp /scheme/udp /scheme/netcfg
echo ""
echo "3. netcfg contents:"
cat /scheme/netcfg/ifaces
echo ""
echo "4. Network scheme MAC:"
test -f /scheme/network.pci-00-00-03.0_virtio_net/mac && echo "MAC file exists" || echo "MAC file NOT found"
echo ""
echo "5. /etc/net config:"
ls /etc/net/
echo "=== Done ==="
