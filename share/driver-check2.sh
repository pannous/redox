echo "=== Driver Check 2 ==="
echo "1. MAC as hex:"
xxd /scheme/network.pci-00-00-03.0_virtio_net/mac
echo ""
echo "2. netcfg directory:"
ls -la /scheme/netcfg/
echo ""
echo "3. netcfg ifaces:"
ls -la /scheme/netcfg/ifaces/
echo ""
echo "4. network driver directory:"
ls -la /scheme/network.pci-00-00-03.0_virtio_net/
echo "=== Done ==="
