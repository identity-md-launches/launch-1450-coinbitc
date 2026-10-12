// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Coinbitc} from "../src/Coinbitc.sol";

/// @dev The four holders are a closed set: every successful transfer stays within it.
/// Expected balances and allowances come from requested operations, never token reads.
/// Rejected calls leave that ledger unchanged, so invariants also check atomicity.
contract CoinbitcHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Coinbitc internal immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Coinbitc token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant holder ", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], type(uint256).max);
    }

    function revokeApproval(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], 0);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, balance < allowanceBefore ? balance : allowanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (allowanceBefore != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    function transferRoundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        // Always pick a distinct counterparty; self transfers are reached by transfer().
        address to = actors[(fromSeed % actors.length + 1 + toSeed % (actors.length - 1)) % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // A round trip must restore the ledger, including all unrelated allowances.
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        // Revoke unlimited approvals so this action always reaches a rejection.
        if (allowanceBefore == type(uint256).max) {
            _approve(owner, spender, 0);
            allowanceBefore = 0;
        }
        amount = bound(amount, allowanceBefore + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowanceBefore, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferFromOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        // Sufficient authorization isolates the balance check and its rollback.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CoinbitcInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Coinbitc internal token;
    CoinbitcHandler internal handler;

    function setUp() public {
        token = new Coinbitc();
        handler = new CoinbitcHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
        }

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = CoinbitcHandler.transfer.selector;
        selectors[1] = CoinbitcHandler.approve.selector;
        selectors[2] = CoinbitcHandler.transferFrom.selector;
        selectors[3] = CoinbitcHandler.approveInfinite.selector;
        selectors[4] = CoinbitcHandler.revokeApproval.selector;
        selectors[5] = CoinbitcHandler.transferRoundTrip.selector;
        selectors[6] = CoinbitcHandler.transferOverBalance.selector;
        selectors[7] = CoinbitcHandler.transferFromOverAllowance.selector;
        selectors[8] = CoinbitcHandler.transferFromOverBalance.selector;
        selectors[9] = CoinbitcHandler.transferToZero.selector;
        selectors[10] = CoinbitcHandler.transferFromToZero.selector;
        selectors[11] = CoinbitcHandler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsAlwaysOneBillionTokens() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertLe(balance, SUPPLY);
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesMatchAuthorizedTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder balance differs from ledger");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance differs from ledger"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }

    function invariant_metadataIsStable() public view {
        assertEq(token.name(), "Coinbitc");
        assertEq(token.symbol(), "COINBITC");
        assertEq(token.decimals(), 18);
    }
}
