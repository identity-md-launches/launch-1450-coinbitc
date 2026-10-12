// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Coinbitc} from "../src/Coinbitc.sol";

/// @dev Test fixture only; the production launch factory is supplied externally.
contract CoinbitcFactoryFixture {
    function deploy(bytes32 salt) external returns (Coinbitc) {
        return new Coinbitc{salt: salt}();
    }

    function move(Coinbitc token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract CoinbitcTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Coinbitc internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Coinbitc();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Coinbitc");
        assertEq(token.symbol(), "COINBITC");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        Coinbitc fresh = new Coinbitc();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2MintsToImmediateFactoryDeployer() public {
        CoinbitcFactoryFixture factory = new CoinbitcFactoryFixture();
        bytes32 salt = keccak256("local deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Coinbitc).creationCode))
                    )
                )
            )
        );
        Coinbitc deployed = factory.deploy(salt);

        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(tx.origin), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
    }

    function test_factoryDistributionAndClaimTransfersAreExact() public {
        CoinbitcFactoryFixture factory = new CoinbitcFactoryFixture();
        Coinbitc deployed = factory.deploy(keccak256("local distribution test"));
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool balance fixture");
        address remainder = makeAddr("remainder fixture");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 88 / 100;
        uint256 remainderShare = SUPPLY * 2 / 100;

        factory.move(deployed, distributor, swarmShare);
        factory.move(deployed, pool, poolShare);
        factory.move(deployed, remainder, remainderShare);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), swarmShare);
        assertEq(deployed.balanceOf(pool), poolShare);
        assertEq(deployed.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarmShare));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), swarmShare);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 42 ether);
        assertTrue(token.transfer(alice, 42 ether));
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireBalanceCanBeTransferred() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferDoesNotChangeBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferInsufficientBalanceRevertsWithoutStateChange() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAmountCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroAddressRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 9 ether);
        assertTrue(token.approve(spender, 9 ether));
        assertEq(token.allowance(address(this), spender), 9 ether);
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalRevocationPreventsSpending() public {
        assertTrue(token.approve(spender, 9 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), bob, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanExhaustAllowance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_transferFromPreservesInfiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertTrue(token.transferFrom(address(this), bob, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3 ether);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToSelfConsumesAllowanceButPreservesBalance() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 1 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromInsufficientAllowanceRevertsWithoutStateChange() public {
        assertTrue(token.approve(spender, 4));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 4, 5));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 5);
        assertEq(token.allowance(address(this), spender), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_failedTransferFromRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToZeroRevertsAndPreservesAllowance() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(alice, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_runtimeHasNoPrivilegedExecutionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_transferPreservesSupplyAndBalances(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        if (recipient == address(this)) recipient = alice;
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromSpendsOnlyApprovedAmount(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_excessTransferReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
