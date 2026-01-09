echo "=== Driver Check ==="
echo "1. Network scheme info:"
ls /scheme/network.pci-00-00-03.0_virtio_net/
echo ""
echo "2. Try reading MAC:"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac
echo ""
echo "3. netcfg scheme:"
ls /scheme/netcfg/
echo ""
echo "4. Try list under netcfg:"
cat /scheme/netcfg/list
echo ""
echo "5. Check ip scheme:"
ls /scheme/ip/
echo "=== Done ==="
