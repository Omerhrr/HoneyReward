// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/HoneyReward.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployHoneyReward is Script {
    // Existing token addresses on BSC with correct checksum
    address constant HONEYBEE_TOKEN = 0x16f5e796b7aa86A971aD3F2dA1a8e984E8766b46;
    address constant HONEY_TOKEN = 0x0c139fBB1e79807f0367D0245E23E5f52D057D5f;

    // Reward parameters
    uint256 constant TOTAL_REWARDS = 20_000_000_000 * 10**18; // 20 billion tokens (assuming 18 decimals)
    uint256 constant DURATION = 94_608_000; // 3 years in seconds (1,095 days * 86,400)
    uint256 constant REWARD_RATE = TOTAL_REWARDS / DURATION; // ~211,404 wei per second

    function run() external {
        // Start broadcasting transactions using the private key from the environment
        vm.startBroadcast();

        // Get the deployer's address
        address deployer = msg.sender;
        console.log("Deployer address:", deployer);

        // Check deployer's Honey token balance
        IERC20 honeyToken = IERC20(HONEY_TOKEN);
        uint256 deployerBalance = honeyToken.balanceOf(deployer);
        console.log("Deployer's Honey token balance:", deployerBalance / 10**18, "HONEY");
        require(deployerBalance >= TOTAL_REWARDS, "Insufficient Honey tokens to fund contract");

        // Deploy the HoneyReward contract
        HoneyReward rewardContract = new HoneyReward(
            HONEYBEE_TOKEN,
            HONEY_TOKEN,
            REWARD_RATE,
            block.timestamp,           // Start time: now
            block.timestamp + DURATION // End time: 3 years from now
        );
        console.log("HoneyReward deployed at:", address(rewardContract));

        // Approve the reward contract to spend Honey tokens (if needed, depending on token implementation)
        honeyToken.approve(address(rewardContract), TOTAL_REWARDS);
        console.log("Approved reward contract to spend", TOTAL_REWARDS / 10**18, "HONEY tokens");

        // Transfer Honey tokens to the reward contract
        honeyToken.transfer(address(rewardContract), TOTAL_REWARDS);
        console.log("Transferred", TOTAL_REWARDS / 10**18, "HONEY tokens to reward contract");

        // Verify the contract's balance
        uint256 contractBalance = honeyToken.balanceOf(address(rewardContract));
        console.log("Reward contract Honey token balance:", contractBalance / 10**18, "HONEY");
        require(contractBalance == TOTAL_REWARDS, "Failed to fund reward contract");

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}