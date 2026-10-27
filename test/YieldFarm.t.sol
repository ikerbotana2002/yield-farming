// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockLPToken} from "../src/MockLPToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";

contract YieldFarmTest is Test {
    MockLPToken lpToken;
    YieldFarm farm;
    MockRewardToken rewardToken;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address charlie = address(0xC1);

    function setUp() public {
        lpToken = new MockLPToken();
        rewardToken = new MockRewardToken();

        farm = new YieldFarm(address(lpToken), address(rewardToken));

        lpToken.transfer(alice, 500 ether);
        lpToken.transfer(bob, 500 ether);

        vm.prank(alice);
        lpToken.approve(address(farm), type(uint256).max);

        vm.prank(bob);
        lpToken.approve(address(farm), type(uint256).max);
    }

    // ----------------------------------------------------
    // ESTADO INICIAL
    // ----------------------------------------------------

    function testInitialState() public view {
        assertEq(farm.totalStaked(), 0);
        assertEq(farm.balances(alice), 0);
        assertEq(farm.balances(bob), 0);

        assertEq(address(farm.lpToken()), address(lpToken));
    }

    // ----------------------------------------------------
    // DEPOSITOS
    // ----------------------------------------------------

    function testDeposit() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        assertEq(farm.balances(alice), 100 ether);
        assertEq(farm.totalStaked(), 100 ether);

        assertEq(lpToken.balanceOf(alice), 400 ether);

        assertEq(lpToken.balanceOf(address(farm)), 100 ether);
    }

    function testTwoUsersDeposit() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.prank(bob);
        farm.deposit(300 ether);

        assertEq(farm.balances(alice), 100 ether);
        assertEq(farm.balances(bob), 300 ether);

        assertEq(farm.totalStaked(), 400 ether);

        assertEq(lpToken.balanceOf(address(farm)), 400 ether);
    }

    function testUserCanDepositSeveralTimes() public {
        vm.startPrank(alice);

        farm.deposit(50 ether);
        farm.deposit(75 ether);

        vm.stopPrank();

        assertEq(farm.balances(alice), 125 ether);
        assertEq(farm.totalStaked(), 125 ether);
    }

    // ----------------------------------------------------
    // RETIRADAS
    // ----------------------------------------------------

    function testPartialWithdrawal() public {
        vm.startPrank(alice);

        farm.deposit(100 ether);
        farm.withdraw(40 ether);

        vm.stopPrank();

        assertEq(farm.balances(alice), 60 ether);
        assertEq(farm.totalStaked(), 60 ether);

        assertEq(lpToken.balanceOf(alice), 440 ether);

        assertEq(lpToken.balanceOf(address(farm)), 60 ether);
    }

    function testFullWithdrawal() public {
        vm.startPrank(alice);

        farm.deposit(100 ether);
        farm.withdraw(100 ether);

        vm.stopPrank();

        assertEq(farm.balances(alice), 0);
        assertEq(farm.totalStaked(), 0);

        assertEq(lpToken.balanceOf(alice), 500 ether);
        assertEq(lpToken.balanceOf(address(farm)), 0);
    }

    function testUsersWithdrawIndependently() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.prank(bob);
        farm.deposit(300 ether);

        vm.prank(alice);
        farm.withdraw(40 ether);

        assertEq(farm.balances(alice), 60 ether);
        assertEq(farm.balances(bob), 300 ether);

        assertEq(farm.totalStaked(), 360 ether);
    }

    // ----------------------------------------------------
    // ERRORES
    // ----------------------------------------------------

    function test_RevertWhen_DepositZero() public {
        vm.expectRevert(YieldFarm.ZeroAmount.selector);

        vm.prank(alice);
        farm.deposit(0);
    }

    function test_RevertWhen_WithdrawZero() public {
        vm.expectRevert(YieldFarm.ZeroAmount.selector);

        vm.prank(alice);
        farm.withdraw(0);
    }

    function test_RevertWhen_WithdrawTooMuch() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.expectRevert(YieldFarm.InsufficientBalance.selector);

        vm.prank(alice);
        farm.withdraw(101 ether);
    }

    function test_RevertWhen_OtherUserWithdraws() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        // Bob no tiene participacion registrada.
        vm.expectRevert(YieldFarm.InsufficientBalance.selector);

        vm.prank(bob);
        farm.withdraw(50 ether);

        // Alice conserva su deposito.
        assertEq(farm.balances(alice), 100 ether);
        assertEq(farm.totalStaked(), 100 ether);
    }

    function test_RevertWhen_NoApproval() public {
        // Charlie recibe LP, pero no autoriza al farming.
        lpToken.transfer(charlie, 100 ether);

        vm.expectRevert();

        vm.prank(charlie);
        farm.deposit(10 ether);
    }

    function test_RevertWhen_InvalidLPToken() public {
        vm.expectRevert(YieldFarm.InvalidLPToken.selector);

        new YieldFarm(address(0), address(rewardToken));
    }

    function test_RevertWhen_AddressHasNoCode() public {
        vm.expectRevert(YieldFarm.InvalidLPToken.selector);

        new YieldFarm(address(0x1234), address(rewardToken));
    }

    // ----------------------------------------------------
    // DONACIONES DIRECTAS
    // ----------------------------------------------------

    function testDirectTransferDoesNotIncreaseStake() public {
        vm.prank(alice);
        lpToken.transfer(address(farm), 10 ether);

        assertEq(lpToken.balanceOf(address(farm)), 10 ether);

        assertEq(farm.balances(alice), 0);
        assertEq(farm.totalStaked(), 0);
    }

    // ----------------------------------------------------
    // FUZZ TESTING
    // ----------------------------------------------------

    function testFuzzDepositAndWithdraw(uint256 amount) public {
        amount = bound(amount, 1, 500 ether);

        uint256 initialWalletBalance = lpToken.balanceOf(alice);

        vm.startPrank(alice);

        farm.deposit(amount);

        assertEq(farm.balances(alice), amount);
        assertEq(farm.totalStaked(), amount);

        farm.withdraw(amount);

        vm.stopPrank();

        assertEq(farm.balances(alice), 0);
        assertEq(farm.totalStaked(), 0);

        assertEq(lpToken.balanceOf(alice), initialWalletBalance);

        assertEq(lpToken.balanceOf(address(farm)), 0);
    }
}
