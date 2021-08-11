// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// TODO: Step #3: sell PFX for AVAX in the PFX/AVAX pool
// TODO: Step #4: distribute AVAX to PFX-LP holders and LM participants, but not to the SR contracts
// TODO: Exclude the SR contracts from rewards
// TODO: Exclude the locked liquidity from rewards
// TODO: Investigate - see if the LP itself can store PFX-LP (instead of just minting / burning). If that is the case, exclude it from the rewards
// TODO: Write: this contract is not using SafeMath because we are using Solidity >= 0.8.0

// TODO: Add proper introductory comment
// TODO: Add comments to functions

import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';
import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol';
import '@polarfox/core/contracts/interfaces/IStakingRewards.sol';

// TODO: Add event for setReflectionAddress
// TODO: Add event for setPfxAvaxPair
// TODO: Add event for setPfxRouter
// TODO: Add other events
// TODO: This contract should be properly excluded from PFX fees
// TODO: Think - should we define functions to update PFX and WAVAX? Or is it better to deploy a new contract if it ever comes to that?
// TODO: When we change PFXRewardsFactory, should we send the PFX and AVAX to the new one? Or is this dangerous from a safety perspective?
// TODO: Write getters and setters for PfxPool
// TODO: Write getters and setters for lockedLiquidityAddresses. In the setter, require that the list does not contain SR addresses, otherwise it'd break the code

import './Ownable.sol';
import './IPFX.sol';
import './IERC20.sol';

contract PFXRewardsFactory is Ownable {
    struct PfxPool {
        uint256 ratio;
        address pool;
        address stakingRewards;
    }

    // PFX address
    address public pfx;

    // WAVAX address
    address public wavax;

    // PFX/AVAX pair address
    address public pfxAvaxPair;

    // Polarfox router address
    address public pfxRouter;

    // Minimum PFX balance to be able to swap PFX against AVAX
    uint256 public minimumPfxBalance;

    // Minimum AVAX balance to be able to give rewards
    uint256 public minimumAvaxBalance;

    // Eligible PFX pools
    PfxPool[] public pfxPools;

    // Locked liquidity addresses. They should not receive rewards
    address[] public lockedLiquidityAddresses;
    mapping(address => bool) public isLockedLiquidity;

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

        // TODO: Initialize pfxPools
        // TODO: Initialize lockedLiquidityAddresses
        // TODO: Initialize isLockedLiquidity
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
                    require(payable(lmParticipants[j]).send(toSend), 'PFXRewardsFactory::sendAvax: a transfer to a liquidity mining participant failed');
                }
            }
        }
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
    }

    function setPfxRouter(address _pfxRouter) public onlyOwner {
        pfxRouter = _pfxRouter;
    }

    function setMinimumPfxBalance(uint256 _minimumPfxBalance) public onlyOwner {
        minimumPfxBalance = _minimumPfxBalance;
    }

    function setMinimumAvaxBalance(uint256 _minimumAvaxBalance) public onlyOwner {
        minimumAvaxBalance = _minimumAvaxBalance;
    }
}
