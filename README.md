# nft-staking-pool-contract
This is nft staking pool smart contract

### Requirement
Staking contract for an existing ERC1155 NFT project.
The NFT contract for the project is on testnet here: https://mumbai.polygonscan.com/address/0x1a3d0451f48ebef398dd4c134ae60846274b7ce0#code
Staking contract:
- owners deposit their NFT's, 
- and have a total reward per block of the ERC20 reward token split between the depositors based on their stake weight vs total stake weight for all deposited tokens.
- admin functions to set total reward, minimum stake time, reclaim stuck tokens and pause/unpause the contract.
- admin funtion to allow/disallow each tokenID, and set their stake weight as a number from 000 to 999.
- public functions for stake, unstake, check stake, check reward balance and withdraw rewards.
TokenId 1 in the NFT contract is a free mint, and the staking of this should be limited in amount to only 1 per address, while the other tokenIds have no limit.
Reward token Contract:
- is a basic ERC20 with burn/mint functions.
- A requirement for the reward token is the stake contract can mint, and our future game contract can burn
and since people will deposit coins to game contract I think this has it all

