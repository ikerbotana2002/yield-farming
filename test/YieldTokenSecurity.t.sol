// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MockLPToken} from "../src/MockLPToken.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {YieldFarm} from "../src/YieldFarm.sol";

// Token de prueba que descuenta un 1%
// cuando se transfiere al destinatario configurado.
contract FeeToken is ERC20 {
    address public feeTarget;
    bool public feeEnabled;

    constructor() ERC20("Fee Token", "FEE") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function configureFee(address target, bool enabled) external {
        feeTarget = target;
        feeEnabled = enabled;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (feeEnabled && to == feeTarget && from != address(0)) {
            uint256 fee = amount / 100;

            // El destinatario recibe el 99%.
            super._update(from, to, amount - fee);

            // Quemamos el 1% restante.
            super._update(from, address(0), fee);
        } else {
            super._update(from, to, amount);
        }
    }
}

contract YieldTokenSecurityTest is Test {
    address alice = address(0xA1);

    function test_RevertWhen_LPChargesTransferFee() public {
        FeeToken feeLP = new FeeToken();
        MockRewardToken reward = new MockRewardToken();

        YieldFarm farm = new YieldFarm(address(feeLP), address(reward));

        feeLP.transfer(alice, 100 ether);

        vm.prank(alice);
        feeLP.approve(address(farm), 100 ether);

        feeLP.configureFee(address(farm), true);

        vm.prank(alice);
        vm.expectRevert(YieldFarm.UnsupportedToken.selector);
        farm.deposit(100 ether);

        // El revert deshace tambien la transferencia.
        assertEq(feeLP.balanceOf(alice), 100 ether);
        assertEq(feeLP.balanceOf(address(farm)), 0);
        assertEq(farm.totalStaked(), 0);
    }

    function test_RevertWhen_RewardTokenChargesFee() public {
        MockLPToken lp = new MockLPToken();
        FeeToken feeReward = new FeeToken();

        YieldFarm farm = new YieldFarm(address(lp), address(feeReward));

        feeReward.approve(address(farm), 40 ether);
        feeReward.configureFee(address(farm), true);

        vm.expectRevert(YieldFarm.UnsupportedToken.selector);
        farm.startRewards(40 ether, 10 days);

        assertFalse(farm.rewardsStarted());
        assertEq(feeReward.balanceOf(address(farm)), 0);
    }
}
