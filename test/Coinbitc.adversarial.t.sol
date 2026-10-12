// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Coinbitc} from "../src/Coinbitc.sol";

/// @dev Complements the deployment and ERC-20 examples with authorization boundaries
/// and algebraic properties. All funding uses real transfers of the constructor mint.
/// forge-config: default.fuzz.runs = 1000
contract CoinbitcAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Coinbitc internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Coinbitc();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_oneWeiTransferAndReturnHaveNoRounding() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCallerStillRequiresSelfApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_spenderCanBeTheRecipient() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        uint256 approval = type(uint256).max - 1;
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), approval - 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_infiniteAllowanceCanBeLoweredAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_approvalDoesNotFollowTokensToAnotherHolder() public {
        assertTrue(token.transfer(alice, 1));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 1));
        assertTrue(token.transfer(bob, 1));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalsAreIsolatedByOwnerAndSpender() public {
        assertTrue(token.transfer(alice, 20));
        assertTrue(token.approve(spender, 11));
        assertTrue(token.approve(bob, 13));
        vm.prank(alice);
        assertTrue(token.approve(spender, 17));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 7));
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(address(this), spender), 11);
        assertEq(token.allowance(address(this), bob), 13);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), 13);
        assertEq(token.balanceOf(bob), 7);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalWithoutBalanceBecomesSpendableAfterFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_infiniteAllowanceDoesNotPermitMaximumOverdraw() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromEmitsEventAndPreservesApproval() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromToZeroIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedSelfTransferFromRestoresAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approval));
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitTransfersEqualSingleTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        Coinbitc singleTransfer = new Coinbitc();
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, total - first));
        assertTrue(singleTransfer.transfer(alice, total));
        assertEq(token.balanceOf(alice), singleTransfer.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), singleTransfer.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransfer.totalSupply(), SUPPLY);
    }

    function testFuzz_consumedAllowanceCannotBeReusedAfterRefund(uint256 approval, uint256 first) public {
        approval = bound(approval, 1, SUPPLY);
        first = bound(first, 0, approval);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, first));
        assertEq(token.allowance(address(this), spender), approval - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, approval - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), approval);

        vm.prank(bob);
        assertTrue(token.transfer(address(this), approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalUsesLastValue(uint256 original, uint256 replacement) public {
        assertTrue(token.approve(spender, original));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        uint256 amount = replacement < SUPPLY ? replacement : SUPPLY;
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(
            token.allowance(address(this), spender),
            replacement == type(uint256).max ? replacement : replacement - amount
        );
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
