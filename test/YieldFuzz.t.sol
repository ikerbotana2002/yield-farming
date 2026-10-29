// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockLPToken} from "../src/MockLPToken.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

contract YieldFuzzTest is Test {
    MockLPToken lp;
    MockRewardToken rwd;
    YieldFarm farm;

    address alice = address(0xA1);
    address bob = address(0xB1);

    uint256 constant REWARD_AMOUNT = 40 ether;
    uint256 constant DURATION = 10 days;
    uint256 constant TOLERANCE = 1_000_000;

    function setUp() public {
        lp = new MockLPToken();
        rwd = new MockRewardToken();

        farm = new YieldFarm(address(lp), address(rwd));

        lp.transfer(alice, 500 ether);
        lp.transfer(bob, 500 ether);

        vm.prank(alice);
        lp.approve(address(farm), type(uint256).max);

        vm.prank(bob);
        lp.approve(address(farm), type(uint256).max);

        rwd.approve(address(farm), REWARD_AMOUNT);

        farm.startRewards(REWARD_AMOUNT, DURATION);
    }

    // --------------------------------------------------
    // 1. DEPOSITAR Y RETIRAR CANTIDADES VARIABLES
    // --------------------------------------------------

    function testFuzzPartialWithdrawal(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 300 ether);

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.prank(alice);
        farm.deposit(depositAmount);

        vm.prank(alice);
        farm.withdraw(withdrawAmount);

        uint256 remaining = depositAmount - withdrawAmount;

        assertEq(farm.balances(alice), remaining);

        assertEq(farm.totalStaked(), remaining);

        assertEq(lp.balanceOf(address(farm)), remaining);

        assertEq(lp.balanceOf(alice), 500 ether - remaining);
    }

    // --------------------------------------------------
    // 2. REPARTO ENTRE DOS USUARIOS
    // --------------------------------------------------

    function testFuzzTwoUsersRewards(uint256 aliceAmount, uint256 bobAmount) public {
        aliceAmount = bound(aliceAmount, 1 ether, 300 ether);

        bobAmount = bound(bobAmount, 1 ether, 300 ether);

        vm.prank(alice);
        farm.deposit(aliceAmount);

        vm.prank(bob);
        farm.deposit(bobAmount);

        uint256 start = block.timestamp;

        vm.warp(start + 2 days);

        uint256 aliceEarned = farm.earned(alice);
        uint256 bobEarned = farm.earned(bob);

        // Han transcurrido dos dias.
        // Se han generado unos 8 RWD.
        assertApproxEqAbs(aliceEarned + bobEarned, 8 ether, TOLERANCE);

        // Los depositos no han cambiado.
        assertEq(farm.totalStaked(), aliceAmount + bobAmount);

        // Ambos pueden reclamar lo acumulado.
        vm.prank(alice);
        farm.claimRewards();

        vm.prank(bob);
        farm.claimRewards();

        assertEq(rwd.balanceOf(alice), aliceEarned);

        assertEq(rwd.balanceOf(bob), bobEarned);

        // No se ha pagado mas de lo financiado.
        assertLe(rwd.balanceOf(alice) + rwd.balanceOf(bob), REWARD_AMOUNT);
    }

    // --------------------------------------------------
    // 3. UN USUARIO ENTRA MAS TARDE
    // --------------------------------------------------

    function testFuzzLateDepositor(uint256 aliceAmount, uint256 bobAmount) public {
        aliceAmount = bound(aliceAmount, 1 ether, 250 ether);

        bobAmount = bound(bobAmount, 1 ether, 250 ether);

        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.deposit(aliceAmount);

        // Alicia participa sola durante cinco dias.
        vm.warp(start + 5 days);

        uint256 aliceFirstPeriod = farm.earned(alice);

        assertApproxEqAbs(aliceFirstPeriod, 20 ether, TOLERANCE);

        // Bob entra ahora.
        vm.prank(bob);
        farm.deposit(bobAmount);

        // Bob no puede cobrar recompensas anteriores.
        assertEq(farm.earned(bob), 0);

        vm.warp(start + 10 days);

        uint256 aliceFinal = farm.earned(alice);

        uint256 bobFinal = farm.earned(bob);

        assertGe(aliceFinal, aliceFirstPeriod);

        assertApproxEqAbs(aliceFinal + bobFinal, REWARD_AMOUNT, TOLERANCE);
    }

    // --------------------------------------------------
    // 4. RETIRAR Y VOLVER A DEPOSITAR
    // --------------------------------------------------

    function testFuzzWithdrawAndRedeposit(uint256 amount) public {
        amount = bound(amount, 1 ether, 300 ether);

        uint256 start = block.timestamp;

        vm.prank(alice);
        farm.deposit(amount);

        vm.warp(start + 2 days);

        // Alicia retira todo sin reclamar.
        vm.prank(alice);
        farm.withdraw(amount);

        uint256 previousRewards = farm.earned(alice);

        assertApproxEqAbs(previousRewards, 8 ether, TOLERANCE);

        // Un dia sin LP depositados.
        vm.warp(start + 3 days);

        // Alicia vuelve a entrar.
        vm.prank(alice);
        farm.deposit(amount);

        // No obtiene recompensas por el dia vacio.
        assertApproxEqAbs(farm.earned(alice), previousRewards, TOLERANCE);

        vm.warp(start + 4 days);

        // Dos dias antes + uno despues:
        // aproximadamente 12 RWD.
        assertApproxEqAbs(farm.earned(alice), 12 ether, TOLERANCE);

        vm.prank(alice);
        farm.claimRewards();

        assertApproxEqAbs(rwd.balanceOf(alice), 12 ether, TOLERANCE);
    }

    // --------------------------------------------------
    // 5. RETIRADA DE EMERGENCIA CON DOS USUARIOS
    // --------------------------------------------------

    function testFuzzEmergencyWithdrawal(uint256 aliceAmount, uint256 bobAmount) public {
        aliceAmount = bound(aliceAmount, 1 ether, 300 ether);

        bobAmount = bound(bobAmount, 1 ether, 300 ether);

        vm.prank(alice);
        farm.deposit(aliceAmount);

        vm.prank(bob);
        farm.deposit(bobAmount);

        vm.warp(block.timestamp + 3 days);

        uint256 bobBefore = farm.earned(bob);

        vm.prank(alice);
        farm.emergencyWithdraw();

        // Alicia recupera sus LP y pierde los RWD.
        assertEq(farm.balances(alice), 0);
        assertEq(farm.earned(alice), 0);
        assertEq(lp.balanceOf(alice), 500 ether);

        // Bob conserva sus LP y recompensas.
        assertEq(farm.balances(bob), bobAmount);
        assertEq(farm.totalStaked(), bobAmount);

        assertApproxEqAbs(farm.earned(bob), bobBefore, TOLERANCE);

        assertEq(lp.balanceOf(address(farm)), bobAmount);
    }
}
