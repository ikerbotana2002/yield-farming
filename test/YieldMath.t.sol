// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract YieldMathTest is Test {
    // Escalamos los decimales para evitar usar
    // números de coma flotante en Solidity.
    uint256 constant PRECISION = 1e18;

    uint256 constant DAILY_REWARDS = 4 ether;

    // -------------------------------------------------
    // CALCULAR RECOMPENSA POR LP TOKEN
    // -------------------------------------------------

    function rewardPerTokenIncrement(uint256 emitted, uint256 totalStaked) internal pure returns (uint256) {
        require(totalStaked > 0, "No LP staked");

        return emitted * PRECISION / totalStaked;
    }

    // -------------------------------------------------
    // TEST 1: DOS USUARIOS CON LA MISMA PARTICIPACION
    // -------------------------------------------------

    function testEqualStakeEqualRewards() public pure {
        uint256 aliceStake = 100 ether;
        uint256 bobStake = 100 ether;

        uint256 total = aliceStake + bobStake;

        uint256 rpt = rewardPerTokenIncrement(DAILY_REWARDS, total);

        uint256 aliceReward = aliceStake * rpt / PRECISION;

        uint256 bobReward = bobStake * rpt / PRECISION;

        assertEq(aliceReward, 2 ether);
        assertEq(bobReward, 2 ether);
    }

    // -------------------------------------------------
    // TEST 2: PARTICIPACIONES 25 % / 75 %
    // -------------------------------------------------

    function testProportionalRewards() public pure {
        uint256 aliceStake = 100 ether;
        uint256 bobStake = 300 ether;

        uint256 rpt = rewardPerTokenIncrement(DAILY_REWARDS, aliceStake + bobStake);

        uint256 aliceReward = aliceStake * rpt / PRECISION;

        uint256 bobReward = bobStake * rpt / PRECISION;

        assertEq(aliceReward, 1 ether);
        assertEq(bobReward, 3 ether);

        assertEq(aliceReward + bobReward, DAILY_REWARDS);
    }

    // -------------------------------------------------
    // TEST 3: BOB ENTRA CINCO DIAS DESPUES
    // -------------------------------------------------

    function testLateDepositDoesNotReceivePastRewards() public pure {
        uint256 aliceStake = 100 ether;
        uint256 bobStake = 300 ether;

        // Primeros 5 dias:
        // solo Alicia participa.
        uint256 firstPeriodRewards = DAILY_REWARDS * 5;

        uint256 rptAfterFiveDays = rewardPerTokenIncrement(firstPeriodRewards, aliceStake);

        assertEq(rptAfterFiveDays, 0.2 ether);

        // Bob entra ahora.
        // Guardamos el acumulador en ese instante.
        uint256 bobPaidRPT = rptAfterFiveDays;

        // Dias 5 a 10:
        // ambos participan.
        uint256 secondPeriodRewards = DAILY_REWARDS * 5;

        uint256 rptSecondPeriod = rewardPerTokenIncrement(secondPeriodRewards, aliceStake + bobStake);

        uint256 finalRPT = rptAfterFiveDays + rptSecondPeriod;

        // Alicia estaba desde el principio.
        uint256 aliceRewards = aliceStake * finalRPT / PRECISION;

        // Bob solo acumula desde su entrada.
        uint256 bobRewards = bobStake * (finalRPT - bobPaidRPT) / PRECISION;

        assertEq(aliceRewards, 25 ether);
        assertEq(bobRewards, 15 ether);

        // Nunca repartimos mas de lo emitido.
        assertEq(aliceRewards + bobRewards, 40 ether);
    }

    // -------------------------------------------------
    // TEST 4: LAS RECOMPENSAS PASADAS NO CAMBIAN
    // -------------------------------------------------

    function testNewDepositsDoNotRewritePastRewards() public pure {
        uint256 aliceStake = 100 ether;

        uint256 firstPeriod = 20 ether;

        uint256 rptBeforeBob = rewardPerTokenIncrement(firstPeriod, aliceStake);

        uint256 aliceAccrued = aliceStake * rptBeforeBob / PRECISION;

        assertEq(aliceAccrued, 20 ether);

        // Bob entra despues.
        uint256 bobStake = 300 ether;

        assertEq(aliceAccrued, 20 ether);

        assertEq(rptBeforeBob, rewardPerTokenIncrement(firstPeriod, aliceStake));

        // Ahora el total para la siguiente
        // distribucion sera 400 LP.
        assertEq(aliceStake + bobStake, 400 ether);
    }

    // -------------------------------------------------
    // TEST 5: PRECISION Y REDONDEO ENTERO
    // -------------------------------------------------

    function testRoundingLeavesUndistributedDust() public pure {
        // Un wei de recompensa a repartir
        // entre tres LP tokens completos.
        uint256 emitted = 1;
        uint256 totalStake = 3 ether;

        uint256 rpt = rewardPerTokenIncrement(emitted, totalStake);

        // Este valor es cero por redondeo.
        assertEq(rpt, 0);

        // No podemos distribuir con esta escala
        // una fraccion tan pequena.
        // El wei queda sin contabilizar.
    }

    // -------------------------------------------------
    // TEST 6: SIN DEPOSITOS NO PODEMOS DIVIDIR
    // -------------------------------------------------

    function test_RevertWhen_NoLiquidityStaked() public {
        vm.expectRevert(bytes("No LP staked"));

        this.calculateWithoutLiquidity();
    }

    function calculateWithoutLiquidity() external pure returns (uint256) {
        return rewardPerTokenIncrement(DAILY_REWARDS, 0);
    }

    // -------------------------------------------------
    // TEST 7: APR COMO PORCENTAJE ANUAL
    // -------------------------------------------------

    function testAPRCalculation() public pure {
        // Recompensas: 4 RWD diarios.
        // Precio ficticio: 2 USD por RWD.
        // Valor depositado: 4.000 USD.

        uint256 rewardValuePerDay = 4 * 2;

        uint256 annualRewardValue = rewardValuePerDay * 365;

        // BPS = basis points (puntos basicos).
        // 10.000 BPS equivalen al 100 %.
        uint256 aprBps = annualRewardValue * 10_000 / 4_000;

        // 7.300 BPS equivalen al 73 %.
        assertEq(aprBps, 7_300);
    }
}
