#!/usr/bin/env python3
"""
Simple extractor for Redox initfs format.
Based on recipes/core/base/source/initfs/src/types.rs
"""
import struct
import sys
import os
from pathlib import Path

class InitFsExtractor:
    def __init__(self, data):
        self.data = data
        self.parse_header()

    def parse_header(self):
        # Header format from types.rs:
        # magic: [u8; 8] - "RedoxFtw"
        # inode_table_offset: u32
        # creation_time: u64 (sec) + u32 (nsec)
        # inode_count: u16
        # bootstrap_entry: u64
        # initfs_size: u64
        # page_size: u16

        magic = self.data[0:8]
        if magic != b"RedoxFtw":
            raise ValueError(f"Invalid magic: {magic}")

        self.inode_table_offset = struct.unpack('<I', self.data[8:12])[0]
        self.inode_count = struct.unpack('<H', self.data[24:26])[0]
        self.bootstrap_entry = struct.unpack('<Q', self.data[26:34])[0]
        self.initfs_size = struct.unpack('<Q', self.data[34:42])[0]
        self.page_size = struct.unpack('<H', self.data[42:44])[0]

        print(f"InitFS Header:")
        print(f"  Inode table offset: {hex(self.inode_table_offset)}")
        print(f"  Inode count: {self.inode_count}")
        print(f"  Bootstrap entry: {hex(self.bootstrap_entry)}")
        print(f"  InitFS size: {self.initfs_size}")
        print(f"  Page size: {self.page_size}")

    def get_inode(self, inode_num):
        # InodeHeader format:
        # type_and_mode: u32
        # length: u32
        # offset: u32
        # uid: u32
        # gid: u32
        # Total: 20 bytes

        inode_offset = self.inode_table_offset + (inode_num * 20)
        inode_data = self.data[inode_offset:inode_offset + 20]

        type_and_mode, length, offset, uid, gid = struct.unpack('<5I', inode_data)

        inode_type = (type_and_mode >> 28) & 0xF
        mode = type_and_mode & 0xFFF

        return {
            'num': inode_num,
            'type': inode_type,
            'mode': mode,
            'length': length,
            'offset': offset,
            'uid': uid,
            'gid': gid
        }

    def get_file_data(self, inode):
        offset = inode['offset']
        length = inode['length']
        return self.data[offset:offset + length]

    def list_dir(self, inode, path="/"):
        """List directory contents"""
        if inode['type'] != 1:  # DIR type
            return

        # Directory contains DirEntry structures
        # DirEntry format:
        # inode: u16
        # name_len: u16
        # name_offset: u32
        # Total: 8 bytes

        dir_data = self.get_file_data(inode)
        entry_count = len(dir_data) // 8

        entries = []
        for i in range(entry_count):
            entry_offset = i * 8
            entry_bytes = dir_data[entry_offset:entry_offset + 8]
            child_inode, name_len, name_offset = struct.unpack('<HHI', entry_bytes)

            # Get name
            name_bytes = self.data[name_offset:name_offset + name_len]
            name = name_bytes.decode('utf-8', errors='replace')

            child = self.get_inode(child_inode)
            type_char = 'd' if child['type'] == 1 else ('l' if child['type'] == 2 else '-')

            print(f"{type_char} {oct(child['mode'])[2:]:>4} {child['uid']:>4} {child['gid']:>4} {child['length']:>8} {path}{name}")
            entries.append((name, child))

        # Recurse into subdirectories
        for name, child in entries:
            if child['type'] == 1:  # DIR
                self.list_dir(child, f"{path}{name}/")

    def extract(self, output_dir, inode=None, path="/"):
        """Extract initfs to directory"""
        if inode is None:
            inode = self.get_inode(0)  # Root inode

        output_path = Path(output_dir) / path.lstrip('/')

        if inode['type'] == 1:  # DIR
            output_path.mkdir(parents=True, exist_ok=True)

            # Extract directory entries
            dir_data = self.get_file_data(inode)
            entry_count = len(dir_data) // 8

            for i in range(entry_count):
                entry_offset = i * 8
                entry_bytes = dir_data[entry_offset:entry_offset + 8]
                child_inode_num, name_len, name_offset = struct.unpack('<HHI', entry_bytes)

                name_bytes = self.data[name_offset:name_offset + name_len]
                name = name_bytes.decode('utf-8', errors='replace')

                child = self.get_inode(child_inode_num)
                self.extract(output_dir, child, f"{path}{name}" if path.endswith('/') else f"{path}/{name}")

        elif inode['type'] == 0:  # Regular file
            file_data = self.get_file_data(inode)
            output_path.write_bytes(file_data)
            os.chmod(output_path, inode['mode'])
            print(f"Extracted: {output_path}")

        elif inode['type'] == 2:  # Symlink
            link_target = self.get_file_data(inode).decode('utf-8', errors='replace')
            output_path.symlink_to(link_target)
            print(f"Created symlink: {output_path} -> {link_target}")

def main():
    if len(sys.argv) < 2:
        print("Usage: extract_initfs.py <initfs.img> [output_dir]")
        print("  Without output_dir: list contents")
        print("  With output_dir: extract to directory")
        sys.exit(1)

    initfs_path = sys.argv[1]
    data = Path(initfs_path).read_bytes()

    extractor = InitFsExtractor(data)

    if len(sys.argv) >= 3:
        output_dir = sys.argv[2]
        print(f"\nExtracting to {output_dir}...")
        extractor.extract(output_dir)
        print("Done!")
    else:
        print("\nContents:")
        root_inode = extractor.get_inode(0)
        extractor.list_dir(root_inode)

if __name__ == '__main__':
    main()
