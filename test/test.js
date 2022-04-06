const NFTContract = artifacts.require("NFT");
const RewardTokenContract = artifacts.require("RewardToken");
const StakingContract = artifacts.require("NFTStaking");

contract("Staking of one nft", async (accounts) => {
  it("Should stake an nft", async function () {
    const StakingObject = await StakingContract.deployed();

    await StakingObject.stake(1);
    await StakingObject.stake(2);
    await StakingObject.stake(3);
    
    // get Staked information
    const staked_info = await StakingObject.getActivityLogs(accounts[0]);
    const depositIds = staked_info[0];

    const array_len = depositIds.length;
    for(let i = 0; i < array_len; i ++ ){
      console.log('\n--------------------', i, '-----------------------\n');
      console.log('depositId------------>', staked_info[0][i].toString());
      console.log('Owner------------>', staked_info[1][i].toString());
      console.log('TokenId------------>', staked_info[2][i].toString());
      console.log('isWithdrawn------------>', staked_info[3][i].toString());
      console.log('depositTime------------>', staked_info[4][i].toString());      
      console.log('timeLockInSeconds------------>', staked_info[5][i].toString());
    }

    console.log('\n--------------------Display Reward Earned Amount and Released Amount-----------------------\n');

    const getRewardsAmount = await StakingObject.getRewardsAmount(staked_info[0][0].toString());
    console.log('reward Earned Amount-------------->', getRewardsAmount[0].toString());
    console.log('reward Released Amount-------------->', getRewardsAmount[1].toString());
  });
});