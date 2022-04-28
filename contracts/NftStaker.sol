// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./IRewardsToken.sol";

abstract contract ReentrancyGuard { 
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
   _status = _ENTERED;

        _;
        _status = _NOT_ENTERED;
    }
}
contract NftStaker is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using Address for address;
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
    // rewardsTokenAmount * stakeWeight
    mapping (uint256 => uint256) public stakeWeight; // tokenId => weight, weight is in wei

    // stakingTime for tokenId
    uint256 public stakingTime = 300; // stakingtime is in seconds
    mapping (uint256 => uint256) public minimum_stakingTime; // tokenId => time, time is in seconds
    

    struct NFTDeposit {
        uint256 id; // array index
        address depositOwner; // deposited user address - nft owner address
        uint256 tokenId; // deposited nft token id
        uint256 amount; // deposited nft amount
        bool isWithdrawn; // status if this value is true, in this case user can't withdraw, and false, user can withdraw
        uint256 depositTime; // deposit time(block.time current)
        uint256 timeLockInSeconds; // minimum staking time for tokenID
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

    function setMinimumStakingTime(uint256 tokenId, uint256 _minimumStakingTime) external onlyOwner{
        minimum_stakingTime[tokenId] = _minimumStakingTime;
    }

    function setStakingTime(uint256 _stakingTime) external onlyOwner{
        stakingTime = _stakingTime;
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
        require(!Address.isContract(msg.sender), "Staking is not allowed for contracts");
        require(canStake == true, "Staking is temporarily disabled");   
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
                minimum_stakingTime[_tokenId],
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
            minimum_stakingTime[_tokenId],
            0,
            0
        );
    }    



    // Unstake without caring about rewards. EMERGENCY ONLY.
    function emergencyUnstake(uint256 depositId) public {      

        require(depositId <= nftDeposits.length);

        require(nftDeposits[depositId].depositOwner == msg.sender, "Only the sender can withdraw this deposit");

        require(nftDeposits[depositId].isWithdrawn == false, "This deposit has already been withdrawn.");

        nft.safeTransferFrom(address(this), msg.sender, nftDeposits[depositId].tokenId, nftDeposits[depositId].amount, "");

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
        require((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds + stakingTime, "You can't yet unlock this deposit.  please use emergencyUnstake instead");
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for your deposit. Please contact support team.");
        nft.safeTransferFrom(address(this), msg.sender, nftDeposits[depositId].tokenId, nftDeposits[depositId].amount, "");        
        stakedTotal = stakedTotal - nftDeposits[depositId].amount;
        nftDeposits[depositId].isWithdrawn = true;
        uint256 rewardMultiplier = ((block.timestamp - nftDeposits[depositId].depositTime -nftDeposits[depositId].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[depositId].tokenId] * nftDeposits[depositId].amount;
        nftDeposits[depositId].rewardsEarned += rewardsTokenAmount * rewardMultiplier;

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

    function unstakeAll() public {
        for(uint256 i = 0; i < nftDeposits.length; i++) {
            if(nftDeposits[i].depositOwner == msg.sender && nftDeposits[i].isWithdrawn == false) {
                nft.safeTransferFrom(address(this), msg.sender, nftDeposits[i].tokenId, nftDeposits[i].amount, "");        
                stakedTotal = stakedTotal - nftDeposits[i].amount;
                nftDeposits[i].isWithdrawn = true;
                uint256 rewardMultiplier = ((block.timestamp - nftDeposits[i].depositTime -nftDeposits[i].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[i].tokenId] * nftDeposits[i].amount;
                nftDeposits[i].rewardsEarned += rewardsTokenAmount * rewardMultiplier;
                emit NFTWithdrawLog(
                    i,
                    msg.sender,
                    nftDeposits[i].tokenId,
                    nftDeposits[i].amount,
                    block.timestamp,
                    false,
                    nftDeposits[i].rewardsEarned,
                    nftDeposits[i].rewardsReleased
                );
                rewardsToken.rewardsMint(msg.sender, nftDeposits[i].rewardsEarned );
                nftDeposits[i].rewardsReleased += nftDeposits[i].rewardsEarned;
                nftDeposits[i].rewardsEarned = 0;
                emit RewardsWithdrawLog(
                    i,
                    msg.sender,
                    nftDeposits[i].tokenId,
                    nftDeposits[i].amount,
                    block.timestamp,
                    0,
                    nftDeposits[i].rewardsReleased
                );
            }
        }
    }


    function withdrawRewards(uint256 depositId) public nonReentrant{            
        require(depositId <= nftDeposits.length, "Deposit id is not valid");
        require(nftDeposits[depositId].isWithdrawn == false, "This deposit has already been withdrawn.");
        require(nftDeposits[depositId].depositOwner == msg.sender, "You can only withdraw your own deposits.");
        require((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds + stakingTime, "You can't yet unlock this deposit.  please use emergencyUnstake instead");
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for your deposit. Please contact support team.");
        uint256 rewardMultiplier = ((block.timestamp - nftDeposits[depositId].depositTime -nftDeposits[depositId].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[depositId].tokenId] * nftDeposits[depositId].amount;
        uint256 rewardAmount = nftDeposits[depositId].rewardsEarned + rewardsTokenAmount * rewardMultiplier;  
        rewardsToken.rewardsMint(msg.sender, rewardAmount );
        nftDeposits[depositId].depositTime = block.timestamp;   
        nftDeposits[depositId].rewardsReleased += rewardAmount;
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

    function withdrawAllRewards() public nonReentrant{
        for(uint256 i = 0; i < nftDeposits.length; i++) {
            uint256 rewardMultiplier = ((block.timestamp - nftDeposits[i].depositTime -nftDeposits[i].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[i].tokenId] * nftDeposits[i].amount;
            if(nftDeposits[i].depositOwner == msg.sender && rewardMultiplier > 0 &&nftDeposits[i].isWithdrawn == false) {
                uint256 rewardAmount = nftDeposits[i].rewardsEarned + rewardsTokenAmount * rewardMultiplier;  
                rewardsToken.rewardsMint(msg.sender, rewardAmount );
                nftDeposits[i].depositTime = block.timestamp;   
                nftDeposits[i].rewardsReleased += rewardAmount;
                nftDeposits[i].rewardsEarned = 0;
                emit RewardsWithdrawLog(
                    i,
                    msg.sender,
                    nftDeposits[i].tokenId,
                    nftDeposits[i].amount,
                    block.timestamp,
                    0,
                    nftDeposits[i].rewardsReleased
                );
            }
        }
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
    
    function getRewardsAmount(uint256 depositId) external view returns (uint256, uint256) {
        require(depositId <= nftDeposits.length, "Deposit id is not valid");        
        require(rewardsTokenAmount > 0, "Smart contract owner hasn't defined reward for this depositId. Please contact support team.");  
        if (nftDeposits[depositId].isWithdrawn == true) {
            return (0, nftDeposits[depositId].rewardsReleased);
        } else {
            if ((block.timestamp - nftDeposits[depositId].depositTime) >= nftDeposits[depositId].timeLockInSeconds+stakingTime) {
                uint256 rewardMultiplier = ((block.timestamp - nftDeposits[depositId].depositTime -nftDeposits[depositId].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[depositId].tokenId] * nftDeposits[depositId].amount;
                uint256 rewardAmount = nftDeposits[depositId].rewardsEarned + rewardsTokenAmount * rewardMultiplier;          
                return (rewardAmount, nftDeposits[depositId].rewardsReleased);
            } else {
                return (nftDeposits[depositId].rewardsEarned, nftDeposits[depositId].rewardsReleased);
            }
        }        
    }


    function getAllRewardsAmount(address _stakerAddres) external view returns(uint256, uint256) {
        uint256 totalRewardsEarned = 0;
        uint256 totalRewardsReleased = 0;
        for (uint256 i = 0; i < nftDeposits.length; i++) {
            if (nftDeposits[i].depositOwner==_stakerAddres){
                 if (nftDeposits[i].isWithdrawn == true) {                    
                    totalRewardsReleased += nftDeposits[i].rewardsReleased;                    
                } else {
                    if ((block.timestamp - nftDeposits[i].depositTime) >= nftDeposits[i].timeLockInSeconds+stakingTime) {
                        uint256 rewardMultiplier = ((block.timestamp - nftDeposits[i].depositTime- nftDeposits[i].timeLockInSeconds) / stakingTime) * stakeWeight[nftDeposits[i].tokenId] * nftDeposits[i].amount;
                        uint256 rewardAmount = nftDeposits[i].rewardsEarned + rewardsTokenAmount * rewardMultiplier;
                        totalRewardsEarned += rewardAmount;
                        totalRewardsReleased += nftDeposits[i].rewardsReleased;
                    } else {
                        totalRewardsEarned += nftDeposits[i].rewardsEarned;
                        totalRewardsReleased += nftDeposits[i].rewardsReleased;
                    }
                }
            }
        }
        return (totalRewardsEarned, totalRewardsReleased);
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