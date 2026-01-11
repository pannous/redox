#!/usr/bin/env python3
"""Simple pkgar extractor - skips signature verification"""
import struct
import sys
import os

HEADER_SIZE = 136  # 64 + 32 + 32 + 8
ENTRY_SIZE = 308   # 32 + 8 + 8 + 4 + 256

def extract_pkgar(pkgar_path, output_dir):
    with open(pkgar_path, 'rb') as f:
        # Read header
        header = f.read(HEADER_SIZE)
        if len(header) < HEADER_SIZE:
            print(f"Error: File too small for header")
            return False

        # Parse header
        signature = header[0:64]
        public_key = header[64:96]
        blake3_hash = header[96:128]
        count = struct.unpack('<Q', header[128:136])[0]

        print(f"Package has {count} entries")

        # Read all entries
        entries = []
        for i in range(count):
            entry_data = f.read(ENTRY_SIZE)
            if len(entry_data) < ENTRY_SIZE:
                print(f"Error: Truncated entry {i}")
                return False

            blake3 = entry_data[0:32]
            offset = struct.unpack('<Q', entry_data[32:40])[0]
            size = struct.unpack('<Q', entry_data[40:48])[0]
            mode = struct.unpack('<I', entry_data[48:52])[0]
            path_bytes = entry_data[52:308]

            # Extract null-terminated path
            try:
                null_pos = path_bytes.index(0)
                path = path_bytes[:null_pos].decode('utf-8')
            except ValueError:
                path = path_bytes.decode('utf-8', errors='replace')

            entries.append({
                'path': path,
                'offset': offset,
                'size': size,
                'mode': mode
            })

        # Calculate data section start
        data_start = HEADER_SIZE + (count * ENTRY_SIZE)
        print(f"Data section starts at offset {data_start}")

        # Extract files
        extracted = 0
        for entry in entries:
            out_path = os.path.join(output_dir, entry['path'])
            os.makedirs(os.path.dirname(out_path), exist_ok=True)

            # Seek to file data
            f.seek(data_start + entry['offset'])
            data = f.read(entry['size'])

            # Check if it's a directory (size 0, mode has directory bit)
            if entry['size'] == 0 and (entry['mode'] & 0o40000):
                os.makedirs(out_path, exist_ok=True)
            else:
                with open(out_path, 'wb') as out:
                    out.write(data)
                # Set mode
                os.chmod(out_path, entry['mode'] & 0o7777)

            extracted += 1
            if extracted % 100 == 0:
                print(f"Extracted {extracted}/{count} files...")

        print(f"Extracted {extracted} files to {output_dir}")
        return True

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <pkgar_file> <output_dir>")
        sys.exit(1)

    if not extract_pkgar(sys.argv[1], sys.argv[2]):
        sys.exit(1)
