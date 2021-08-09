// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

// TODO: Step #3: sell PFX for AVAX in the PFX/AVAX pool
// TODO: Step #4: distribute AVAX to PFX-LP holders and LM participants, but not to the SR contracts

// TODO: Add proper introductory comment

// TODO: Use this to perform the swap in the PFX/AVAX pool
import '@polarfox/periphery/contracts/interfaces/IPolarfoxRouter.sol';

// TODO: Use these to get the PFX-LP holders and LM participants
import '@polarfox/core/contracts/interfaces/IPolarfoxPair.sol';
// import '@polarfox/core/contracts/interfaces/IPolarfoxLiquidity.sol'; // This should not be necessary

import './Ownable.sol';
import './IPFX.sol';
import './IERC20.sol';

contract PFXRewardsFactory is Ownable {
    // PFX address
    address public pfx;

    // WAVAX address
    address public wavax;

    // PFX/AVAX pair address
    address public pfxAvaxPair;

    // Polarfox router address
    address public pfxRouter;

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
    }

    // Public methods
    function swapPfxToAvax() public {
        // The amount of PFX to swap
        uint amountIn = IERC20(pfx).balanceOf(address(this));

        // Slippage - minimumRatio // TODO: Move somewhere else
        uint mimimumRatio = 950; // 95% = 950/1000

        // Exit if the PFX balance is below a certain amount
        // ...

        // Get the PFX/AVAX pair's reserves
        uint balancePfx = IERC20(pfx).balanceOf(address(pfxAvaxPair));
        uint balanceAvax = IERC20(wavax).balanceOf(address(pfxAvaxPair));

        // Calculate the price of PFX. Will revert if the pool is not properly initialized
        uint pfxPrice = balanceAvax / balancePfx;

        // Calculate amountOut (expected AVAX amount)
        uint amountOut = amountIn * pfxPrice;

        // Calculate amountOutMin (minimum AVAX amount)
        uint amountOutMin = (amountOut * mimimumRatio) / 1000;

        // Approve the router
        // TODO: Is this needed? Only way to know is to try
        // ...

        // Call to swapExactTokensForAvax
        IPolarfoxRouter(pfxRouter).swapExactTokensForAvax(
            amountIn,
            amountOutMin, // TODO: When testing is done, do all the math on one line
            path, // TODO: define
            address(this),
            deadline // TODO: define
        )
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
}
