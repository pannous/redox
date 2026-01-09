echo "=== Manual Interface Test ==="
echo "1. Check what netcfg accepts:"
cat /scheme/netcfg/
echo ""
echo "2. Try creating eth0:"
echo "network.pci-00-00-03.0_virtio_net" > /scheme/netcfg/ifaces/eth0
echo "Result: $?"
echo ""
echo "3. Check ifaces now:"
ls /scheme/netcfg/ifaces/
echo "=== Done ==="
