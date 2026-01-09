echo "=== netcfg Test ==="
echo "1. netcfg scheme:"
ls /scheme/netcfg/
echo ""
echo "2. netcfg ifaces:"
ls /scheme/netcfg/ifaces/
echo ""
echo "3. Try reading netcfg root:"
cat /scheme/netcfg/
echo ""
echo "4. smolnetd status:"
ps aux | grep smol
echo "=== Done ==="
