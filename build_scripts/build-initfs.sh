cd /opt/other/redox/build/aarch64/cranelift-initfs
./initfs-tools-target/release/redox-initfs-ar --max-size 134217728 --output initfs.img initfs/
cp initfs.img /opt/other/redox/mount/boot/initfs && sync
