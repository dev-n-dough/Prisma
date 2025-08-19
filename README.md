# Prisma

A vault made on hyperliquid, which runs a custom strategy to generate yield for its users

## Technical Components

- Using Boring-Vault architecture by Veda 
- Implements Staking and Unstaking on `stakedhype.fi`
- Interacts with `Felix Vanilla Markets` to supply collateral and borrow Hype.
- Creates a leveraged loop, which generates yield
- User deposits, withdrawals, vault access controls, tvl guard - all are implemented inside the boring vault architechture
- 