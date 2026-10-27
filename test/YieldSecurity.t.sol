// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockLPToken} from "../src/MockLPToken.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

contract YieldSecurityTest is Test {
    MockLPToken lpToken;
    MockRewardToken rewardToken;
    YieldFarm farm;

    address alice = address(0xA1);
    address bob = address(0xB1);

    uint256 constant DURATION = 10 days;
    uint256 constant TOTAL_REWARDS = 40 ether;
    uint256 constant TOLERANCE = 1_000_000;

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

        rewardToken.approve(address(farm), TOTAL_REWARDS);
        farm.startRewards(TOTAL_REWARDS, DURATION);
    }

    function testEmergencyWithdrawReturnsAllLP() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(block.timestamp + 5 days);

        assertGt(farm.earned(alice), 0);

        vm.prank(alice);
        farm.emergencyWithdraw();

        assertEq(farm.balances(alice), 0);
        assertEq(farm.totalStaked(), 0);
        assertEq(farm.earned(alice), 0);
        assertEq(lpToken.balanceOf(alice), 500 ether);
    }

    function testEmergencyWithdrawDoesNotAffectBob() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.prank(bob);
        farm.deposit(300 ether);

        vm.warp(block.timestamp + 3 days);

        uint256 bobRewardsBefore = farm.earned(bob);

        vm.prank(alice);
        farm.emergencyWithdraw();

        assertEq(farm.balances(alice), 0);
        assertEq(farm.balances(bob), 300 ether);
        assertEq(farm.totalStaked(), 300 ether);

        assertApproxEqAbs(farm.earned(bob), bobRewardsBefore, TOLERANCE);
    }

    function testEmergencyWithdrawForfeitsRewards() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(block.timestamp + 5 days);

        uint256 pending = farm.earned(alice);
        assertGt(pending, 0);

        vm.prank(alice);
        farm.emergencyWithdraw();

        assertEq(farm.rewards(alice), 0);
        assertEq(farm.earned(alice), 0);

        // No puede reclamar los RWD abandonados.
        vm.prank(alice);
        vm.expectRevert(YieldFarm.NoRewards.selector);
        farm.claimRewards();
    }

    function test_RevertWhen_EmergencyWithoutStake() public {
        vm.prank(alice);
        vm.expectRevert(YieldFarm.NoStake.selector);
        farm.emergencyWithdraw();
    }

    function testNormalWithdrawalKeepsRewards() public {
        vm.prank(alice);
        farm.deposit(100 ether);

        vm.prank(bob);
        farm.deposit(100 ether);

        vm.warp(block.timestamp + 2 days);

        // Alicia retira normalmente.
        vm.prank(alice);
        farm.withdraw(100 ether);

        // Bob utiliza la salida de emergencia.
        vm.prank(bob);
        farm.emergencyWithdraw();

        assertGt(farm.earned(alice), 0);
        assertEq(farm.earned(bob), 0);

        assertEq(lpToken.balanceOf(alice), 500 ether);
        assertEq(lpToken.balanceOf(bob), 500 ether);
    }
}
