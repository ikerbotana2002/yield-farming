// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

contract ReentrantLPToken is ERC20 {
    YieldFarm public farm;

    bool public attackEnabled;
    bool public attackAttempted;
    bool public attackSucceeded;

    constructor() ERC20("Attack LP", "ALP") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function configureFarm(address farm_) external {
        farm = YieldFarm(farm_);
    }

    // El propio token se convierte en un staker legitimo.
    // Asi puede intentar retirar su participacion
    // durante la operacion de otro usuario.
    function seedStake() external {
        _mint(address(this), 1 ether);
        _approve(address(this), address(farm), 1 ether);

        farm.deposit(1 ether);
    }

    function enableAttack() external {
        attackEnabled = true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        if (attackEnabled && to == address(farm) && from != address(0)) {
            attackEnabled = false;
            attackAttempted = true;

            // El token malicioso tiene 1 LP depositado.
            // Intenta retirarlo mientras se ejecuta
            // el deposito de Alicia.
            (bool success,) = address(farm).call(abi.encodeCall(YieldFarm.withdraw, (1 ether)));

            attackSucceeded = success;
        }
    }
}

contract YieldReentrancyTest is Test {
    ReentrantLPToken lp;
    MockRewardToken reward;
    YieldFarm farm;

    address alice = address(0xA1);

    function setUp() public {
        lp = new ReentrantLPToken();
        reward = new MockRewardToken();

        farm = new YieldFarm(address(lp), address(reward));

        lp.configureFarm(address(farm));

        // El token malicioso ya tiene 1 LP depositado.
        lp.seedStake();

        assertEq(farm.balances(address(lp)), 1 ether);

        lp.transfer(alice, 100 ether);

        vm.prank(alice);
        lp.approve(address(farm), 100 ether);
    }

    function testReentrancyDuringDepositIsBlocked() public {
        lp.enableAttack();

        vm.prank(alice);
        farm.deposit(100 ether);

        // Se produjo el intento.
        assertTrue(lp.attackAttempted());

        // La llamada reentrante no tuvo exito.
        assertFalse(lp.attackSucceeded());

        // Alicia completo su deposito.
        assertEq(farm.balances(alice), 100 ether);

        // El atacante no pudo retirar su LP.
        assertEq(farm.balances(address(lp)), 1 ether);

        assertEq(farm.totalStaked(), 101 ether);

        assertEq(lp.balanceOf(address(farm)), 101 ether);
    }
}
