// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WATT is ERC20, Ownable, ERC20Burnable, AccessControl {
    mapping (address => bool) private staking;
    mapping (address => bool) private gaming;
    modifier onlyStaking {
        require(staking[msg.sender] == true, "Only Staking contract can call this function");
        _;
    }
    modifier onlyGaming {
        require(gaming[msg.sender] == true, "Only Gaming contract can call this function");
        _;
    }

    constructor() ERC20("WATT", "WATT") {
        staking[msg.sender]=true;       
        gaming[msg.sender] = true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function updateStaking (address newAddress, bool value) external onlyOwner {
        staking[newAddress] = value;
    }

    function updateGaming (address newAddress, bool value) external onlyOwner {
        gaming[newAddress] = value;
    }

    // rewards mint function
    function rewardsMint(address to, uint256 _amount) public onlyStaking {
        _mint(to, _amount);
    }

    // rewards burn function
    function rewardsBurn(address from, uint256 _amount) public onlyGaming {
        _burn(from, _amount);
    }
}