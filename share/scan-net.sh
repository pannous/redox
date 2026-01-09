echo "=== Scan Network ==="
echo "All schemes:"
ls /scheme/
echo ""
echo "Network schemes:"
ls /scheme/ | grep network
echo ""
echo "Try opening network scheme:"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac
echo ""
echo "smolnetd status:"
ps aux | grep smol
echo "=== Done ==="
