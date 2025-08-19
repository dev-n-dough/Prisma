# Prisma Vault

A sophisticated yield-generating vault built on Hyperliquid that implements automated leverage strategies to maximize returns for users through a proven Boring-Vault architecture.

## 🌟 Overview

Prisma is an automated vault system that creates leveraged yield opportunities by:
- Implementing staking mechanisms through stakedhype.fi
- Utilizing Felix Vanilla Markets for collateral management and borrowing
- Creating leveraged loops that amplify yield generation
- Providing secure deposit/withdrawal functionality with shares-based tracking mechanism and access controls

## ⚡ Key Features

### Core Functionality
- **Automated Yield Generation**: Custom strategies that maximize returns through leveraged positions
- **Staking Integration**: Seamless interaction with stakedhype.fi for additional yield opportunities
- **Leveraged Loops**: Sophisticated borrowing and lending cycles using Felix Vanilla Markets
- **TVL Protection**: Built-in total value locked guards to maintain vault stability

### User Experience
- **Simple Deposits/Withdrawals**: Easy-to-use interfaces for fund management
- **Access Controls**: Comprehensive permission system for secure operations
- **Transparent Operations**: Clear visibility into vault performance and strategy execution

## 🔧 Technical Implementation

### Smart Contract Components
- **Vault Controller**: Core contract managing user funds and strategy execution
- **Strategy Manager**: Handles automated leveraged loop creation and management
- **Access Control**: Role-based permissions for administrative functions

### External Integrations
- **[stakedhype.fi](https://stakedhype.fi)**: Primary staking platform integration
- **Felix Vanilla Markets**: Collateral supply and HYPE borrowing operations
- **Hyperliquid Protocol**: Underlying blockchain infrastructure

## 📊 Strategy Details

### Leveraged Loop Mechanism
1. **Initial Deposit**: User deposits native hype
2. **Staking** : Stake it to get stHype, which will next be supplied as collateral
3. **Collateral Supply**: Funds supplied to Felix Vanilla Markets
4. **Borrowing**: HYPE tokens borrowed against collateral
5. **Re-staking**: Borrowed assets re-deployed for additional yield 
6. **Loop Amplification**: Process repeats to maximize leverage efficiency


## Testing
1. Created mocks for all necessary contracts
2. Tested those mocks to ensure reliabilty
3. Tested boring-vault's individual components using unit testing
4. Mock tested all the external interactions
5. Mock tested the looping strategy
6. Mock tested user flows of deposit and withdraw
7. Fork testing(WIP)

**⭐ Star this repository if Prisma Vault helps you maximize your DeFi yields!**