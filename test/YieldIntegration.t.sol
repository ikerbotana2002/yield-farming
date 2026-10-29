// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockLPToken} from "../src/MockLPToken.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

contract YieldIntegrationTest is Test {
    MockLPToken lp;
    MockRewardToken rwd;
    YieldFarm farm;

    address alice = address(0xA1);
    address bob = address(0xB1);

    uint256 constant TOLERANCE = 1_000_000;

    function setUp() public {
        lp = new MockLPToken();
        rwd = new MockRewardToken();

        farm = new YieldFarm(address(lp), address(rwd));

        lp.transfer(alice, 100 ether);
        lp.transfer(bob, 300 ether);

        vm.prank(alice);
        lp.approve(address(farm), type(uint256).max);

        vm.prank(bob);
        lp.approve(address(farm), type(uint256).max);

        rwd.approve(address(farm), 40 ether);

        farm.startRewards(40 ether, 10 days);
    }

    function testCompleteFarmingLifecycle() public {
        uint256 start = block.timestamp;

        // DIA 0: Alice deposita 100 LP.
        vm.prank(alice);
        farm.deposit(100 ether);

        // DIA 5: Alicia acumula 20 RWD.
        vm.warp(start + 5 days);

        assertApproxEqAbs(farm.earned(alice), 20 ether, TOLERANCE);

        // Bob entra con 300 LP.
        vm.prank(bob);
        farm.deposit(300 ether);

        assertEq(farm.earned(bob), 0);

        // DIA 7: Alicia retira 40 LP.
        vm.warp(start + 7 days);

        vm.prank(alice);
        farm.withdraw(40 ether);

        assertEq(farm.balances(alice), 60 ether);
        assertEq(farm.balances(bob), 300 ether);
        assertEq(farm.totalStaked(), 360 ether);

        assertApproxEqAbs(farm.earned(alice), 22 ether, TOLERANCE);

        assertApproxEqAbs(farm.earned(bob), 6 ether, TOLERANCE);

        // DIA 10: termina la distribucion.
        vm.warp(start + 10 days);

        uint256 aliceEarned = farm.earned(alice);
        uint256 bobEarned = farm.earned(bob);

        assertApproxEqAbs(aliceEarned, 24 ether, TOLERANCE);

        assertApproxEqAbs(bobEarned, 16 ether, TOLERANCE);

        // Ambos reclaman sus RWD.
        vm.prank(alice);
        farm.claimRewards();

        vm.prank(bob);
        farm.claimRewards();

        assertEq(rwd.balanceOf(alice), aliceEarned);
        assertEq(rwd.balanceOf(bob), bobEarned);

        // No quedan recompensas reclamables.
        assertEq(farm.earned(alice), 0);
        assertEq(farm.earned(bob), 0);

        // Ambos retiran sus LP restantes.
        vm.prank(alice);
        farm.withdraw(60 ether);

        vm.prank(bob);
        farm.withdraw(300 ether);

        assertEq(farm.balances(alice), 0);
        assertEq(farm.balances(bob), 0);
        assertEq(farm.totalStaked(), 0);

        assertEq(lp.balanceOf(alice), 100 ether);
        assertEq(lp.balanceOf(bob), 300 ether);

        // Los pagos no superan el fondo inicial.
        assertLe(rwd.balanceOf(alice) + rwd.balanceOf(bob), 40 ether);

        // Puede permanecer una pequena cantidad
        // sin distribuir por el redondeo entero.
        assertLe(rwd.balanceOf(address(farm)), 40 ether);
    }

    function testRewardsStayConstantAfterProgramEnds() public {
        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(start + 10 days);

        uint256 earnedAtFinish = farm.earned(alice);

        vm.warp(start + 100 days);

        assertEq(farm.earned(alice), earnedAtFinish);

        // La emision ya ha terminado.
        assertEq(farm.lastTimeRewardApplicable(), farm.periodFinish());
    }
}
