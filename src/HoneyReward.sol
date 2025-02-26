// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HoneyReward {
    using SafeERC20 for IERC20;

    IERC20 public immutable honeybeeToken;
    IERC20 public immutable honeyToken;

    uint256 public immutable rewardRate;
    uint256 public immutable periodStart;
    uint256 public immutable periodEnd;
    uint256 public constant TOTAL_REWARDS = 20_000_000_000 * 10**18;
    uint256 public constant DAILY_CAP_PERCENTAGE = 100;
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant SECONDS_PER_DAY = 86_400;

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    bool public rewardsFinalized;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastClaimTimestamp;

    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(
        address _honeybeeToken,
        address _honeyToken,
        uint256 _rewardRate,
        uint256 _periodStart,
        uint256 _periodEnd
    ) {
        require(_periodEnd > _periodStart, "Invalid period");
        honeybeeToken = IERC20(_honeybeeToken);
        honeyToken = IERC20(_honeyToken);
        rewardRate = _rewardRate;
        periodStart = _periodStart;
        periodEnd = _periodEnd;
        lastUpdateTime = _periodStart;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodEnd ? block.timestamp : periodEnd;
    }

    function rewardPerToken() public view returns (uint256) {
        if (honeybeeToken.totalSupply() == 0 || block.timestamp <= periodStart) {
            return rewardPerTokenStored;
        }
        if (rewardsFinalized || block.timestamp >= periodEnd) {
            // Return the finalized reward per token at periodEnd
            return ((periodEnd - periodStart) * rewardRate * 1e18) / honeybeeToken.totalSupply();
        }
        uint256 timeApplicable = lastTimeRewardApplicable();
        if (timeApplicable <= lastUpdateTime) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((timeApplicable - lastUpdateTime) * rewardRate * 1e18) /
                honeybeeToken.totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return
            ((honeybeeToken.balanceOf(account) *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    function updateReward(address account) public {
        if (block.timestamp >= periodEnd && !rewardsFinalized) {
            // Finalize rewards at periodEnd
            rewardPerTokenStored = ((periodEnd - periodStart) * rewardRate * 1e18) / honeybeeToken.totalSupply();
            lastUpdateTime = periodEnd;
            rewardsFinalized = true;
        } else if (!rewardsFinalized) {
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = lastTimeRewardApplicable();
        }
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function getDailyRewardCap(address account) public view returns (uint256) {
        uint256 honeybeeBalance = honeybeeToken.balanceOf(account);
        return (honeybeeBalance * DAILY_CAP_PERCENTAGE) / BASIS_POINTS;
    }

    function claimReward() public {
        updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        require(honeybeeToken.balanceOf(msg.sender) > 0, "Must hold Honeybee tokens to claim");

        if (reward > 0) {
            uint256 dailyCap = getDailyRewardCap(msg.sender);
            uint256 timeSinceLastClaim = block.timestamp - lastClaimTimestamp[msg.sender];
            uint256 claimable;

            if (timeSinceLastClaim >= SECONDS_PER_DAY) {
                claimable = reward > dailyCap ? dailyCap : reward;
            } else {
                uint256 availableCap = (dailyCap * timeSinceLastClaim) / SECONDS_PER_DAY;
                claimable = reward > availableCap ? availableCap : reward;
            }

            if (claimable > 0) {
                rewards[msg.sender] = reward - claimable;
                lastClaimTimestamp[msg.sender] = block.timestamp;
                honeyToken.safeTransfer(msg.sender, claimable);
                emit RewardsClaimed(msg.sender, claimable);
            }
        }
    }
}