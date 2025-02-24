// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/HoneyReward.sol";

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

    uint256 constant TOTAL_REWARDS = 20_000_000_000 * 10 ** 18;
    uint256 constant DURATION = 94_608_000;
    uint256 constant REWARD_RATE = TOTAL_REWARDS / DURATION;
    uint256 constant INITIAL_HONEYBEE_SUPPLY = 100_000_000 * 10 ** 18;

    function setUp() public {
        honeybeeToken = new MockERC20("Honeybee Token", "HONEYBEE");
        honeyToken = new MockERC20("Honey Token", "HONEY");

        rewardContract = new HoneyReward(
            address(honeybeeToken), address(honeyToken), REWARD_RATE, block.timestamp, block.timestamp + DURATION
        );

        honeybeeToken.mint(user1, 50_000_000 * 10 ** 18);
        honeybeeToken.mint(user2, 25_000_000 * 10 ** 18);
        honeyToken.mint(address(rewardContract), TOTAL_REWARDS);

        vm.startPrank(user1);
        honeybeeToken.approve(address(rewardContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        honeybeeToken.approve(address(rewardContract), type(uint256).max);
        vm.stopPrank();
    }

    // function testDeployment() public {
    //     assertEq(rewardContract.honeybeeToken(), address(honeybeeToken));
    //     assertEq(rewardContract.honeyToken(), address(honeyToken));
    //     assertEq(rewardContract.rewardRate(), REWARD_RATE);
    //     assertEq(rewardContract.periodStart(), block.timestamp);
    //     assertEq(rewardContract.periodEnd(), block.timestamp + DURATION);
    //     assertEq(honeyToken.balanceOf(address(rewardContract)), TOTAL_REWARDS);
    // }

    function testRewardCalculation() public {
        vm.warp(block.timestamp + 86_400);
        uint256 totalSupply = honeybeeToken.totalSupply();
        uint256 dailyReward = REWARD_RATE * 86_400;

        uint256 expectedUser1Reward = (dailyReward * 50_000_000 * 10 ** 18) / totalSupply;
        uint256 user1Earned = rewardContract.earned(user1);
        assertApproxEqAbs(user1Earned, expectedUser1Reward, 1e15);

        uint256 expectedUser2Reward = (dailyReward * 25_000_000 * 10 ** 18) / totalSupply;
        uint256 user2Earned = rewardContract.earned(user2);
        assertApproxEqAbs(user2Earned, expectedUser2Reward, 1e15);
    }

    function testClaimReward() public {
        vm.warp(block.timestamp + 86_400);
        uint256 user1BalanceBefore = honeyToken.balanceOf(user1);
        vm.prank(user1);
        rewardContract.claimReward();
        uint256 user1BalanceAfter = honeyToken.balanceOf(user1);

        uint256 totalSupply = honeybeeToken.totalSupply();
        uint256 dailyReward = REWARD_RATE * 86_400;
        uint256 expectedReward = (dailyReward * 50_000_000 * 10 ** 18) / totalSupply;

        assertApproxEqAbs(user1BalanceAfter - user1BalanceBefore, expectedReward, 1e15);
        assertEq(rewardContract.earned(user1), 0);
    }

    function testUpdateRewardBeforeTransfer() public {
        vm.warp(block.timestamp + 86_400);

        vm.prank(user1);
        rewardContract.updateMyReward();
        uint256 user1RewardBefore = rewardContract.earned(user1);

        vm.prank(user1);
        honeybeeToken.transfer(user2, 25_000_000 * 10 ** 18);

        vm.warp(block.timestamp + 86_400 * 2);

        uint256 totalSupply = honeybeeToken.totalSupply();
        uint256 dailyReward = REWARD_RATE * 86_400;

        uint256 expectedUser1Day1 = (dailyReward * 50_000_000 * 10 ** 18) / totalSupply;
        uint256 expectedUser1Day2 = (dailyReward * 25_000_000 * 10 ** 18) / totalSupply;
        uint256 expectedUser1Total = user1RewardBefore + expectedUser1Day2;
        uint256 user1Earned = rewardContract.earned(user1);
        assertApproxEqAbs(user1Earned, expectedUser1Total, 1e15);

        uint256 expectedUser2Day1 = (dailyReward * 25_000_000 * 10 ** 18) / totalSupply;
        uint256 expectedUser2Day2 = (dailyReward * 50_000_000 * 10 ** 18) / totalSupply;
        uint256 expectedUser2Total = expectedUser2Day1 + expectedUser2Day2;
        uint256 user2Earned = rewardContract.earned(user2);
        assertApproxEqAbs(user2Earned, expectedUser2Total, 1e15);
    }

    function testNoRewardsAfterPeriodEnd() public {
        vm.warp(block.timestamp + DURATION - 1);
        vm.prank(user1);
        rewardContract.updateMyReward();
        uint256 user1EarnedBefore = rewardContract.earned(user1);

        vm.warp(block.timestamp + DURATION + 86_400);
        uint256 user1EarnedAfter = rewardContract.earned(user1);

        assertEq(user1EarnedAfter, user1EarnedBefore);
    }

    function testZeroTotalSupply() public {
        MockERC20 freshHoneybeeToken = new MockERC20("Fresh Honeybee", "FHONEYBEE");
        honeyToken.mint(address(this), TOTAL_REWARDS);

        HoneyReward newReward = new HoneyReward(
            address(freshHoneybeeToken), address(honeyToken), REWARD_RATE, block.timestamp, block.timestamp + DURATION
        );

        honeyToken.transfer(address(newReward), TOTAL_REWARDS);

        vm.warp(block.timestamp + 86_400);
        assertEq(newReward.rewardPerToken(), 0);
    }

    function testReentrancyProtection() public {
        MaliciousReceiver malicious = new MaliciousReceiver(address(rewardContract));
        honeybeeToken.mint(address(malicious), 10_000_000 * 10 ** 18);
        honeyToken.mint(address(rewardContract), TOTAL_REWARDS);

        vm.warp(block.timestamp + 86_400);
        vm.prank(address(malicious));
        malicious.claimRewards();

        uint256 maliciousEarned = rewardContract.earned(address(malicious));
        assertEq(maliciousEarned, 0);
    }
}

contract MaliciousReceiver {
    HoneyReward rewardContract;
    bool public alreadyCalled;

    constructor(address _rewardContract) {
        rewardContract = HoneyReward(_rewardContract);
    }

    function claimRewards() external {
        rewardContract.claimReward();
    }

    fallback() external payable {
        if (!alreadyCalled) {
            alreadyCalled = true;
            rewardContract.claimReward();
        }
    }
}
