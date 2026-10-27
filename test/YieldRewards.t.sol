// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockLPToken} from "../src/MockLPToken.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

contract YieldRewardsTest is Test {
    MockLPToken lpToken;
    MockRewardToken rewardToken;
    YieldFarm farm;

    address alice = address(0xA1);
    address bob = address(0xB1);

    uint256 constant TOTAL_REWARDS = 40 ether;
    uint256 constant DURATION = 10 days;

    // Tolerancia de redondeo en unidades minimas de RWD.
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

        rewardToken.approve(address(farm), type(uint256).max);
    }

    function startProgram() internal {
        farm.startRewards(TOTAL_REWARDS, DURATION);
    }

    // -------------------------------------------------
    // 1. FINANCIACION REAL
    // -------------------------------------------------

    function testStartRewards() public {
        startProgram();

        assertTrue(farm.rewardsStarted());

        assertEq(rewardToken.balanceOf(address(farm)), TOTAL_REWARDS);

        assertEq(farm.rewardRate(), TOTAL_REWARDS / DURATION);

        assertEq(farm.periodFinish(), block.timestamp + DURATION);
    }

    // -------------------------------------------------
    // 2. SOLO ALICIA DEPOSITA
    // -------------------------------------------------

    function testSingleUserAccruesRewards() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(startTime + 5 days);

        // Alicia estuvo sola durante cinco dias.
        // Debe haber generado aproximadamente 20 RWD.
        assertApproxEqAbs(farm.earned(alice), 20 ether, TOLERANCE);
    }

    // -------------------------------------------------
    // 3. BOB ENTRA CINCO DIAS DESPUES
    // -------------------------------------------------

    function testLateUserDoesNotEarnPastRewards() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        // Transcurren cinco dias.
        vm.warp(startTime + 5 days);

        assertApproxEqAbs(farm.earned(alice), 20 ether, TOLERANCE);

        // Bob deposita 300 LP al entrar.
        vm.prank(bob);
        farm.deposit(300 ether);

        // Bob no tiene recompensas anteriores.
        assertEq(farm.earned(bob), 0);

        // Pasan otros cinco dias.
        vm.warp(startTime + 10 days);

        // Alicia: 20 RWD + 5 RWD.
        assertApproxEqAbs(farm.earned(alice), 25 ether, TOLERANCE);

        // Bob: 15 RWD desde su entrada.
        assertApproxEqAbs(farm.earned(bob), 15 ether, TOLERANCE);
    }

    // -------------------------------------------------
    // 4. RECLAMAR RECOMPENSAS
    // -------------------------------------------------

    function testClaimRewards() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(startTime + 1 days);

        uint256 pending = farm.earned(alice);

        assertGt(pending, 0);

        vm.prank(alice);
        farm.claimRewards();

        assertEq(rewardToken.balanceOf(alice), pending);

        // Acaba de cobrar todo lo acumulado.
        assertEq(farm.earned(alice), 0);

        // Sus LP continuan depositados.
        assertEq(farm.balances(alice), 100 ether);
        assertEq(farm.totalStaked(), 100 ether);
    }

    // -------------------------------------------------
    // 5. RETIRADA CONSERVA RECOMPENSAS ANTERIORES
    // -------------------------------------------------

    function testWithdrawalPreservesAccruedRewards() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(startTime + 5 days);

        // Alicia retira todos sus LP.
        vm.prank(alice);
        farm.withdraw(100 ether);

        assertEq(farm.balances(alice), 0);

        // Aunque ya no tenga LP depositados,
        // conserva sus recompensas anteriores.
        assertApproxEqAbs(farm.earned(alice), 20 ether, TOLERANCE);

        vm.prank(alice);
        farm.claimRewards();

        assertApproxEqAbs(rewardToken.balanceOf(alice), 20 ether, TOLERANCE);
    }

    // -------------------------------------------------
    // 6. NO SE GENERAN NUEVAS RECOMPENSAS
    //    DESPUES DE TERMINAR EL PROGRAMA
    // -------------------------------------------------

    function testRewardsStopAfterPeriodFinish() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(startTime + 10 days);

        uint256 atFinish = farm.earned(alice);

        vm.warp(startTime + 30 days);

        assertEq(farm.earned(alice), atFinish);
    }

    // -------------------------------------------------
    // 7. LOS PERIODOS SIN DEPOSITOS NO SE REGALAN
    // -------------------------------------------------

    function testEmptyPoolDoesNotRewardLateDepositor() public {
        startProgram();

        uint256 startTime = block.timestamp;

        // Dos dias sin ningun deposito.
        vm.warp(startTime + 2 days);

        vm.prank(alice);
        farm.deposit(100 ether);

        assertEq(farm.earned(alice), 0);

        vm.warp(startTime + 3 days);

        // Alicia solo participa durante un dia.
        assertApproxEqAbs(farm.earned(alice), 4 ether, TOLERANCE);
    }

    // -------------------------------------------------
    // 8. UN SEGUNDO CLAIM NO PUEDE COBRAR DOS VECES
    // -------------------------------------------------

    function test_RevertWhen_ClaimingTwice() public {
        startProgram();

        uint256 startTime = block.timestamp;

        vm.prank(alice);
        farm.deposit(100 ether);

        vm.warp(startTime + 1 days);

        vm.prank(alice);
        farm.claimRewards();

        vm.expectRevert(YieldFarm.NoRewards.selector);

        vm.prank(alice);
        farm.claimRewards();
    }

    // -------------------------------------------------
    // 9. BOB NO PUEDE COBRAR SIN HABER DEPOSITADO
    // -------------------------------------------------

    function test_RevertWhen_ClaimingWithoutStake() public {
        startProgram();

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(YieldFarm.NoRewards.selector);

        vm.prank(bob);
        farm.claimRewards();
    }

    // -------------------------------------------------
    // 10. SOLO EL OWNER FINANCIA EL PROGRAMA
    // -------------------------------------------------

    function test_RevertWhen_NonOwnerStartsRewards() public {
        vm.expectRevert(YieldFarm.Unauthorized.selector);

        vm.prank(alice);
        farm.startRewards(TOTAL_REWARDS, DURATION);
    }

    // -------------------------------------------------
    // 11. NO PODEMOS EMPEZAR EL PROGRAMA DOS VECES
    // -------------------------------------------------

    function test_RevertWhen_StartRewardsTwice() public {
        startProgram();

        vm.expectRevert(YieldFarm.RewardsAlreadyStarted.selector);

        farm.startRewards(TOTAL_REWARDS, DURATION);
    }

    // -------------------------------------------------
    // 12. RECHAZAR UNA DURACION INVALIDA
    // -------------------------------------------------

    function test_RevertWhen_DurationIsZero() public {
        vm.expectRevert(YieldFarm.InvalidRewardSchedule.selector);

        farm.startRewards(40 ether, 0);
    }

    // -------------------------------------------------
    // 13. RECHAZAR UNA EMISION DE CERO POR SEGUNDO
    // -------------------------------------------------

    function test_RevertWhen_RewardRateRoundsToZero() public {
        vm.expectRevert(YieldFarm.InvalidRewardSchedule.selector);

        farm.startRewards(1, 10 days);
    }

    // -------------------------------------------------
    // 14. RECHAZAR TOKENS LP Y RWD IDENTICOS
    // -------------------------------------------------

    function test_RevertWhen_RewardTokenEqualsLP() public {
        vm.expectRevert(YieldFarm.InvalidRewardToken.selector);

        new YieldFarm(address(lpToken), address(lpToken));
    }
}
