# **Lending pool protocol**

## 📌 Overview

This project consists of a lending pool with staking rewards. It allows you to borrow USDC by posting ETH as collateral. It also allows you to add USDC to the protocol in order to create liquidity in the system and allow
other users to take USDC borrowed. Those who deposit USDC to create liquidity, will receive USDC rewards relative to
their staked amounts. They can also earn rewards in ETH, thanks to the fee charged to borrowers against their ETH collateral.

## 🛠 Tech Stack

- Solidity ^0.8.18
- Foundry
- Forge
- OpenZeppelin

## 📂 Project Structure

**- src/ ->** You can find the LendingPool.sol where all the lending logic is located and also the StakingRewards.sol where the staking and rewards accounting is taking place.

**- test/ ->** Unit, fuzzing and invariant tests from both LendingPool.sol and StakingRewards.sol contracts. Also libraries tests.

## 🎯 Learning Objectives

- Secure programming practices.
- Secure mindset.
- Security concerns.
- Knowledge about Solidity smart contract vulnerabilities (reentrancy, access control...).
- Mixture of scalability and architectural practices, ensuring at the same time security.
- Solidity best practices.
- User roles and privileges.
- Mathematical economics.
- Solidity arithmetic.
- Economic protocols
