const NFT = artifacts.require("NFT");
const RewardToken = artifacts.require("RewardToken");
const NFTStaking = artifacts.require("NFTStaking");

module.exports = async function (deployer) {

  console.log("================> Deploying smart contracts started");
  await deployer.deploy(NFT);
  const NFT_ADDRESS = await NFT.deployed();

  await deployer.deploy(RewardToken);
  const RewardToken_ADDRESS = await RewardToken.deployed();

  await deployer.deploy(NFTStaking, NFT_ADDRESS.address, RewardToken_ADDRESS.address);  
  const Staking_ADDRESS = await NFTStaking.deployed();
  
  console.log("Deployed NFT addresss:", NFT.address);
  console.log("Deployed RewardToken addresss:", RewardToken_ADDRESS.address);
  console.log("Deployed Staking addresss:", Staking_ADDRESS.address);
  console.log("================> Deploying smart contracts is finished");
};
