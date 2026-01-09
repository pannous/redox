echo "=== Check Logs ==="
echo "1. Read scheme log (last 50 lines):"
cat /scheme/log
echo ""
echo "2. Check smolnetd proc:"
ps aux | grep smol
echo ""
echo "3. List netcfg:"
ls /scheme/netcfg/
echo ""
echo "4. List netcfg ifaces:"
ls /scheme/netcfg/ifaces/
echo "=== Done ==="
