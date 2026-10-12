// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Coinbitc
/// @notice Fixed supply of one billion COINBITC with 18 decimals.
/// @dev The immediate deployer receives the entire supply. During an IdentityMD
/// launch this is the factory, which handles distribution outside this contract.
contract Coinbitc is ERC20 {
    constructor() ERC20("Coinbitc", "COINBITC") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
