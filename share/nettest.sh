#!/bin/sh
echo "=== Quick Net Check ==="
echo "Schemes:"
ls /scheme/ | grep -E "network|net"
echo ""
echo "netcfg/ifaces:"
ls /scheme/netcfg/ifaces/ 2>&1 || echo "empty/error"
echo "Done"
