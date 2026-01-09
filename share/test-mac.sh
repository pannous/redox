echo "=== MAC Test ==="
echo "1. Open network scheme:"
ls /scheme/ | grep network
echo ""
echo "2. Read MAC (6 bytes binary):"
dd if=/scheme/network.pci-00-00-03.0_virtio_net/mac bs=6 count=1
echo ""
echo "3. Raw bytes:"
od -x /scheme/network.pci-00-00-03.0_virtio_net/mac
echo "=== Done ==="
