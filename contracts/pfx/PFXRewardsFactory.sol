// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// TODO: Step #3: sell PFX for AVAX in the PFX/AVAX pool
// TODO: Step #4: distribute AVAX to PFX-LP holders and LM participants, but not to the SR contracts
// TODO: Exclude the following addresses: SR contracts, locked liquidity
// TODO: Investigate - see if the LP itself can store PFX-LP (instead of just minting / burning). If that is the case, exclude it from the rewards
// TODO: Write: this contract is not using SafeMath because we are using Solidity >= 0.8.0

// TODO: Add proper introductory comment
// TODO: Add comments to functions

import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';
import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol'; // TODO: Add holders to IPolarfoxLiquidity
// TODO: Add IStakingRewards

// TODO: Add holders to IStakingRewards
// TODO: Add event for setReflectionAddress
// TODO: Add event for setPfxAvaxPair
// TODO: Add event for setPfxRouter
// TODO: Add other events
// TODO: This contract should be properly excluded from PFX fees
// TODO: Think - should we define functions to update PFX and WAVAX? Or is it better to deploy a new contract if it ever comes to that?
// TODO: When we change PFXRewardsFactory, should we send the PFX and AVAX to the new one? Or is this dangerous from a safety perspective?
// TODO: Write getters and setters for PfxPool

import './Ownable.sol';
import './IPFX.sol';
import './IERC20.sol';

contract PFXRewardsFactory is Ownable {
    struct PfxPool {
        string name;
        uint ratio;
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

    // Minimum PFX balance to be able to give rewards
    uint256 public minimumPfxBalance;

    // Eligible PFX pools
    PfxPool[] public pfxPools;

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

        // TODO: Initialize pfxPools
    }

    // Public methods
    function swapPfxToAvax() public {
        // The amount of PFX to swap
        uint256 amountIn = IERC20(pfx).balanceOf(address(this));

        // Exit if the PFX balance is below a certain amount
        require(amountIn < minimumPfxBalance, 'PFXRewardsFactory::swapPfxToAvax: PFX balance is below minimum');

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
        uint toSendTotal = address(this).balance;

        // Exit if the AVAX balance is below a certain amount
        // ...

    struct PfxPool {
        string name;
        uint ratio;
        address pool;
        address stakingRewards;
    }

        // For each supported pool
        for (uint i = 0; i < pfxPools.length; i++) {
            // Find the relevant PFX-LP holders
            address[] pfxLpHolders = IPolarfoxLiquidity(pfxPools[i].pool).holders();

            // Remove the relevant StakingRewards address from the PFX-LP holders
            uint stakingRewardsIndex = IPolarfoxLiquidity(pfxPools[i].pool).holdersIndex[pfxPools[i].stakingRewards];
            pfxLpHolders[stakingRewardsIndex] = pfxLpHolders[pfxLpHolders.length-1];
            pfxLpHolders.pop();

            // Find the relevant liquidity mining participants
            address[] lmParticipants = IStakingRewards(pfxAvaxPools[i]).stakingRewards();

            // TODO: Using the total supply of PFX-LP in the math would save us from having to compute it ourselves by summing everything, which is computer-intensive.
            // TODO: However, is it exact? What if we are missing some PFX-LP?
            // TODO: In theory, it should all add up, unless some addresses are blacklisted.

            // Determine the amount of AVAX to send for this pool
            uint toSend = toSendTotal * pfxPools[i].ratio / 1000;

            // Send the AVAX
            for (...) {
                // ...
            }
        }
    }

    function distributeRewards() public {
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
}
