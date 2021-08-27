// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// TODO: Optimize gas usage (use uint96 whenever possible, for instance)

import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';
import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol';
import '@polarfox/core/contracts/interfaces/IStakingRewards.sol';

import './libraries/Ownable.sol';
import './interfaces/IERC20.sol';

/**
 * The PFX rewards factory contract.
 * 🦊
 *
 * This contract receives the reflection fees from the PFX token. It converts them to AVAX,
 * and then proceeds to distribute them to liquidity providers among specific pools on the
 * Polarfox decentralized exchange. Said pools can be changed to allow for more flexibility.
 *
 * If there are many liquidity providers, gas block limits will not allow the contract to
 * distribute all the rewards at once, so it will have to be called multiple times in order
 * to do so. This is achieved by storing the IDs of the last processed addresses and
 * starting the next execution there.
 *
 * Note: this contract is not using the SafeMath library as it is using Solidity 0.8.7.
 */
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
    uint256 public gasLimit;

    /// @notice Current amount of AVAX being distributed
    uint256 public currentBatchAmount_;

    /// @notice Index of the last processed pool
    uint256 public lastProcessedPool_;

    /// @notice Index of the last processed PFX-LP address
    uint256 public nextPfxLpAddressToProcess_;

    /// @notice Index of the last processed liquidity mining address
    uint256 public nextLmAddressToProcess_;

    /// @notice Length of the currently processed pool's holders array. We keep track of this for safety purposes
    uint256 public holdersLength_;

    /// @notice Length of the currently processed pool's holders array. We keep track of this for safety purposes
    uint256 public lmParticipantsLength_;

    /// @notice True if the currently processed pool is set up, false otherwise
    bool public isSetUpPool_;

    /// @notice Amount of AVAX to send to the currently processed pool
    uint256 public toSendPool_;

    /// @notice Total supply of the currently processed PFX-LP token, minus the supply of the locked liquidity addresses
    uint256 public totalSupply_;

    /// @notice Locked liquidity addresses. They should not receive rewards
    address[] public lockedLiquidityAddresses;
    mapping(address => bool) public isLockedLiquidity;

    /// @notice An event that is emitted when some PFX is swapped for AVAX
    event SwappedPfx(uint256 amountIn);

    /// @notice An event that is emitted when AVAX is sent to liquidity providers
    event SentAvax(uint256 toSendTotal);

    /// @notice An event that is emitted when the Polarfox router is set
    event SetPfxRouter(address _pfxRouter);

    /// @notice An event that is emitted when the minimum PFX balance is set
    event SetMinimumPfxBalance(uint256 _minimumPfxBalance);

    /// @notice An event that is emitted when the minimum AVAX balance is set
    event SetMinimumAvaxBalance(uint256 _minimumAvaxBalance);

    /// @notice An event that is emitted when PFX pools are set
    event SetPfxPools(uint256[] ratios, address[] pools, address[] stakingRewards);

    /// @notice An event that is emitted when the gas limit is set
    event SetGasLimit(uint256 _gasLimit);

    /// @notice An event that is emitted when a locked liquidity address is set
    event AddedLockedLiquidityAddress(address _address);

    /// @notice An event that is emitted when a locked liquidity address is removed
    event RemovedLockedLiquidityAddress(address _address);

    constructor(address pfx_, address pfxRouter_) {
        pfx = pfx_;
        pfxRouter = pfxRouter_;
        minimumPfxBalance = 10000000000000000000; // 10 PFX
        minimumAvaxBalance = 1 ether; // 1 AVAX
        gasLimit = 6000;

        // Consider the 0x0 address locked liquidity
        lockedLiquidityAddresses.push(address(0));
        isLockedLiquidity[address(0)] = true;
    }

    // Public methods

    // Necessary to be able to receive AVAX
    receive() external payable {}

    // Swaps PFX for AVAX on the Polarfox decentralized exchange
    function swapPfxToAvax() public {
        // This function should not be callable by contracts
        require(tx.origin == msg.sender, 'PFXRewardsFactory::swapPfxToAvax: Caller cannot be a contract');

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

    // Sends AVAX to liquidity providers on specific pools. Stops when it runs out of gas
    function sendAvax() public {
        // Exit if the current batch amount is 0
        if (currentBatchAmount_ == 0) return;

        // For each supported pool
        for (uint256 i = lastProcessedPool_; i < pfxPools.length; i++) {
            // Exit if out of gas, keep going otherwise
            if (sendAvaxPool(i)) return; // sendAvaxPool() returns true if out of gas

            // Update the last processed indexes
            lastProcessedPool_++;
            nextPfxLpAddressToProcess_ = 0;
            nextLmAddressToProcess_ = 0;

            // Mark the next pool as not set up
            isSetUpPool_ = false;
        }

        // When done, set currentBatchAmount_ to 0
        currentBatchAmount_ = 0;

        if (pfxPools.length > 0) emit SentAvax(currentBatchAmount_);
    }

    // Attempts to swap PFX for AVAX and distribute said AVAX to liquidity providers on specific pools
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
            nextPfxLpAddressToProcess_ = 0;
            nextLmAddressToProcess_ = 0;

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

    // Collects and stores the data required to distribute AVAX to liquidity providers on a specific pool
    function setUpPool(uint256 i, IPolarfoxLiquidity currentPool) internal {
        // Setup - only needs to be run once per pool
        uint256 j;
        uint256 totalSupplyTmp;

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
        nextPfxLpAddressToProcess_ = 0;

        // Store the length of the current pool's holders array
        holdersLength_ = currentPool.holders().length;

        // Store the length of the current liquidity mining pool's holders array
        lmParticipantsLength_ = IStakingRewards(pfxPools[i].stakingRewards).holders().length;

        // Mark the pool as set up
        isSetUpPool_ = true;
    }

    // Sends as many AVAX rewards to the liquidity providers on a specific pool as possible. Exits when it runs out of gas
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
        for (j = nextPfxLpAddressToProcess_; j < holdersLength_ && j < pfxLpHolders.length; j++) {
            // Ignore illegal addresses, represented by address(0)
            if (pfxLpHolders[j] == address(0)) continue;

            // Determine the amount of AVAX to send
            toSend = (IPolarfoxLiquidity(pfxPools[i].pool).balanceOf(pfxLpHolders[j]) * toSendPool_) / totalSupply_;

            // Send the AVAX
            if (toSend > 0) {
                // We cannot ensure everyone will receive their tokens, but this avoids a crash due to contracts holding PFX-LP and not being able to receive AVAX
                pfxLpHolders[j].call{value: toSend, gas: 3000}('');
            }

            // Gas check
            if (gasleft() < gasLimit) {
                // Out of gas: exit
                nextPfxLpAddressToProcess_ = j + 1; // We will start at the next holder

                return true;
            }
        }

        // Do not reexecute the loop above
        nextPfxLpAddressToProcess_ = holdersLength_;

        // Send the AVAX to liquidity mining participants
        for (j = nextLmAddressToProcess_; j < lmParticipantsLength_ && j < lmParticipants.length; j++) {
            // Ignore illegal addresses, represented by address(0)
            if (lmParticipants[j] == address(0)) continue;

            // Determine the amount of AVAX to send
            toSend = (IStakingRewards(pfxPools[i].stakingRewards).balanceOf(lmParticipants[j]) * toSendPool_) / totalSupply_;

            // Send the AVAX
            if (toSend > 0) {
                // We cannot ensure everyone will receive their tokens, but this avoids a crash due to contracts holding PFX-LP and not being able to receive AVAX
                lmParticipants[j].call{value: toSend, gas: 3000}('');
            }

            // Gas check
            if (gasleft() < gasLimit) {
                // Out of gas: exit
                nextLmAddressToProcess_ = j + 1; // We will start at the next holder

                return true;
            }
        }

        return false;
    }

    // Owner methods

    // Sets a new Polarfox router
    function setPfxRouter(address _pfxRouter) public onlyOwner {
        pfxRouter = _pfxRouter;

        emit SetPfxRouter(_pfxRouter);
    }

    // Sets a new minimum PFX balance to allow swapping PFX to AVAX
    function setMinimumPfxBalance(uint256 _minimumPfxBalance) public onlyOwner {
        minimumPfxBalance = _minimumPfxBalance;

        emit SetMinimumPfxBalance(_minimumPfxBalance);
    }

    // Sets a new minimum AVAX balance to allow distributing rewards
    function setMinimumAvaxBalance(uint256 _minimumAvaxBalance) public onlyOwner {
        minimumAvaxBalance = _minimumAvaxBalance;

        emit SetMinimumAvaxBalance(_minimumAvaxBalance);
    }

    // Sets new PFX pools to distribute rewards to
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

    // Sets a new gas limit
    function setGasLimit(uint256 _gasLimit) public onlyOwner {
        gasLimit = _gasLimit;

        emit SetGasLimit(_gasLimit);
    }

    // Adds a new address to the locked liquidity addresses list
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

    // Removes an address from the locked liquidity address list
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
