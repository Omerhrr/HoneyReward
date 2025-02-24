// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

// Import OpenZeppelin contracts for ERC20 and safe transfers
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title HoneyReward
 * @dev Distributes Honey tokens to Honeybee token holders proportionally over 3 years.
 * Rewards are based on the user's share of the total Honeybee supply.
 * Users can claim their accrued rewards at any time.
 */
contract HoneyReward {
    using SafeERC20 for IERC20;

    // Immutable token contracts
    IERC20 public immutable honeybeeToken;
    IERC20 public immutable honeyToken;

    // Reward distribution parameters
    uint256 public immutable rewardRate;       // Reward rate in wei per second
    uint256 public immutable periodStart;      // Start time of reward distribution
    uint256 public immutable periodEnd;        // End time of reward distribution (3 years later)

    // State variables for reward tracking
    uint256 public lastUpdateTime;             // Last time the reward state was updated
    uint256 public rewardPerTokenStored;       // Accumulated reward per Honeybee token, scaled by 1e18

    // User reward tracking
    mapping(address => uint256) public userRewardPerTokenPaid;  // Reward per token paid to each user
    mapping(address => uint256) public rewards;                 // Claimable rewards for each user

    /**
     * @dev Constructor to initialize the contract.
     * @param _honeybeeToken Address of the Honeybee token contract
     * @param _honeyToken Address of the Honey token contract
     * @param _rewardRate Reward rate in wei per second (e.g., 211404000000000000)
     * @param _periodStart Start time of reward distribution
     * @param _periodEnd End time of reward distribution
     */
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

    /**
     * @dev Returns the last time rewards are applicable (current time or period end).
     * @return Last applicable timestamp for reward calculation
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodEnd ? block.timestamp : periodEnd;
    }

    /**
     * @dev Calculates the accumulated reward per Honeybee token up to now.
     * @return Accumulated reward per token, scaled by 1e18
     */
    function rewardPerToken() public view returns (uint256) {
        if (honeybeeToken.totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) /
                honeybeeToken.totalSupply());
    }

    /**
     * @dev Calculates the claimable reward for an account.
     * @param account Address of the user
     * @return Claimable reward in wei
     */
    function earned(address account) public view returns (uint256) {
        return
            ((honeybeeToken.balanceOf(account) *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    /**
     * @dev Updates the reward state for an account.
     * @param account Address of the user
     */
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /**
     * @dev Allows a user to claim their accrued rewards.
     */
    function claimReward() public {
        updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            honeyToken.safeTransfer(msg.sender, reward);
        }
    }

    /**
     * @dev Allows a user to update their reward state without claiming.
     * Should be called before transferring Honeybee tokens to update accrued rewards.
     */
    function updateMyReward() public {
        updateReward(msg.sender);
    }
}