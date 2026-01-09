echo "=== Restart smolnetd ==="
echo "1. Find PID:"
ps aux | grep smol
echo ""
echo "2. Check network scheme exists:"
ls /scheme/ | grep network
echo ""
echo "3. Check ifaces before:"
ls /scheme/netcfg/ifaces/
echo ""
echo "4. Try starting new smolnetd:"
smolnetd
echo ""
echo "5. Check ifaces after:"
ls /scheme/netcfg/ifaces/
echo "=== Done ==="
