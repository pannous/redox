#!/usr/bin/env python3
import re
import sys

def process_file(filepath):
    """Process a single file"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        original_content = content

        # Pattern to match multi-line syscall imports with Error or Result
        # Match: use syscall::{...} potentially across multiple lines
        pattern = r'use syscall::\{([^}]+)\};'

        def replace_import(match):
            items_str = match.group(1)
            # Split by comma and clean up whitespace/newlines
            items = [item.strip() for item in re.split(r'[,\s]+', items_str) if item.strip()]

            has_error = 'Error' in items
            has_result = 'Result' in items

            # If neither Error nor Result, no change
            if not has_error and not has_result:
                return match.group(0)

            # Remove Error and Result
            other_items = [item for item in items if item not in ['Error', 'Result']]

            # Build replacements
            result = []

            # Add error import
            error_items = []
            if has_error:
                error_items.append('Error')
            if has_result:
                error_items.append('Result')
            result.append(f"use syscall::error::{{{', '.join(error_items)}}};")

            # Add other imports if any
            if other_items:
                # Format nicely if more than 3 items
                if len(other_items) > 3:
                    items_formatted = ',\n    '.join(other_items)
                    result.append(f"use syscall::{{\n    {items_formatted},\n}};")
                else:
                    result.append(f"use syscall::{{{', '.join(other_items)}}};")

            return '\n'.join(result)

        # Apply the replacement
        content = re.sub(pattern, replace_import, content, flags=re.DOTALL)

        if content != original_content:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Fixed: {filepath}")
            return True
        return False
    except FileNotFoundError:
        print(f"File not found: {filepath}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error processing {filepath}: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    files = [
        'recipes/core/base/source/drivers/acpid/src/acpi.rs',
        'recipes/core/base/source/drivers/acpid/src/aml_physmem.rs',
        'recipes/core/base/source/drivers/acpid/src/ec.rs',
        'recipes/core/base/source/drivers/acpid/src/scheme.rs',
        'recipes/core/base/source/drivers/graphics/bgad/src/scheme.rs',
        'recipes/core/base/source/drivers/graphics/fbbootlogd/src/scheme.rs',
        'recipes/core/base/source/drivers/graphics/fbcond/src/scheme.rs',
        'recipes/core/base/source/drivers/graphics/ihdgd/src/device/ddi.rs',
        'recipes/core/base/source/drivers/graphics/virtio-gpu-venusd/src/scheme.rs',
        'recipes/core/base/source/drivers/graphics/virtio-gpud/src/scheme.rs',
        'recipes/core/base/source/drivers/hwd/src/backend/acpi.rs',
        'recipes/core/base/source/drivers/hwd/src/backend/devicetree.rs',
        'recipes/core/base/source/drivers/hwd/src/backend/legacy.rs',
        'recipes/core/base/source/drivers/hwd/src/backend/mod.rs',
        'recipes/core/base/source/drivers/input/ps2d/src/controller.rs',
        'recipes/core/base/source/drivers/input/usbhidd/src/reqs.rs',
        'recipes/core/base/source/drivers/inputd/src/lib.rs',
        'recipes/core/base/source/drivers/net/virtio-netd/src/main.rs',
        'recipes/core/base/source/ptyd/src/scheme.rs',
        'recipes/core/base/source/randd/src/main.rs',
        'recipes/core/base/source/zerod/src/main.rs',
        'recipes/core/base/source/logd/src/scheme.rs',
        'recipes/core/base/source/ramfs/src/main.rs',
    ]

    fixed_count = sum(1 for f in files if process_file(f))
    print(f"\nFixed {fixed_count} files")
