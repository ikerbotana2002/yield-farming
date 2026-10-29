
# Yield Farming Protocol

An educational DeFi yield farming protocol built with
**Solidity, Foundry and OpenZeppelin Contracts**.

Users deposit ERC-20 liquidity provider (LP) tokens and
earn rewards in a separate ERC-20 token (RWD).

The implementation uses a global reward-per-token
accumulator to distribute rewards according to stake
size and participation time, without looping through
all depositors.

> Educational prototype. Not audited or production-ready.

## Features

- ERC-20 LP token staking
- Multi-user deposits and withdrawals
- Pre-funded reward distribution
- Time-based reward emission
- Reward-per-token accounting
- Reward claims without withdrawing LP tokens
- Emergency withdrawal with reward forfeiture
- Custom errors and events
- SafeERC20 and ReentrancyGuard
- Unit tests, fuzz tests and adversarial security tests

## Architecture

```text
        Liquidity Provider
                |
          deposits LP
                |
                v
           YieldFarm
           /       \
          /         \
    LP Token      RWD Token
    (staked)      (rewards)
          \         /
           \       /
       User accounting
       rewardPerToken
       earned(user)
       claimRewards()
```

## Main Contracts

| Contract | Responsibility |
|---|---|
| `src/YieldFarm.sol` | LP deposits, withdrawals and rewards |
| `src/MockLPToken.sol` | Mock ERC-20 LP token for testing |
| `src/MockRewardToken.sol` | Mock ERC-20 reward token |

The farming protocol does not create LP tokens.
It receives an existing ERC-20 token address.

## Reward Model

The owner funds a single reward distribution program
by transferring RWD into the farming contract.

The reward rate is calculated as:

```text
rewardRate = rewardAmount / duration
```

Reward distribution uses an accumulated value per
staked LP token:

```text
rewardPerToken +=
    elapsedTime * rewardRate * 1e18 / totalStaked
```

The reward earned by each user is calculated using:

```text
earned(user) =
    balances[user]
    * (rewardPerToken - userRewardPerTokenPaid[user])
    / 1e18
    + rewards[user]
```

When a user deposits or withdraws LP tokens, their
reward accounting is updated before modifying
their stake.

This prevents late depositors from receiving rewards
generated before they joined.

The calculations use integer arithmetic. Very small
rounding differences can occur.

## Example

A program distributes 40 RWD over 10 days.

- Alice deposits 100 LP on day 0.
- Bob deposits 300 LP on day 5.
- Both remain until day 10.

Expected rewards, ignoring rounding:

| User | Rewards |
|---|---:|
| Alice | 25 RWD |
| Bob | 15 RWD |

Alice receives all rewards generated before Bob
joined, plus her proportional share afterward.

## Installation

Requirements:

- Git
- Foundry

Clone including submodules:

```bash
git clone --recurse-submodules \
  https://github.com/ikerbotana2002/yield-farming.git

cd yield-farming
```

Build:

```bash
forge build
```

Run all tests:

```bash
forge test -vv
```

Run extended fuzz tests:

```bash
forge test \
  --match-contract YieldFuzzTest \
  --fuzz-runs 1000 \
  -vv
```

Check formatting:

```bash
forge fmt --check
```

Check contract size:

```bash
forge build --sizes
```

## Testing

The project includes:

- Reward distribution mathematics
- Deposits and withdrawals
- Multi-user accounting
- Late depositor scenarios
- Claiming and reward preservation
- Emergency withdrawals
- Fee-on-transfer token rejection
- Reentrancy attempt simulations
- Fuzz testing of valid operations
- Multi-step integration scenarios

See the GitHub Actions workflow for automated checks.

## Security Considerations

This protocol is intended for learning and portfolio
demonstration. It has not been independently audited.

Known limitations:

1. **One reward program:** Only one pre-funded reward
   schedule is supported. Reward top-ups and extensions
   are not implemented.

2. **Unused rewards:** Rewards emitted while no LP
   tokens are deposited are not assigned to users.
   Forfeited rewards from emergency withdrawals also
   remain in the contract.

3. **No surplus recovery:** There is no implemented
   procedure for withdrawing unused reward tokens.
   A recovery function would require strict accounting
   to protect outstanding user claims.

4. **Token compatibility:** Standard ERC-20 behavior is
   assumed. Rebasing and arbitrary malicious token
   behavior are not fully supported.

5. **Rounding:** Integer division can leave small
   residual balances. The implementation does not
   eliminate all precision limitations.

6. **Administrator trust:** The deploying address
   controls initiation of the reward program.

7. **Emergency withdrawals:** Emergency withdrawals
   return staked LP tokens and forfeit pending rewards.
   This path still depends on reward accounting and
   the LP token's transfer behavior.

8. **Underlying AMM risk:** Staked LP tokens remain
   exposed to the economics and vulnerabilities of
   the liquidity pool that issued them.

9. **No audit:** Passing automated tests does not
   guarantee economic or smart-contract security.

Do not use this code to custody real funds.

## Technologies

- Solidity 0.8.24
- Foundry / Forge
- OpenZeppelin Contracts 5.x
- ERC-20
- GitHub Actions

## Resumen en español

Protocolo educativo de Yield Farming donde los usuarios
depositan LP tokens y acumulan recompensas RWD según
el importe depositado y el tiempo de participación.

Implementa depósitos, retiradas, distribución de
recompensas mediante `rewardPerToken`, reclamaciones
y retiradas de emergencia.

Incluye pruebas funcionales, fuzz testing, simulaciones
de tokens con comisiones y pruebas de reentrancy.

**No está auditado ni preparado para fondos reales.**
