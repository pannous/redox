echo "MAC Read Test"
echo "File exists check:"
test -f /scheme/network.pci-00-00-03.0_virtio_net/mac && echo "YES" || echo "NO"
echo "Cat MAC (binary):"
cat /scheme/network.pci-00-00-03.0_virtio_net/mac > /tmp/mac.bin
ls -la /tmp/mac.bin
echo "Done"
