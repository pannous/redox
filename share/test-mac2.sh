echo "=== MAC Test 2 ==="
echo "Network scheme found:"
ls /scheme/ | grep network
echo ""
echo "Read MAC directly:"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac
echo "< MAC end (6 binary bytes)"
echo "=== Done ==="
