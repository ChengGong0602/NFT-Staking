// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IRewardsToken.sol";
contract NftStaker is Ownable{
    using SafeMath for uint256;
    IERC1155 private nft;
    IRewardsToken private rewardsToken;
    bool public canStake = false;
    //allow/disallow staking for tokenID
    mapping (uint256 => bool) public canDeposit;

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }


    uint256 public stakedTotal;    
    uint256 public rewardsTokenAmount = 10 ether;

    // stake weight for tokenId
    // rewardsTokenAmount * stakeWeight / stakedTotal
    mapping (uint256 => uint256) public stakeWeight; // tokenId => weight, weight is in wei

    // stakingTime for tokenId
    mapping (uint256 => uint256) public stakingTime; // tokenId => time, time is in seconds
    

    struct NFTDeposit {
        uint256 id; // array index
        address depositOwner; // deposited user address - nft owner address
        uint256 tokenId; // deposited nft token id
        uint256 amount; // deposited nft amount
        bool isWithdrawn; // status if this value is true, in this case user can't withdraw, and false, user can withdraw
        uint256 depositTime; // deposit time(block.time current)
        uint256 timeLockInSeconds; 
        uint256 rewardsEarned; // all earned rewards amount via staking
        uint256 rewardsReleased; // released earned rewards amount
    }

    NFTDeposit[] public nftDeposits;

    event NFTDepositLog(
        uint256 depositId,
        address depositOwner,
        uint256 tokenId,
        uint256 amount,
        bool isWithdrawn,
        uint256 depositTime,
        uint256 timeLockInSeconds,
        uint256 rewardsEarned,
        uint256 rewardsReleased
    );

    event NFTWithdrawLog(
        uint256 depositId,
        address depositOwner,
        uint256 tokenId,
        uint256 amount,
        uint256 withdrawTime,
        bool forceWithdraw,
        uint256 rewardsEarned,
        uint256 rewardsReleased
    );

    event RewardsWithdrawLog(
        uint256 depositId,
        address depositOwner,
        uint256 tokenId,
        uint256 amount,
        uint256 withdrawTime,
        uint256 rewardsEarned,
        uint256 rewardsReleased
    );
    

    constructor(IERC1155 _nft, IRewardsToken _rewardsToken) {        
        nft = _nft;
        rewardsToken = _rewardsToken;
        canStake = true;
    }

    function pause() external onlyOwner{
        canStake = false;
    }

    function unpause() external onlyOwner{
        canStake = true;
    }

    function setCanDeposit(uint256 tokenId, bool value) external onlyOwner {
        canDeposit[tokenId] = value;
    }

    function setStakingTime(uint256 tokenId, uint256 _stakingTime) external onlyOwner{
        stakingTime[tokenId] = _stakingTime;
    }

    function setRewardsTokenAmount(uint256 _newRewardsTokenAmount) external onlyOwner {
        rewardsTokenAmount = _newRewardsTokenAmount;
    }

    function setStakeWeight(uint256 _tokenId, uint256 _weight) external onlyOwner {
        stakeWeight[_tokenId] = _weight;
    }

    function stake(uint256 tokenId, uint256 amount) public {        
        _stake(tokenId, amount);
    }

    function stakeBatch(uint256[] memory tokenIds, uint256[] memory amounts) public {
        for (uint256 i = 0; i < tokenIds.length; i++) {            
            _stake(tokenIds[i], amounts[i]);
        }
    }

    function _stake(uint256 _tokenId,uint256 _amount) internal {
        require(canStake = true, "Staking is temporarily disabled");   
        require(canDeposit[_tokenId], "You can't stake for this tokenId");     
        require(nft.balanceOf(msg.sender, _tokenId) != 0, "User must be the owner of the staked nft");
        if (_tokenId == 1)
        {
            require(_amount == 1, 'You can only stake one FREE NFT');
            // check if tokenID 1 is already staked before.
            for (uint256 i = 0; i < nftDeposits.length; i++)
            {
                if (nftDeposits[i].depositOwner == msg.sender && nftDeposits[i].tokenId == _tokenId)
                {
                    require(nftDeposits[i].isWithdrawn == true, 'Please unstake first');
                }
            }            
        }   

        uint256 newItemId = nftDeposits.length;
        nftDeposits.push(
            NFTDeposit(
                newItemId,
                msg.sender,
                _tokenId,
                _amount,
                false,
                block.timestamp,
                stakingTime[_tokenId],
                0,
                0
            )
        );

        nft.safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");

        stakedTotal = stakedTotal + _amount;

        emit NFTDepositLog(
            newItemId,
            msg.sender,
            _tokenId,
            _amount,
            false,
            block.timestamp,
            stakingTime[_tokenId],
            0,
            0
        );
    }    

    function _restake(uint256 depositId) internal {

        require(depositId <= nftDeposits.length);
        require(nftDeposits[depositId].depositOwner == msg.sender, "You can only withdraw your own deposits.");
        require((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds, "You can't yet unlock this deposit.  please use emergencyUnstake instead");
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for your deposit. Please contact support team.");  
        nftDeposits[depositId].depositTime = block.timestamp;        
        nftDeposits[depositId].rewardsEarned += rewardsTokenAmount*stakeWeight[nftDeposits[depositId].tokenId]/stakedTotal;

        emit NFTDepositLog(
            depositId,
            msg.sender,
            nftDeposits[depositId].tokenId,
            nftDeposits[depositId].amount,
            false,
            block.timestamp,
            stakingTime[nftDeposits[depositId].tokenId],
            nftDeposits[depositId].rewardsEarned,
            nftDeposits[depositId].rewardsReleased
        );
    }

    // Unstake without caring about rewards. EMERGENCY ONLY.
    function emergencyUnstake(uint256 depositId) public {      

        require(depositId <= nftDeposits.length);

        require(nftDeposits[depositId].depositOwner == msg.sender, "Only the sender can withdraw this deposit");

        require(nftDeposits[depositId].isWithdrawn == false, "This deposit has already been withdrawn.");

        // nft.safeTransferFrom(address(this), msg.sender, nftDeposits[depositId].tokenId);

        stakedTotal = stakedTotal - nftDeposits[depositId].amount;

        nftDeposits[depositId].isWithdrawn = true;

        emit NFTWithdrawLog(
            depositId,
            msg.sender,
            nftDeposits[depositId].tokenId,
            nftDeposits[depositId].amount,
            block.timestamp,
            true,
            nftDeposits[depositId].rewardsEarned,
            nftDeposits[depositId].rewardsReleased
        );
    }

    function unstake(uint256 depositId) public {

        require(depositId <= nftDeposits.length, "Deposit id is not valid");
        require(nftDeposits[depositId].isWithdrawn == false, "This deposit has already been withdrawn.");
        require(nftDeposits[depositId].depositOwner == msg.sender, "You can only withdraw your own deposits.");
        require((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds, "You can't yet unlock this deposit.  please use emergencyUnstake instead");
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for your deposit. Please contact support team.");
        nft.safeTransferFrom(address(this), msg.sender, nftDeposits[depositId].tokenId, nftDeposits[depositId].amount, "");        
        stakedTotal -nftDeposits[depositId].amount;
        nftDeposits[depositId].isWithdrawn = true;
        nftDeposits[depositId].rewardsEarned += rewardsTokenAmount*stakeWeight[nftDeposits[depositId].tokenId]/stakedTotal;

        emit NFTWithdrawLog(
            depositId,
            msg.sender,
            nftDeposits[depositId].tokenId,
            nftDeposits[depositId].amount,
            block.timestamp,
            false,
            nftDeposits[depositId].rewardsEarned,
            nftDeposits[depositId].rewardsReleased
        );
    }

    function withdrawRewards(uint256 depositId) external {
        require(depositId <= nftDeposits.length);
        require(nftDeposits[depositId].rewardsEarned  > 0, "Amound should be greater than zero");
        rewardsToken.rewardsMint(msg.sender, nftDeposits[depositId].rewardsEarned );
        nftDeposits[depositId].rewardsReleased += nftDeposits[depositId].rewardsEarned;
        nftDeposits[depositId].rewardsEarned = 0;

        emit RewardsWithdrawLog(
            depositId,
            msg.sender,
            nftDeposits[depositId].tokenId,
            nftDeposits[depositId].amount,
            block.timestamp,
            0,
            nftDeposits[depositId].rewardsReleased
        );
    }

    function getItemIndexByNFT(uint256 tokenId) external view returns (uint256) {
        uint256 depositId;
        for(uint256 i = 0; i < nftDeposits.length; i ++){
            if(tokenId == nftDeposits[i].tokenId){
                depositId = nftDeposits[i].id;
            }
        }
        return depositId;
    }

    function getRewardsAmount(uint256 depositId) external view returns (uint256) {
        require(depositId <= nftDeposits.length, "Deposit id is not valid");        
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for this depositId. Please contact support team.");  
        if ((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds) {
            uint256 rewardAmount = nftDeposits[depositId].rewardsEarned + rewardsTokenAmount*stakeWeight[nftDeposits[depositId].tokenId]/stakedTotal;            
            return rewardAmount;
        } else {
            return nftDeposits[depositId].rewardsEarned;
        }
    }

    function getActivityLogs(address _walletAddress) external view returns (NFTDeposit[] memory) {
        address walletAddress = _walletAddress;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for(uint256 i = 0; i < nftDeposits.length; i ++){
            if(walletAddress == nftDeposits[i].depositOwner){
                itemCount += 1;
            }
        }
        NFTDeposit[] memory items = new NFTDeposit[](itemCount);
        for (uint256 i = 0; i < nftDeposits.length; i++) {
            if(walletAddress == nftDeposits[i].depositOwner){
                NFTDeposit storage item = nftDeposits[i];
                items[currentIndex] = item;
                currentIndex += 1;
            }
        }
        return items;
    }

}