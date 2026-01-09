echo "=== Network Check ==="
echo "1. ls /scheme/ | grep net"
ls /scheme/ | grep net
echo ""
echo "2. Processes:"
ps aux
echo ""
echo "3. netcfg contents:"
ls /scheme/netcfg/
echo ""
echo "4. ifaces contents:"
ls /scheme/netcfg/ifaces/
echo ""
echo "5. Try ip scheme:"
ls /scheme/ip/
echo ""
echo "6. Try tcp scheme:"
ls /scheme/tcp/
echo "=== Done ==="
