echo "=== Timing Test ==="
echo "1. Kill smolnetd"
ps aux | grep smol
echo ""
echo "2. Check schemes"
ls /scheme/ | grep network
echo ""
echo "3. Restart smolnetd"
/usr/bin/smolnetd
echo ""
echo "4. Check ifaces"
ls /scheme/netcfg/ifaces/
echo "=== Done ==="
