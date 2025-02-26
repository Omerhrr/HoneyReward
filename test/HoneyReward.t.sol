// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/HoneyReward.sol"; // Adjust path based on your project structure
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 contract with minting capability
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract HoneyRewardTest is Test {
    HoneyReward rewardContract;
    MockERC20 honeybeeToken;
    MockERC20 honeyToken;

    address user1 = address(0x123);
    address user2 = address(0x456);
    address owner = address(this);

    uint256 constant TOTAL_REWARDS = 20_000_000_000 * 10**18;
    uint256 constant DURATION = 94_608_000; // 3 years in seconds
    uint256 constant REWARD_RATE = TOTAL_REWARDS / DURATION; // ~211,404 wei/second
    uint256 constant SECONDS_PER_DAY = 86_400;

    function setUp() public {
        honeybeeToken = new MockERC20("Honeybee Token", "HONEYBEE");
        honeyToken = new MockERC20("Honey Token", "HONEY");

        rewardContract = new HoneyReward(
            address(honeybeeToken),
            address(honeyToken),
            REWARD_RATE,
            block.timestamp,
            block.timestamp + DURATION
        );

        honeybeeToken.mint(user1, 1_000_000 * 10**18); // 1M tokens
        honeybeeToken.mint(user2, 500_000 * 10**18);  // 500K tokens
        honeyToken.mint(address(rewardContract), TOTAL_REWARDS);
    }

    function testDeployment() public {
        assertTrue(address(rewardContract.honeybeeToken()) == address(honeybeeToken), "Honeybee token address mismatch");
        assertTrue(address(rewardContract.honeyToken()) == address(honeyToken), "Honey token address mismatch");
        assertTrue(rewardContract.rewardRate() == REWARD_RATE, "Reward rate mismatch");
        assertTrue(rewardContract.periodStart() == block.timestamp, "Period start mismatch");
        assertTrue(rewardContract.periodEnd() == block.timestamp + DURATION, "Period end mismatch");
        assertTrue(honeyToken.balanceOf(address(rewardContract)) == TOTAL_REWARDS, "Initial funding mismatch");
    }

    function testRewardAccrual() public {
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        uint256 totalSupply = honeybeeToken.totalSupply();
        uint256 expectedRewardPerToken = (SECONDS_PER_DAY * REWARD_RATE * 1e18) / totalSupply;

        assertApproxEqAbs(rewardContract.rewardPerToken(), expectedRewardPerToken, 1e15, "Reward per token incorrect");

        uint256 user1Earned = rewardContract.earned(user1);
        uint256 expectedUser1 = (1_000_000 * 10**18 * expectedRewardPerToken) / 1e18;
        assertApproxEqAbs(user1Earned, expectedUser1, 1e15, "User1 earned rewards incorrect");
    }

    function testClaimWithHoneybee() public {
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        uint256 user1BalanceBefore = honeyToken.balanceOf(user1);
        
        vm.prank(user1);
        rewardContract.claimReward();

        uint256 user1BalanceAfter = honeyToken.balanceOf(user1);
        uint256 dailyCap = rewardContract.getDailyRewardCap(user1);
        assertTrue(user1BalanceAfter > user1BalanceBefore, "User1 balance should increase");
        assertApproxEqAbs(user1BalanceAfter - user1BalanceBefore, dailyCap, 1e15, "Claim amount incorrect");
        assertTrue(rewardContract.lastClaimTimestamp(user1) == block.timestamp, "Last claim timestamp incorrect");
    }

    function testClaimFailsWithZeroHoneybee() public {
        address noHoneybeeUser = address(0x789);
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        
        vm.prank(noHoneybeeUser);
        vm.expectRevert("Must hold Honeybee tokens to claim");
        rewardContract.claimReward();
    }

    function testDailyCap() public {
        vm.warp(block.timestamp + SECONDS_PER_DAY * 2);
        
        vm.prank(user1);
        rewardContract.claimReward();

        uint256 user1BalanceAfterFirst = honeyToken.balanceOf(user1);
        assertApproxEqAbs(user1BalanceAfterFirst, 10_000 * 10**18, 1e15, "First claim amount incorrect");

        vm.prank(user1);
        rewardContract.claimReward();
        uint256 user1BalanceAfterSecond = honeyToken.balanceOf(user1);
        assertTrue(user1BalanceAfterSecond == user1BalanceAfterFirst, "No additional rewards within same day");
    }

    function testProRatedCap() public {
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        
        vm.prank(user1);
        rewardContract.claimReward();

        vm.warp(block.timestamp + SECONDS_PER_DAY / 2);
        uint256 user1BalanceBefore = honeyToken.balanceOf(user1);
        
        vm.prank(user1);
        rewardContract.claimReward();

        uint256 user1BalanceAfter = honeyToken.balanceOf(user1);
        assertTrue(user1BalanceAfter > user1BalanceBefore, "Balance should increase after half day");
        assertApproxEqAbs(user1BalanceAfter - user1BalanceBefore, 5_000 * 10**18, 1e15, "Pro-rated claim amount incorrect");
    }

    function testNoRewardsAfterPeriodEnd() public {
        // Warp to just before the end and update rewards
        vm.warp(block.timestamp + DURATION - 1);
        vm.prank(user1);
        rewardContract.updateReward(user1);
        uint256 user1EarnedBefore = rewardContract.earned(user1);

        // Warp past the end and update rewards again
        vm.warp(block.timestamp + DURATION + SECONDS_PER_DAY);
        vm.prank(user1);
        rewardContract.updateReward(user1); // Ensure state is updated post-period
        uint256 user1EarnedAfter = rewardContract.earned(user1);

        assertTrue(user1EarnedAfter == user1EarnedBefore, "Rewards should not increase after period end");
    }

    function testRewardTransfer() public {
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        uint256 contractBalanceBefore = honeyToken.balanceOf(address(rewardContract));
        
        vm.prank(user1);
        rewardContract.claimReward();

        uint256 contractBalanceAfter = honeyToken.balanceOf(address(rewardContract));
        assertTrue(contractBalanceBefore > contractBalanceAfter, "Contract balance should decrease");
        assertApproxEqAbs(contractBalanceBefore - contractBalanceAfter, 10_000 * 10**18, 1e15, "Transferred amount incorrect");
    }
}