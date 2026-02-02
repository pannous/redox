#!/bin/bash
# Fix syscall imports from 0.6 to 0.7 API

fix_file() {
    local file="$1"
    echo "Fixing: $file"

    # Check if file has the pattern we're looking for
    if grep -q "use syscall::{.*Error.*}" "$file" || grep -q "use syscall::{.*Result.*}" "$file"; then
        # Create a temporary file
        tmp_file=$(mktemp)

        # Process the file line by line
        awk '
        /^use syscall::.*{.*Error.*}/ || /^use syscall::.*{.*Result.*}/ {
            # Extract everything between the braces
            match($0, /\{([^}]+)\}/, arr)
            if (arr[1]) {
                split(arr[1], items, ",")

                has_error = 0
                has_result = 0
                other_items = ""

                for (i in items) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
                    if (items[i] == "Error") {
                        has_error = 1
                    } else if (items[i] == "Result") {
                        has_result = 1
                    } else if (items[i] != "") {
                        if (other_items != "") other_items = other_items ", "
                        other_items = other_items items[i]
                    }
                }

                # Print the error import if needed
                if (has_error || has_result) {
                    error_imports = ""
                    if (has_error) error_imports = "Error"
                    if (has_result) {
                        if (error_imports != "") error_imports = error_imports ", "
                        error_imports = error_imports "Result"
                    }
                    print "use syscall::error::{" error_imports "};"
                }

                # Print the other imports if any
                if (other_items != "") {
                    print "use syscall::{" other_items "};"
                }
            }
            next
        }
        { print }
        ' "$file" > "$tmp_file"

        # Replace original file
        mv "$tmp_file" "$file"
    fi
}

# Fix all the files
for file in \
    recipes/core/base/source/drivers/acpid/src/acpi.rs \
    recipes/core/base/source/drivers/acpid/src/aml_physmem.rs \
    recipes/core/base/source/drivers/acpid/src/ec.rs \
    recipes/core/base/source/drivers/acpid/src/scheme.rs \
    recipes/core/base/source/drivers/graphics/bgad/src/scheme.rs \
    recipes/core/base/source/drivers/graphics/fbbootlogd/src/scheme.rs \
    recipes/core/base/source/drivers/graphics/fbcond/src/scheme.rs \
    recipes/core/base/source/drivers/graphics/ihdgd/src/device/ddi.rs \
    recipes/core/base/source/drivers/graphics/virtio-gpu-venusd/src/scheme.rs \
    recipes/core/base/source/drivers/graphics/virtio-gpud/src/scheme.rs \
    recipes/core/base/source/drivers/hwd/src/backend/acpi.rs \
    recipes/core/base/source/drivers/hwd/src/backend/devicetree.rs \
    recipes/core/base/source/drivers/hwd/src/backend/legacy.rs \
    recipes/core/base/source/drivers/hwd/src/backend/mod.rs \
    recipes/core/base/source/drivers/input/ps2d/src/controller.rs \
    recipes/core/base/source/drivers/input/usbhidd/src/reqs.rs \
    recipes/core/base/source/drivers/inputd/src/lib.rs \
    recipes/core/base/source/drivers/net/virtio-netd/src/main.rs \
    recipes/core/base/source/ipcd/src/scheme.rs \
    recipes/core/base/source/ptyd/src/scheme.rs \
    recipes/core/base/source/randd/src/main.rs \
    recipes/core/base/source/zerod/src/main.rs \
    recipes/core/base/source/logd/src/scheme.rs \
    recipes/core/base/source/ramfs/src/main.rs
do
    if [ -f "$file" ]; then
        fix_file "$file"
    fi
done

echo "Done!"
