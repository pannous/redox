Here's how tools get into /usr/bin/ and survive rebuilds:

  The Build Flow

  config/base.toml → [packages] section → recipe.toml → build → stage → .pkg → filesystem

⏺ Wow, 2713 recipe.toml files! Here's what we can clean up:

  MUST KEEP (source code used by build-cranelift.sh):
  - recipes/core/kernel/source/
  - recipes/core/relibc/source/
  - recipes/core/base/source/
  - recipes/core/ion/source/ (ion shell)

  Keep an eye on:
    libs, math, net, dev,web, wip, tools, shells, other, tests,  
  - Most of recipes/core/* except kernel, relibc, base, ion
  -  binutils bootloader contain coreutils dash extrautils findutils installer  kernel liner netdb netutils nushell pkgar pkgutils profiled redoxfs relibc strace termion userutils uutils

  OPTIONAL for now (25 categories, ~2700 recipes!):
  - Everything in: archives, artwork, demos,  doc, emulators, fonts, games, graphics, groups, gui, icons, sound, tui, video, 

17GB total, only ~9.4GB needed. We could reclaim ~7.5GB but let's leave em for now.

  Adding Your OWN package:

  Key locations:
  ┌───────────────────┬────────────────────────────────────────────────────────────┐
  │       Step        │                          Location                          │
  ├───────────────────┼────────────────────────────────────────────────────────────┤
  │ Package selection │ config/base.toml or filesystem.toml - [packages.yourpkg]   │
  ├───────────────────┼────────────────────────────────────────────────────────────┤
  │ Recipe definition │ recipes/category/yourpkg/recipe.toml                       │
  ├───────────────────┼────────────────────────────────────────────────────────────┤
  │ Source code       │ recipes/category/yourpkg/source/                           │
  ├───────────────────┼────────────────────────────────────────────────────────────┤
  │ Compiled output   │ recipes/.../source/target/aarch64-unknown-redox-*/release/ │
  └───────────────────┴────────────────────────────────────────────────────────────┘
  To Make a Tool Persist After Complete Rebuild

  Option 1: Create your own recipe (recommended for custom tools)
  mkdir -p recipes/tools/mytool/
  # Create recipe.toml with [source] and [build] sections
  # Build scripts copy binaries to ${COOKBOOK_STAGE}/usr/bin/

  Option 2: Add to base recipe (for essential tools)
  Edit recipes/core/base/recipe.toml - add your binary to the BINS array and copy it to ${COOKBOOK_STAGE}/usr/bin/.

  Option 3: Use [[files]] in config (for simple files)
  Add to config/base.toml:
  [[files]]
  path = "/usr/bin/mytool"
  data = "#!/bin/sh\necho hello"

  Your Cranelift Build

  Since you're using build-cranelift.sh which bypasses the normal recipe system, tools built that way need to be:
  1. Added to your build script's compilation list
  2. Copied to the staging/initfs location your script uses
  3. Or injected post-build into the image

  The recipes under recipes/core/coreutils/source/ show the pattern - binaries compiled there would go into /usr/bin/ if coreutils is in your [packages] section.



# Hack to add OSMesa example:
sed -i "s/Requires:/Requires: osmesa >= 8.0.0/" "${COOKBOOK_STAGE}/usr/lib/pkgconfig/sdl2.pc"