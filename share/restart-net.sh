echo "=== Restart smolnetd ==="
echo "Before:"
ls /scheme/netcfg/
ls /scheme/netcfg/ifaces/
echo ""
echo "Finding smolnetd PID..."
ps aux | grep smol
echo ""
echo "Kill using signal - find smolnetd PID first"
ps aux | grep smolnetd | head -1
echo ""
echo "Starting fresh smolnetd..."
smolnetd
sleep 8
echo ""
echo "After:"
ls /scheme/netcfg/
ls /scheme/netcfg/ifaces/
echo "=== Done ==="
