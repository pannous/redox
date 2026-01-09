echo "=== Network Debug ==="
echo "1. /etc/net config:"
cat /etc/net/ip
cat /etc/net/ip_router
cat /etc/net/dns
echo ""
echo "2. Network schemes:"
ls /scheme/netcfg
echo ""
echo "3. netcfg/ifaces:"
ls /scheme/netcfg/ifaces
echo ""
echo "4. smolnetd:"
ps aux | grep smol
echo ""
echo "5. Network MAC:"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac | xxd
echo "=== Done ==="
