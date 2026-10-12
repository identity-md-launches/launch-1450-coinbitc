# Vendored dependencies

These files are included as ordinary source files. No package installation,
submodules, FFI, or network access is needed to build or test.
Solidity 0.8.26 and Foundry must already be installed on the build machine.

## openzeppelin-contracts v5.0.2

- Upstream tag: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2
- Archive: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
- Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- Included files: 6.

## forge-std v1.9.7

- Upstream tag: https://github.com/foundry-rs/forge-std/tree/v1.9.7
- Archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- Included files: 30.

OpenZeppelin: only the unchanged ERC-20 implementation, its transitive imports,
and MIT license are included. Forge Standard Library: the unchanged `src/` tree
and MIT/Apache licenses are included for tests. Upstream tests, build settings,
and repository metadata are intentionally omitted.
