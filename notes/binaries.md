⏺ To include a binary in fresh builds (de novo), you have two approaches:

  Option 1: Add to existing base recipe (simplest)

  The base recipe at recipes/core/base/ bundles multiple binaries. Add your tool there:

  # Copy source/binary to the base source directory
  cp /opt/other/redox/share/tool recipes/core/base/source/

  # Edit the build script to include it
  # Then rebuild with:
  cd recipes/core/base/source && ./build-initfs-cranelift.sh

  Option 2: Create a new recipe (for standalone packages)

  mkdir -p recipes/core/mytool

  Create recipes/core/mytool/recipe.toml:
  [source]
  # For a git repo:
  git = "https://github.com/you/mytool.git"
  # Or for local source:
  # tar = "file:///opt/other/redox/share/mytool.tar"

  [build]
  template = "cargo"

  Then add it to the filesystem config. Edit config/aarch64/minimal.toml (or your build config):
  [packages]
  mytool = {}

  Option 3: Add pre-built binary to filesystem.toml

  Edit mount/filesystem.toml to include the file directly:
  [[files]]
  path = "/usr/bin/tool"
  data = "file:share/tool"
  mode = 0o755

  This copies from host share/tool into the image at build time.

  Which to use?
  ┌──────────────────────────────┬─────────────────────────────────────┐
  │            Method            │              Best for               │
  ├──────────────────────────────┼─────────────────────────────────────┤
  │ Add to base                  │ Core system tools, drivers          │
  ├──────────────────────────────┼─────────────────────────────────────┤
  │ New recipe                   │ Standalone packages with own source │
  ├──────────────────────────────┼─────────────────────────────────────┤
  │ [[files]] in filesystem.toml │ Pre-built binaries, quick additions │
  └──────────────────────────────┴─────────────────────────────────────┘
  For most cases, adding a [[files]] entry to mount/filesystem.toml is the fastest path to persistent inclusion.