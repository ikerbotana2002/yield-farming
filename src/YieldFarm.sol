// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract YieldFarm is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;
    address public immutable owner;

    // Depositos del Dia 41.
    mapping(address => uint256) public balances;
    uint256 public totalStaked;

    // Estado del programa de recompensas.
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    bool public rewardsStarted;

    // Contabilidad individual.
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    error InvalidLPToken();
    error InvalidRewardToken();
    error ZeroAmount();
    error InsufficientBalance();
    error UnsupportedToken();
    error Unauthorized();
    error InvalidRewardSchedule();
    error RewardsAlreadyStarted();
    error NoRewards();
    error NoStake();

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardProgramStarted(uint256 amount, uint256 duration, uint256 rewardRate);
    event RewardClaimed(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount, uint256 forfeitedRewards);

    constructor(address lpToken_, address rewardToken_) {
        if (lpToken_ == address(0) || lpToken_.code.length == 0) {
            revert InvalidLPToken();
        }

        if (rewardToken_ == address(0) || rewardToken_.code.length == 0 || rewardToken_ == lpToken_) {
            revert InvalidRewardToken();
        }

        lpToken = IERC20(lpToken_);
        rewardToken = IERC20(rewardToken_);
        owner = msg.sender;
    }

    // ----------------------------------------------------
    // 1. ULTIMO INSTANTE QUE PUEDE GENERAR RECOMPENSAS
    // ----------------------------------------------------

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    // ----------------------------------------------------
    // 2. RECOMPENSA GLOBAL ACUMULADA POR LP
    // ----------------------------------------------------

    function rewardPerToken() public view returns (uint256) {
        if (!rewardsStarted || totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 applicableTime = lastTimeRewardApplicable();

        if (applicableTime <= lastUpdateTime) {
            return rewardPerTokenStored;
        }

        uint256 elapsed = applicableTime - lastUpdateTime;

        uint256 emitted = elapsed * rewardRate;

        uint256 increment = Math.mulDiv(emitted, PRECISION, totalStaked);

        return rewardPerTokenStored + increment;
    }

    // ----------------------------------------------------
    // 3. RECOMPENSAS PENDIENTES DE UN USUARIO
    // ----------------------------------------------------

    function earned(address user) public view returns (uint256) {
        uint256 deltaRPT = rewardPerToken() - userRewardPerTokenPaid[user];

        uint256 newlyEarned = Math.mulDiv(balances[user], deltaRPT, PRECISION);

        return rewards[user] + newlyEarned;
    }

    // ----------------------------------------------------
    // 4. ACTUALIZAR LA CONTABILIDAD
    // ----------------------------------------------------

    modifier updateReward(address user) {
        rewardPerTokenStored = rewardPerToken();

        if (rewardsStarted) {
            lastUpdateTime = lastTimeRewardApplicable();
        }

        if (user != address(0)) {
            rewards[user] = earned(user);

            userRewardPerTokenPaid[user] = rewardPerTokenStored;
        }

        _;
    }

    // ----------------------------------------------------
    // 5. FINANCIAR E INICIAR LAS RECOMPENSAS
    // ----------------------------------------------------

    function startRewards(uint256 amount, uint256 duration) external nonReentrant {
        if (msg.sender != owner) {
            revert Unauthorized();
        }

        // En este Dia 42 solo admitimos
        // un programa de recompensas.
        if (rewardsStarted) {
            revert RewardsAlreadyStarted();
        }

        if (amount == 0 || duration == 0 || amount / duration == 0) {
            revert InvalidRewardSchedule();
        }

        uint256 beforeBalance = rewardToken.balanceOf(address(this));

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 afterBalance = rewardToken.balanceOf(address(this));

        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) {
            revert UnsupportedToken();
        }

        // Se paga desde un fondo recibido previamente.
        // La division entera puede dejar un resto.
        rewardRate = amount / duration;
        periodFinish = block.timestamp + duration;
        lastUpdateTime = block.timestamp;
        rewardsStarted = true;

        emit RewardProgramStarted(amount, duration, rewardRate);
    }

    // ----------------------------------------------------
    // 6. DEPOSITAR LP TOKENS
    // ----------------------------------------------------

    function deposit(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 balanceBefore = lpToken.balanceOf(address(this));

        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 balanceAfter = lpToken.balanceOf(address(this));

        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != amount) {
            revert UnsupportedToken();
        }

        balances[msg.sender] += amount;
        totalStaked += amount;

        emit Deposited(msg.sender, amount);
    }

    // ----------------------------------------------------
    // 7. RETIRAR LP TOKENS
    // ----------------------------------------------------

    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (balances[msg.sender] < amount) {
            revert InsufficientBalance();
        }

        balances[msg.sender] -= amount;
        totalStaked -= amount;

        uint256 balanceBefore = lpToken.balanceOf(address(this));

        lpToken.safeTransfer(msg.sender, amount);

        uint256 balanceAfter = lpToken.balanceOf(address(this));

        if (balanceAfter > balanceBefore || balanceBefore - balanceAfter != amount) {
            revert UnsupportedToken();
        }

        emit Withdrawn(msg.sender, amount);
    }

    function emergencyWithdraw() external nonReentrant updateReward(msg.sender) {
        uint256 amount = balances[msg.sender];

        if (amount == 0) {
            revert NoStake();
        }

        // Calcular las recompensas acumuladas antes
        // de eliminar la participacion del usuario.
        uint256 forfeitedRewards = rewards[msg.sender];

        // El usuario deja de participar en el farming.
        balances[msg.sender] = 0;
        totalStaked -= amount;

        // Renuncia a las recompensas pendientes.
        rewards[msg.sender] = 0;

        // Registrar saldo del contrato antes de retirar.
        uint256 balanceBefore = lpToken.balanceOf(address(this));

        // Devolver todos los LP tokens.
        lpToken.safeTransfer(msg.sender, amount);

        uint256 balanceAfter = lpToken.balanceOf(address(this));

        // Verificar que han salido exactamente los LP.
        if (balanceAfter > balanceBefore || balanceBefore - balanceAfter != amount) {
            revert UnsupportedToken();
        }

        emit EmergencyWithdrawn(msg.sender, amount, forfeitedRewards);
    }

    // ----------------------------------------------------
    // 8. RECLAMAR RECOMPENSAS
    // ----------------------------------------------------

    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 amount = rewards[msg.sender];

        if (amount == 0) {
            revert NoRewards();
        }

        // Actualizamos antes de transferir.
        rewards[msg.sender] = 0;

        rewardToken.safeTransfer(msg.sender, amount);

        emit RewardClaimed(msg.sender, amount);
    }

    // ----------------------------------------------------
    // 9. CONSULTAS
    // ----------------------------------------------------

    function stakedBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}
