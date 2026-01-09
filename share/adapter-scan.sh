echo "=== Adapter Scan ==="
echo "Scanning /scheme/ for network adapters:"
for f in /scheme/*; do
    name=$(basename $f)
    case $name in
        network*)
            echo "Found adapter: $name"
            ;;
    esac
done
echo "=== Done ==="
