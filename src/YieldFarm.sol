// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract YieldFarm is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token LP que aceptamos en el farming.
    IERC20 public immutable lpToken;

    // Participacion depositada de cada usuario.
    mapping(address => uint256) public balances;

    // Total de LP tokens depositados.
    uint256 public totalStaked;

    // Errores personalizados.
    error InvalidLPToken();
    error ZeroAmount();
    error InsufficientBalance();
    error UnsupportedToken();

    // Eventos para que las aplicaciones
    // externas puedan seguir las operaciones.
    event Deposited(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount);

    constructor(address lpToken_) {
        // No permitimos direcciones nulas
        // ni direcciones sin codigo.
        if (lpToken_ == address(0) || lpToken_.code.length == 0) {
            revert InvalidLPToken();
        }

        lpToken = IERC20(lpToken_);
    }

    // ---------------------------------------------------
    // DEPOSITAR LP TOKENS
    // ---------------------------------------------------

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 balanceBefore = lpToken.balanceOf(address(this));

        // Pedimos al ERC-20 que mueva los tokens
        // desde la wallet hacia nuestro farming.
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = lpToken.balanceOf(address(this));

        // Comprobamos que realmente han entrado
        // los LP tokens que esperabamos.
        if (balanceAfter < balanceBefore) {
            revert UnsupportedToken();
        }

        if (balanceAfter - balanceBefore != amount) {
            revert UnsupportedToken();
        }

        // Registramos el nuevo deposito.
        balances[msg.sender] += amount;
        totalStaked += amount;

        emit Deposited(msg.sender, amount);
    }

    // ---------------------------------------------------
    // RETIRAR LP TOKENS
    // ---------------------------------------------------

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Cada usuario solo puede retirar
        // su propia participacion.
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance();
        }

        // Actualizar estado ANTES de transferir:
        // Checks-Effects-Interactions.
        balances[msg.sender] -= amount;
        totalStaked -= amount;

        uint256 balanceBefore = lpToken.balanceOf(address(this));

        // Devolver LP tokens al usuario.
        lpToken.safeTransfer(msg.sender, amount);

        uint256 balanceAfter = lpToken.balanceOf(address(this));

        // Debe salir exactamente la cantidad pedida.
        if (balanceAfter > balanceBefore) {
            revert UnsupportedToken();
        }

        if (balanceBefore - balanceAfter != amount) {
            revert UnsupportedToken();
        }

        emit Withdrawn(msg.sender, amount);
    }

    // ---------------------------------------------------
    // CONSULTAR DEPOSITO DE UNA DIRECCION
    // ---------------------------------------------------

    function stakedBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}
