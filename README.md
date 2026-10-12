# Coinbitc (COINBITC)

Coinbitc is a fixed-supply ERC-20 token for Ethereum. The complete supply is
created once in the constructor and assigned to the immediate deployer.

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/Coinbitc.sol:Coinbitc` |
| Token name | `Coinbitc` |
| Symbol | `COINBITC` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial recipient | Constructor `msg.sender` |
| Target chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The brief is implemented as a standard ERC-20 using the vendored OpenZeppelin
Contracts v5.0.2 implementation. Transfers deliver the exact requested amount.
There are no transfer fees, rebases, transfer restrictions, burn functions,
post-deployment mint functions, owner, pause, blacklist, upgrade, or recovery
functions. The metadata and supply cannot be changed after construction.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert
with ERC-20 custom errors on invalid operations. Zero-amount transfers between
nonzero addresses are valid and emit `Transfer`. Transfers to the zero address
and approvals to the zero spender revert. Self-transfers preserve balances.
Approvals replace the previous allowance; approving zero revokes it. Finite
allowances decrease when spent, and `type(uint256).max` represents an unlimited
allowance that does not decrease. `approve` emits `Approval`; this vendored
implementation does not emit `Approval` when `transferFrom` spends allowance.

No external contracts, addresses, or services need configuration. Construction
and token operations make no external calls. The token neither implements nor
initializes a liquidity pool, distributor, or application contract.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler, Cancun EVM, optimizer (200 runs), and
`bytecode_hash = "none"`. All source dependencies and their licenses are
vendored under `lib/`; no network installation or submodule is required.
See [DEPENDENCIES.md](DEPENDENCIES.md) for versions and archive checksums.
FFI and filesystem permissions are not enabled. Tests use local EVM state,
without an RPC, environment variables, keys, or shared external state.

Validated locally with Foundry 1.8.3 and Solidity 0.8.26: `forge build`,
`forge test`, and `forge fmt --check` passed. A fresh copy containing only the
project sources, tests, dependencies, and configuration also passed offline with
an empty environment (apart from executable lookup) and four test threads. Its
creation and runtime bytecode matched the original build exactly.

The suite covers exact metadata and constructor minting (including the single
mint event), CREATE2 factory deployment, exact distribution and claim transfers,
transfers and approvals, allowance exhaustion and revocation, unlimited
allowances, self/zero/full-balance transfers, unauthorized spending, invalid
addresses, insufficient balances/allowances, rollback after failure, rejected
administrative calls, and prohibited runtime opcodes. Three fuzz tests run 512
cases each. Two stateful invariants run 128 sequences of 64 calls each, checking
constant supply and conservation of balances across transfers and approvals.

The factory and distribution fixtures are local test helpers, not production
launch contracts. They validate token accounting; they do not simulate Uniswap
pool initialization, liquidity calculations, or actual swaps. The provided
protected launch harness depends on the network's launch sources and resolved
launch parameters and is run separately by the network's verifier.

## Deployment and launch responsibilities

Deploy the creation bytecode for `src/Coinbitc.sol:Coinbitc` with no constructor
arguments and no ETH. For review, obtain the bytecode and ABI locally:

```sh
forge inspect src/Coinbitc.sol:Coinbitc bytecode
forge inspect src/Coinbitc.sol:Coinbitc abi
```

During an IdentityMD custom-token launch, the factory is the immediate deployer
and receives all `10^27` base units. The transaction sender or requester receives
nothing directly from the constructor. A direct wallet deployment instead mints
the whole supply to that wallet; an intermediate deployment helper receives the
supply itself and must be able to distribute it.

The launch service is responsible for its factory, CREATE2 salt, launch manifest,
pool, and distribution. The token needs no address exemptions because every
transfer is exact. The supplied launch policy assigns 10% to the network
distributor, 88% to pool seeding, and 2% to
`0x12a7aad083cef06fef7c295514b52fc8bc81960d`. These allocations happen outside
the token after its constructor has minted everything to the factory.

For the separate manifest step, the supplied policy specifies native ETH as the
pair, fee `12500` (1.25%), tick spacing `60`, reference initial price
`79228162514264337593543950336`, and initial market cap
`10000000000000000000` wei (10 ETH). The launch service derives the actual opening
price. None of these values is a token constructor argument or token setting.
This project does not supply `launch.json` or perform deployment transactions.

## After launch

No initialization calls, owner settings, keepers, or privileged operations are
needed. The launch operator should verify the source and compiler settings on
the explorer, confirm the deployed metadata and total supply, and reconcile the
factory's distribution events and balances against the launch manifest.

Holders are responsible for recipient addresses and allowances. Prefer bounded
approvals, revoke unused approvals, and confirm a zero approval before granting
a replacement to reduce the standard ERC-20 allowance-change race. Tokens sent
to this token contract or another contract unable to transfer them cannot be
recovered by an administrator. The token has no payable entry point or ETH
withdrawal function.

Local build, unit, fuzz, and invariant checks do not constitute an independent
security audit. An independent review and the network's full launch-flow checks
remain release responsibilities. Slither and Mythril are not part of the local
checks reported for this assignment.
