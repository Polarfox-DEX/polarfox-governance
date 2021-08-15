// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// TODO: Add proper introductory comment
// TODO: Write: this contract is not using SafeMath because we are using Solidity >= 0.8.0
// TODO: Add comments to functions
// TODO: Optimize gas usage

import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';
import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol';
import '@polarfox/core/contracts/interfaces/IStakingRewards.sol';

import './Ownable.sol';
import './IERC20.sol';

contract PFXRewardsFactory is Ownable {
    struct PfxPool {
        uint256 ratio;
        address pool;
        address stakingRewards;
    }

    /// @notice PFX address
    address public pfx;

    /// @notice Polarfox router address
    address public pfxRouter;

    /// @notice Minimum PFX balance to be able to swap PFX against AVAX
    uint256 public minimumPfxBalance;

    /// @notice Minimum AVAX balance to be able to give rewards
    uint256 public minimumAvaxBalance;

    /// @notice Eligible PFX pools
    PfxPool[] public pfxPools;

    /// @notice Gas limit - when there is less gas then this number, we should stop executing the contract
    uint256 gasLimit;

    // TODO: Set the fields below to internal or public?
    /// @notice Current amount of AVAX being distributed
    uint256 public currentBatchAmount_;

    /// @notice Index of the last processed pool
    uint256 public lastProcessedPool_;

    /// @notice Index of the last processed PFX-LP address
    uint256 public lastProcessedPfxLpAddress_;

    /// @notice Index of the last processed liquidity mining address
    uint256 public lastProcessedLmAddress_;

    /// @notice True if the currently processed pool is set up, false otherwise
    bool public isSetUpPool_;

    /// @notice Amount of AVAX to send to the currently processed pool
    uint256 public toSendPool_;

    /// @notice Total supply of the currently processed PFX-LP token, minus the supply of the locked liquidity addresses
    uint256 public totalSupply_;

    /// @notice Locked liquidity addresses. They should not receive rewards
    address[] public lockedLiquidityAddresses;
    mapping(address => bool) public isLockedLiquidity;

    event SwappedPfx(uint256 amountIn);
    event SentAvax(uint256 toSendTotal);
    event SetPfxRouter(address _pfxRouter);
    event SetMinimumPfxBalance(uint256 _minimumPfxBalance);
    event SetMinimumAvaxBalance(uint256 _minimumAvaxBalance);
    event SetPfxPools(uint256[] ratios, address[] pools, address[] stakingRewards);
    event SetGasLimit(uint256 _gasLimit);
    event AddedLockedLiquidityAddress(address _address);
    event RemovedLockedLiquidityAddress(address _address);

    constructor(address pfx_, address pfxRouter_) {
        pfx = pfx_;
        pfxRouter = pfxRouter_;
        minimumPfxBalance = 10000000000000000000; // 10 PFX
        minimumAvaxBalance = 1 ether; // 1 AVAX
        gasLimit = 6000; // TODO: Try and lower this as much as possible - be aware of the loops on the locked liquidity addresses

        // Consider the 0x0 address locked liquidity
        lockedLiquidityAddresses.push(address(0));
        isLockedLiquidity[address(0)] = true;
    }

    // Public methods
    receive() external payable {}

    function swapPfxToAvax() public {
        // The amount of PFX to swap
        uint256 amountIn = IERC20(pfx).balanceOf(address(this));

        // Exit if the PFX balance is below a certain amount
        if (amountIn < minimumPfxBalance) return;

        // Create the PFX/AVAX path
        address[] memory path = new address[](2);
        path[0] = pfx;
        path[1] = IPolarfoxRouter(pfxRouter).WAVAX();

        // Approve the router
        IERC20(pfx).approve(pfxRouter, amountIn);

        // Call to swapExactTokensForAvax
        IPolarfoxRouter(pfxRouter).swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn,
            0, // Minimum output amount - we accept any amount of AVAX
            path, // Path for PFX/AVAX
            address(this), // Recipient
            block.timestamp // Deadline
        );

        emit SwappedPfx(amountIn);
    }

    function sendAvax() public {
        // Exit if the current batch amount is 0
        if (currentBatchAmount_ == 0) return;

        // For each supported pool
        for (uint256 i = lastProcessedPool_; i < pfxPools.length; i++) {
            // Exit if out of gas, keep going otherwise
            if (sendAvaxPool(i)) return; // sendAvaxPool() returns true if out of gas

            // Update the last processed indexes
            lastProcessedPool_++;
            lastProcessedPfxLpAddress_ = 0;
            lastProcessedLmAddress_ = 0;

            // Mark the next pool as not set up
            isSetUpPool_ = false;
        }

        // When done, set currentBatchAmount_ to 0
        currentBatchAmount_ = 0;

        if (pfxPools.length > 0) emit SentAvax(currentBatchAmount_);
    }

    function distributeRewards() public {
        // If the factory is not currently processing a batch of rewards
        if (currentBatchAmount_ == 0) {
            // Throw an error if there is no PFX to swap and no AVAX to send
            require(
                IERC20(pfx).balanceOf(address(this)) < minimumPfxBalance || address(this).balance < minimumAvaxBalance + 1 ether,
                'PFXRewardsFactory::distributeRewards: no rewards to distribute'
            );

            // Swap PFX to AVAX
            swapPfxToAvax();

            // Create a batch of rewards
            currentBatchAmount_ = address(this).balance - 1 ether;

            // Initialize values
            lastProcessedPool_ = 0;
            lastProcessedPfxLpAddress_ = 0;
            lastProcessedLmAddress_ = 0;

            // Mark the next pool as not set up
            isSetUpPool_ = false;

            // Start distributing AVAX
            sendAvax();
        }
        // If the factory is currently processing a batch of rewards
        else {
            // Keep processing the batch of rewards
            sendAvax();
        }
    }

    // Internal methods
    function setUpPool(uint256 i, IPolarfoxLiquidity currentPool) internal {
        // Setup - only needs to be run once per pool
        uint256 j;
        uint totalSupplyTmp;

        // Get the total supply of PFX-LP for this pool. If it is 0, exit
        totalSupplyTmp = currentPool.totalSupply();
        if (totalSupplyTmp == 0) return;

        // Remove the locked liquidity addresses' balances from the total supply
        for (j = 0; j < lockedLiquidityAddresses.length; j++) {
            totalSupplyTmp -= currentPool.balanceOf(lockedLiquidityAddresses[j]);
        }
        // If the new total supply is 0, exit
        if (totalSupplyTmp == 0) return;

        // Gas optimization
        totalSupply_ = totalSupplyTmp;

        // Determine the amount of AVAX to send for this pool
        toSendPool_ = (currentBatchAmount_ * pfxPools[i].ratio) / 1000;

        // Initialize values
        lastProcessedPfxLpAddress_ = 0;

        // Mark the pool as set up
        isSetUpPool_ = true;
    }

    function sendAvaxPool(uint256 i) internal returns (bool outOfGas) {
        IPolarfoxLiquidity currentPool = IPolarfoxLiquidity(pfxPools[i].pool);
        uint256 j;

        // Set up the pool
        if (!isSetUpPool_) setUpPool(i, currentPool);

        // Exit if the total supply of PFX-LP for this pool is 0
        if (totalSupply_ == 0) return false;

        // Find the relevant PFX-LP holders, including the relevant StakingRewards address and locked liquidity addresses
        address[] memory pfxLpHolders = currentPool.holders();

        // Find the relevant liquidity mining participants
        // No need to remove locked liquidity accounts as they do not participate in liquidity mining anyway
        address[] memory lmParticipants = IStakingRewards(pfxPools[i].stakingRewards).holders();

        // If the liquidity mining pool has participants, it makes it a PFX-LP holder, so we have to remove it from the address list
        if (lmParticipants.length > 0) {
            uint256 stakingRewardsIndex = currentPool.holdersIndex(pfxPools[i].stakingRewards);

            pfxLpHolders[stakingRewardsIndex] = address(0); // Replace with the 0x0 address
        }

        // Remove the relevant locked liquidity addresses from the PFX-LP holders
        for (j = 0; j < lockedLiquidityAddresses.length; j++) {
            if (currentPool.balanceOf(lockedLiquidityAddresses[j]) > 0) {
                pfxLpHolders[currentPool.holdersIndex(lockedLiquidityAddresses[j])] = address(0); // Replace with the 0x0 address
            }
        }

        // Distribution - will need to be run multiple times
        uint256 toSend;

        // Send the AVAX to PFX-LP holders
        for (j = lastProcessedPfxLpAddress_; j < pfxLpHolders.length; j++) {
            // Ignore illegal addresses, represented by address(0)
            if (pfxLpHolders[j] == address(0)) continue;

            // Determine the amount of AVAX to send
            toSend = (IPolarfoxLiquidity(pfxPools[i].pool).balanceOf(pfxLpHolders[j]) * toSendPool_) / totalSupply_;

            // Send the AVAX
            if (toSend > 0) {
                // We cannot ensure everyone will receive their tokens, but this avoids a crash due to contracts holding PFX-LP and not being able to receive AVAX
                payable(pfxLpHolders[j]).send(toSend);
            }

            // Gas check
            if (gasleft() < gasLimit) {
                // Out of gas: exit
                lastProcessedPfxLpAddress_ = j + 1; // We will start at the next holder

                return true;
            }
        }

        // Send the AVAX to liquidity mining participants
        for (j = lastProcessedLmAddress_; j < lmParticipants.length; j++) {
            // Ignore illegal addresses, represented by address(0)
            if (lmParticipants[j] == address(0)) continue;

            // Determine the amount of AVAX to send
            toSend = (IStakingRewards(pfxPools[i].stakingRewards).balanceOf(lmParticipants[j]) * toSendPool_) / totalSupply_;

            // Send the AVAX
            if (toSend > 0) {
                // We cannot ensure everyone will receive their tokens, but this avoids a crash due to contracts holding PFX-LP and not being able to receive AVAX
                payable(lmParticipants[j]).send(toSend);
            }

            // Gas check
            if (gasleft() < gasLimit) {
                // Out of gas: exit
                lastProcessedLmAddress_ = j + 1; // We will start at the next holder

                return true;
            }
        }

        return false;
    }

    // Owner methods
    function setPfxRouter(address _pfxRouter) public onlyOwner {
        pfxRouter = _pfxRouter;

        emit SetPfxRouter(_pfxRouter);
    }

    function setMinimumPfxBalance(uint256 _minimumPfxBalance) public onlyOwner {
        minimumPfxBalance = _minimumPfxBalance;

        emit SetMinimumPfxBalance(_minimumPfxBalance);
    }

    function setMinimumAvaxBalance(uint256 _minimumAvaxBalance) public onlyOwner {
        minimumAvaxBalance = _minimumAvaxBalance;

        emit SetMinimumAvaxBalance(_minimumAvaxBalance);
    }

    function setPfxPools(
        uint256[] memory ratios,
        address[] memory pools,
        address[] memory stakingRewards
    ) public onlyOwner {
        require(
            ratios.length == pools.length && ratios.length == stakingRewards.length,
            'PFXRewardsFactory::setPfxPools: all arrays should have the same length'
        );

        uint256 i;
        uint256 summedRatios = 0;
        for (i = 0; i < ratios.length; i++) {
            summedRatios += ratios[i];
        }
        require(summedRatios == 1000, 'PFXRewardsFactory::setPfxPools: the summed up ratios should be equal to 1000 (100%)');

        // Empty the previous array
        while (pfxPools.length > 0) {
            pfxPools.pop();
        }

        for (i = 0; i < ratios.length; i++) {
            pfxPools.push(PfxPool(ratios[i], pools[i], stakingRewards[i]));
        }

        emit SetPfxPools(ratios, pools, stakingRewards);
    }

    function setGasLimit(uint256 _gasLimit) public onlyOwner {
        gasLimit = _gasLimit;

        emit SetGasLimit(_gasLimit);
    }

    function addLockedLiquidityAddress(address _address) public onlyOwner {
        require(
            !isLockedLiquidity[_address],
            'PFXRewardsFactory::addLockedLiquidityAddress: the provided address is already registered as locked liquidity'
        );

        for (uint256 i = 0; i < pfxPools.length; i++) {
            require(
                _address != pfxPools[i].stakingRewards,
                'PFXRewardsFactory::addLockedLiquidityAddress: the provided address is a StakingRewards address'
            );
        }

        lockedLiquidityAddresses.push(_address);
        isLockedLiquidity[_address] = true;

        emit AddedLockedLiquidityAddress(_address);
    }

    function removeLockedLiquidityAddress(address _address) public onlyOwner {
        require(
            !isLockedLiquidity[_address],
            'PFXRewardsFactory::removeLockedLiquidityAddress: the provided address is not registered as locked liquidity'
        );

        for (uint256 i = 0; i < lockedLiquidityAddresses.length; i++) {
            if (lockedLiquidityAddresses[i] == _address) {
                lockedLiquidityAddresses[i] = lockedLiquidityAddresses[lockedLiquidityAddresses.length - 1];
                lockedLiquidityAddresses.pop();
                break;
            }
        }

        isLockedLiquidity[_address] = false;

        emit RemovedLockedLiquidityAddress(_address);
    }
}
