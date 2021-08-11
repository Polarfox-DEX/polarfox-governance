// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// TODO: Add proper introductory comment
// TODO: Write: this contract is not using SafeMath because we are using Solidity >= 0.8.0
// TODO: Add comments to functions

import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';
import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol';
import '@polarfox/core/contracts/interfaces/IStakingRewards.sol';

// TODO: This contract should be properly excluded from PFX fees
// TODO: Think - should we define functions to update PFX and WAVAX? Or is it better to deploy a new contract if it ever comes to that?
// TODO: When we change PFXRewardsFactory, should we send the PFX and AVAX to the new one? Or is this dangerous from a safety perspective?

import './Ownable.sol';
import './IPFX.sol';
import './IERC20.sol';

contract PFXRewardsFactory is Ownable {
    struct PfxPool {
        uint256 ratio;
        address pool;
        address stakingRewards;
    }

    /// @notice PFX address
    address public pfx;

    /// @notice WAVAX address
    address public wavax;

    /// @notice PFX/AVAX pair address
    address public pfxAvaxPair;

    /// @notice Polarfox router address
    address public pfxRouter;

    /// @notice Minimum PFX balance to be able to swap PFX against AVAX
    uint256 public minimumPfxBalance;

    /// @notice Minimum AVAX balance to be able to give rewards
    uint256 public minimumAvaxBalance;

    /// @notice Eligible PFX pools
    PfxPool[] public pfxPools;

    /// @notice Locked liquidity addresses. They should not receive rewards
    address[] public lockedLiquidityAddresses;
    mapping(address => bool) public isLockedLiquidity;

    // TODO: Add definitions
    event SwappedPfx(uint256 amountIn);
    event SentAvax(uint256 toSendTotal);
    event SetPfxAvaxPair(address _pfxAvaxPair);
    event SetPfxRouter(address _pfxRouter);
    event SetMinimumPfxBalance(uint256 _minimumPfxBalance);
    event SetMinimumAvaxBalance(uint256 _minimumAvaxBalance);
    event SetPfxPools(uint256[] ratios, address[] pools, address[] stakingRewards);
    event AddedLockedLiquidityAddress(address _address);
    event RemovedLockedLiquidityAddress(address _address);

    constructor(
        address pfx_,
        address wavax_,
        address pfxAvaxPair_,
        address pfxRouter_
    ) {
        pfx = pfx_;
        wavax = wavax_;
        pfxAvaxPair = pfxAvaxPair_;
        pfxRouter = pfxRouter_;
        minimumPfxBalance = 1000000000000000000000; // 1,000 PFX
        minimumAvaxBalance = 1 ether; // 1 AVAX

        // Consider the 0x0 address locked liquidity
        lockedLiquidityAddresses.push(address(0));
        isLockedLiquidity[address(0)];
    }

    // Public methods
    function swapPfxToAvax() public {
        // The amount of PFX to swap
        uint256 amountIn = IERC20(pfx).balanceOf(address(this));

        // Exit if the PFX balance is below a certain amount
        if (amountIn < minimumPfxBalance) return;

        // Create the PFX/AVAX path
        address[] memory path = new address[](2);
        path[0] = pfx;
        path[1] = wavax;

        // Approve the router
        IERC20(pfx).approve(address(this), amountIn);

        // Call to swapExactTokensForAvax
        IPolarfoxRouter(pfxRouter).swapExactTokensForAVAX(
            amountIn,
            0, // Minimum output amount - we accept any amount of AVAX
            path, // Path for PFX/AVAX
            address(this), // Recipient
            block.timestamp // Deadline
        );

        emit SwappedPfx(amountIn);
    }

    function sendAvax() public {
        // Determine the amount of AVAX to send accross all pools
        uint256 toSendTotal = address(this).balance - (1 ether); // Keep 1 AVAX to account for inaccuracies in divisions

        // Exit if the AVAX balance is below a certain amount
        if (toSendTotal < minimumAvaxBalance) return;

        // For each supported pool
        for (uint256 i = 0; i < pfxPools.length; i++) {
            uint256 j;

            // Find the relevant PFX-LP holders, including the relevant StakingRewards address and locked liquidity addresses
            address[] memory pfxLpHoldersTmp = IPolarfoxLiquidity(pfxPools[i].pool).holders();

            // Remove the relevant StakingRewards address and locked liquidity addresses from the PFX-LP holders
            // We cannot use "pop()" because pfxLpHolders is of type address[] memory, so we have to use a loop
            address[] memory pfxLpHolders = new address[](pfxLpHoldersTmp.length - lockedLiquidityAddresses.length - 1); // "- 1" is for the StakingRewards address
            uint256 stakingRewardsIndex = IPolarfoxLiquidity(pfxPools[i].pool).holdersIndex(pfxPools[i].stakingRewards);
            uint256 offset = 0;

            for (j = 0; j < IPolarfoxLiquidity(pfxPools[i].pool).holders().length; j++) {
                if (isLockedLiquidity[pfxLpHoldersTmp[j]] || i == stakingRewardsIndex) offset++;
                else pfxLpHolders[j - offset] = pfxLpHoldersTmp[j];
            }

            // Find the relevant liquidity mining participants
            // No need to remove locked liquidity accounts as they do not participate in liquidity mining anyway
            address[] memory lmParticipants = IStakingRewards(pfxPools[i].stakingRewards).holders();

            // Get the total supply of PFX-LP for this pool
            uint256 totalSupply = IPolarfoxLiquidity(pfxPools[i].pool).totalSupply();

            // Remove the locked liquidity addresses' balances from the total supply
            for (j = 0; j < lockedLiquidityAddresses.length; j++) {
                totalSupply -= IPolarfoxLiquidity(pfxPools[i].pool).balanceOf(lockedLiquidityAddresses[j]);
            }

            // Determine the amount of AVAX to send for this pool, then divide it by the total supply
            uint256 toSendPool = (toSendTotal * pfxPools[i].ratio) / (1000 * totalSupply);
            uint256 toSend;

            // Send the AVAX to PFX-LP holders
            for (j = 0; j < pfxLpHolders.length; j++) {
                toSend = (IPolarfoxLiquidity(pfxPools[i].pool).balanceOf(pfxLpHolders[j]) * toSendPool);
                if (toSend > 0) {
                    require(payable(pfxLpHolders[j]).send(toSend), 'PFXRewardsFactory::sendAvax: a transfer to a PFX-LP holder failed');
                }
            }

            // Send the AVAX to liquidity mining participants
            for (j = 0; j < lmParticipants.length; j++) {
                toSend = (IStakingRewards(pfxPools[i].stakingRewards).balanceOf(lmParticipants[j]) * toSendPool);
                if (toSend > 0) {
                    require(
                        payable(lmParticipants[j]).send(toSend),
                        'PFXRewardsFactory::sendAvax: a transfer to a liquidity mining participant failed'
                    );
                }
            }
        }

        emit SentAvax(toSendTotal);
    }

    function distributeRewards() public {
        // Throw an error if there is no PFX to swap and no AVAX to send
        // TODO: Is this the right approach? Will that crash the Clock contract?
        require(
            IERC20(pfx).balanceOf(address(this)) < minimumPfxBalance && address(this).balance - (1 ether) < minimumAvaxBalance,
            'PFXRewardsFactory::distributeRewards: no rewards to distribute'
        );

        swapPfxToAvax();
        sendAvax();
    }

    // Private methods
    // ...

    // Owner methods
    function setReflectionAddress(address _reflectionAddress) public onlyOwner {
        IPFX(pfx).setReflectionAddress(_reflectionAddress);
    }

    function setPfxAvaxPair(address _pfxAvaxPair) public onlyOwner {
        pfxAvaxPair = _pfxAvaxPair;

        emit SetPfxAvaxPair(_pfxAvaxPair);
    }

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
        require(summedRatios == 1, 'PFXRewardsFactory::setPfxPools: the summed up ratios should be equal to 1');

        // Empty the previous array
        while (pfxPools.length > 0) {
            pfxPools.pop();
        }

        for (i = 0; i < ratios.length; i++) {
            pfxPools.push(PfxPool(ratios[i], pools[i], stakingRewards[i]));
        }

        emit SetPfxPools(ratios, pools, stakingRewards);
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
