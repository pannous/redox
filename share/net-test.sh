echo "=== Network Test ==="
echo "1. Network schemes:"
ls /scheme/ | grep network

echo ""
echo "2. netcfg ifaces:"
ls -la /scheme/netcfg/ifaces/

echo ""
echo "3. eth0 address:"
cat /scheme/netcfg/ifaces/eth0/addr/list

echo ""
echo "4. Route table:"
cat /scheme/netcfg/route/list

echo ""
echo "5. Config files:"
cat /etc/net/ip
cat /etc/net/ip_subnet
cat /etc/net/ip_router

echo "=== Done ==="
