echo "=== Proper Restart ==="
echo "1. Find smolnetd PID"
ps aux | grep smol
echo ""
echo "2. Current schemes:"
ls /scheme/ | grep -E "ip|tcp|udp|icmp|netcfg|network"
echo ""
echo "3. Current ifaces:"
ls /scheme/netcfg/ifaces/
echo ""
echo "4. Test read MAC:"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac
echo ""
echo "5. /etc/net config:"
cat /etc/net/ip
cat /etc/net/ip_router
cat /etc/net/ip_subnet
echo "=== Done ==="
