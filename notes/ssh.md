# SSH for Redox

## Built with Modern RustCrypto
Updated redox-ssh from rust-crypto (ancient) to modern RustCrypto crates:
- aes + ctr for AES-CTR encryption
- hmac + sha2 for HMAC-SHA256
- ed25519-dalek for Ed25519 signatures
- x25519-dalek for Curve25519 key exchange

## Build Command
```bash
cd /opt/other/redox/recipes/net/redox-ssh/source
env CARGO_INCREMENTAL=0 cargo +nightly build --release \
    --target aarch64-unknown-redox \
    --config net.offline=false \
    -Zbuild-std=std,panic_abort
```

## Binaries in share/bin/
- ssh - SSH client (placeholder, prints "Hello from ssh!")
- sshd - SSH server daemon
- ssh-keygen - Key generation tool

## Usage in Redox
```bash
# Copy to /tmp to make executable (9P share doesn't support chmod in Redox)
cp /scheme/9p.hostshare/bin/ssh-keygen /tmp/
chmod +x /tmp/ssh-keygen

# Generate server key
cd /tmp
./ssh-keygen   # Creates server.key

# Start sshd (foreground mode for testing)
./sshd -f -vvv -p 2222

# Or background
./sshd -p 2222
```

## Port Forwarding
QEMU configured with: -netdev user,id=net0,hostfwd=tcp::2222-:22
From host: ssh -p 2222 root@localhost (when sshd running)

## Limitations
- SSH client is just a placeholder
- Authentication is minimal
- No full pty support on Redox yet
