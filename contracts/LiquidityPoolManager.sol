pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./StakingRewards.sol";

/**
 * Contract to distribute PFX tokens to whitelisted trading pairs. After deploying,
 * whitelist the desired pairs and set the avaxPfxPair. When initial administration
 * is complete. Ownership should be transferred to the Timelock governance contract.
 */
contract LiquidityPoolManager is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint;

    // Whitelisted pairs that offer PFX rewards
    // Note: AVAX/PFX is an AVAX pair
    EnumerableSet.AddressSet private avaxPairs;
    EnumerableSet.AddressSet private pfxPairs;

    // Maps pairs to their associated StakingRewards contract
    mapping(address => address) public stakes;

    // Known contract addresses for WAVAX and PFX
    address public wavax;
    address public pfx;

    // AVAX/PFX pair used to determine PFX liquidity
    address public avaxPfxPair;

    // TreasuryVester contract that distributes PFX
    address public treasuryVester;

    uint public numPools = 0;

    bool private readyToDistribute = false;

    // Tokens to distribute to each pool. Indexed by avaxPairs then pfxPairs.
    uint[] public distribution;

    uint public unallocatedPfx = 0;

    constructor(address wavax_,
                address pfx_,
                address treasuryVester_) {
        require(wavax_ != address(0) && pfx_ != address(0) && treasuryVester_ != address(0),
                "LiquidityPoolManager::constructor: Arguments can't be the zero address");
        wavax = wavax_;
        pfx = pfx_;
        treasuryVester = treasuryVester_;
    }

    /**
     * Check if the given pair is a whitelisted pair
     *
     * Args:
     *   pair: pair to check if whitelisted
     *
     * Return: True if whitelisted
     */
    function isWhitelisted(address pair) public view returns (bool) {
        return avaxPairs.contains(pair) || pfxPairs.contains(pair);
    }

    /**
     * Check if the given pair is a whitelisted AVAX pair. The AVAX/PFX pair is
     * considered an AVAX pair.
     *
     * Args:
     *   pair: pair to check
     *
     * Return: True if whitelisted and pair contains AVAX
     */
    function isAvaxPair(address pair) external view returns (bool) {
        return avaxPairs.contains(pair);
    }

    /**
     * Check if the given pair is a whitelisted PFX pair. The AVAX/PFX pair is
     * not considered a PFX pair.
     *
     * Args:
     *   pair: pair to check
     *
     * Return: True if whitelisted and pair contains PFX but is not AVAX/PFX pair
     */
    function isPfxPair(address pair) external view returns (bool) {
        return pfxPairs.contains(pair);
    }

    /**
     * Sets the AVAX/PFX pair. Pair's tokens must be AVAX and PFX.
     *
     * Args:
     *   pair: AVAX/PFX pair
     */
    function setAvaxPfxPair(address avaxPfxPair_) external onlyOwner {
        require(avaxPfxPair_ != address(0), 'LiquidityPoolManager::setAvaxPfxPair: Pool cannot be the zero address');
        avaxPfxPair = avaxPfxPair_;
    }

    /**
     * Adds a new whitelisted liquidity pool pair. Generates a staking contract.
     * Liquidity providers may stake this liquidity provider reward token and
     * claim PFX rewards proportional to their stake. Pair must contain either
     * AVAX or PFX.
     *
     * Args:
     *   pair: pair to whitelist
     */
    function addWhitelistedPool(address pair) external onlyOwner {
        require(!readyToDistribute,
                'LiquidityPoolManager::addWhitelistedPool: Cannot add pool between calculating and distributing returns');
        require(pair != address(0), 'LiquidityPoolManager::addWhitelistedPool: Pool cannot be the zero address');
        require(isWhitelisted(pair) == false, 'LiquidityPoolManager::addWhitelistedPool: Pool already whitelisted');

        address token0 = IPolarfoxPair(pair).token0();
        address token1 = IPolarfoxPair(pair).token1();

        require(token0 != token1, 'LiquidityPoolManager::addWhitelistedPool: Tokens cannot be identical');

        // Create the staking contract and associate it with the pair
        address stakeContract = address(new StakingRewards(pfx, pair));
        stakes[pair] = stakeContract;

        // Add as an AVAX or PFX pair
        if (token0 == wavax || token1 == wavax) {
            require(avaxPairs.add(pair), 'LiquidityPoolManager::addWhitelistedPool: Pair add failed');
        } else if (token0 == pfx || token1 == pfx) {
            require(pfxPairs.add(pair), 'LiquidityPoolManager::addWhitelistedPool: Pair add failed');
        } else {
            // The governance contract can be used to deploy an altered
            // LiquidityPoolManager if non-AVAX/PFX pools are desired.
            revert("LiquidityPoolManager::addWhitelistedPool: No AVAX or PFX in the pair");
        }

        numPools = numPools.add(1);
    }

    /**
     * Delists a whitelisted pool. Liquidity providers will not receiving future rewards.
     * Already vested funds can still be claimed. Re-whitelisting a delisted pool will
     * deploy a new staking contract.
     *
     * Args:
     *   pair: pair to remove from whitelist
     */
    function removeWhitelistedPool(address pair) external onlyOwner {
        require(!readyToDistribute,
                'LiquidityPoolManager::removeWhitelistedPool: Cannot remove pool between calculating and distributing returns');
        require(isWhitelisted(pair), 'LiquidityPoolManager::removeWhitelistedPool: Pool not whitelisted');

        address token0 = IPolarfoxPair(pair).token0();
        address token1 = IPolarfoxPair(pair).token1();

        stakes[pair] = address(0);

        if (token0 == wavax || token1 == wavax) {
            require(avaxPairs.remove(pair), 'LiquidityPoolManager::removeWhitelistedPool: Pair remove failed');
        } else {
            require(pfxPairs.remove(pair), 'LiquidityPoolManager::removeWhitelistedPool: Pair remove failed');
        }
        numPools = numPools.sub(1);
    }

    /**
     * Calculates the amount of liquidity in the pair. For an AVAX pool, the liquidity in the
     * pair is two times the amount of AVAX. Only works for AVAX pairs.
     *
     * Args:
     *   pair: AVAX pair to get liquidity in
     *
     * Returns: the amount of liquidity in the pool in units of AVAX
     */
    function getAvaxLiquidity(address pair) public view returns (uint) {
        (uint reserve0, uint reserve1, ) = IPolarfoxPair(pair).getReserves();

        uint liquidity = 0;

        // add the avax straight up
        if (IPolarfoxPair(pair).token0() == wavax) {
            liquidity = liquidity.add(reserve0);
        } else {
            require(IPolarfoxPair(pair).token1() == wavax, 'LiquidityPoolManager::getAvaxLiquidity: One of the tokens in the pair must be WAVAX');
            liquidity = liquidity.add(reserve1);
        }
        liquidity = liquidity.mul(2);
        return liquidity;
    }

    /**
     * Calculates the amount of liquidity in the pair. For a PFX pool, the liquidity in the
     * pair is two times the amount of PFX multiplied by the price of AVAX per PFX. Only
     * works for PFX pairs.
     *
     * Args:
     *   pair: PFX pair to get liquidity in
     *   conversionFactor: the price of AVAX to PFX
     *
     * Returns: the amount of liquidity in the pool in units of AVAX
     */
    function getPfxLiquidity(address pair, uint conversionFactor) public view returns (uint) {
        (uint reserve0, uint reserve1, ) = IPolarfoxPair(pair).getReserves();

        uint liquidity = 0;

        // add the pfx straight up
        if (IPolarfoxPair(pair).token0() == pfx) {
            liquidity = liquidity.add(reserve0);
        } else {
            require(IPolarfoxPair(pair).token1() == pfx, 'LiquidityPoolManager::getPfxLiquidity: One of the tokens in the pair must be PFX');
            liquidity = liquidity.add(reserve1);
        }

        uint oneToken = 1e18;
        liquidity = liquidity.mul(conversionFactor).mul(2).div(oneToken);
        return liquidity;
    }

    /**
     * Calculates the price of swapping AVAX for 1 PFX
     *
     * Returns: the price of swapping AVAX for 1 PFX
     */
    function getAvaxPfxRatio() public view returns (uint conversionFactor) {
        require(!(avaxPfxPair == address(0)), "LiquidityPoolManager::getAvaxPfxRatio: No AVAX-PFX pair set");
        (uint reserve0, uint reserve1, ) = IPolarfoxPair(avaxPfxPair).getReserves();

        if (IPolarfoxPair(avaxPfxPair).token0() == wavax) {
            conversionFactor = quote(reserve1, reserve0);
        } else {
            conversionFactor = quote(reserve0, reserve1);
        }
    }

    /**
     * Determine how the vested PFX allocation will be distributed to the liquidity
     * pool staking contracts. Must be called before distributeTokens(). Tokens are
     * distributed to pools based on relative liquidity proportional to total
     * liquidity. Should be called after vestAllocation()/
     */
    function calculateReturns() public {
        require(!readyToDistribute, 'LiquidityPoolManager::calculateReturns: Previous returns not distributed. Call distributeTokens()');
        require(unallocatedPfx > 0, 'LiquidityPoolManager::calculateReturns: No PFX to allocate. Call vestAllocation().');
        if (pfxPairs.length() > 0) {
            require(!(avaxPfxPair == address(0)), 'LiquidityPoolManager::calculateReturns: Avax/PFX Pair not set');
        }

        // Calculate total liquidity
        distribution = new uint[](numPools);
        uint totalLiquidity = 0;

        // Add liquidity from AVAX pairs
        for (uint i = 0; i < avaxPairs.length(); i++) {
            uint pairLiquidity = getAvaxLiquidity(avaxPairs.at(i));
            distribution[i] = pairLiquidity;
            totalLiquidity = SafeMath.add(totalLiquidity, pairLiquidity);
        }

        // Add liquidity from PFX pairs
        if (pfxPairs.length() > 0) {
            uint conversionRatio = getAvaxPfxRatio();
            for (uint i = 0; i < pfxPairs.length(); i++) {
                uint pairLiquidity = getPfxLiquidity(pfxPairs.at(i), conversionRatio);
                distribution[i + avaxPairs.length()] = pairLiquidity;
                totalLiquidity = SafeMath.add(totalLiquidity, pairLiquidity);
            }
        }

        // Calculate tokens for each pool
        uint transferred = 0;
        for (uint i = 0; i < distribution.length; i++) {
            uint pairTokens = distribution[i].mul(unallocatedPfx).div(totalLiquidity);
            distribution[i] = pairTokens;
            transferred = transferred + pairTokens;
        }
        readyToDistribute = true;
    }

    /**
     * After token distributions have been calculated, actually distribute the vested PFX
     * allocation to the staking pools. Must be called after calculateReturns().
     */
    function distributeTokens() public nonReentrant {
        require(readyToDistribute, 'LiquidityPoolManager::distributeTokens: Previous returns not allocated. Call calculateReturns()');
        readyToDistribute = false;
        address stakeContract;
        uint rewardTokens;
        for (uint i = 0; i < distribution.length; i++) {
            if (i < avaxPairs.length()) {
                stakeContract = stakes[avaxPairs.at(i)];
            } else {
                stakeContract = stakes[pfxPairs.at(i - avaxPairs.length())];
            }
            rewardTokens = distribution[i];
            if (rewardTokens > 0) {
                require(IPFX(pfx).transfer(stakeContract, rewardTokens), 'LiquidityPoolManager::distributeTokens: Transfer failed');
                StakingRewards(stakeContract).notifyRewardAmount(rewardTokens);
            }
        }
        unallocatedPfx = 0;
    }

    /**
     * Fallback for distributeTokens in case of gas overflow. Distributes PFX tokens to a single pool.
     * distibuteTokens() must still be called once to reset the contract state before calling vestAllocation.
     *
     * Args:
     *   pairIndex: index of pair to distribute tokens to, AVAX pairs come first in the ordering
     */
    function distributeTokensSinglePool(uint pairIndex) external nonReentrant {
        require(readyToDistribute, 'LiquidityPoolManager::distributeTokensSinglePool: Previous returns not allocated. Call calculateReturns()');
        require(pairIndex < numPools, 'LiquidityPoolManager::distributeTokensSinglePool: Index out of bounds');

        address stakeContract;
        if (pairIndex < avaxPairs.length()) {
            stakeContract = stakes[avaxPairs.at(pairIndex)];
        } else {
            stakeContract = stakes[pfxPairs.at(pairIndex - avaxPairs.length())];
        }

        uint rewardTokens = distribution[pairIndex];
        if (rewardTokens > 0) {
            distribution[pairIndex] = 0;
            require(IPFX(pfx).transfer(stakeContract, rewardTokens), 'LiquidityPoolManager::distributeTokens: Transfer failed');
            StakingRewards(stakeContract).notifyRewardAmount(rewardTokens);
        }
    }

    /**
     * Calculate pool token distribution and distribute tokens. Methods are separate
     * to use risk of approaching the gas limit. There must be vested tokens to
     * distribute, so this method should be called after vestAllocation.
     */
    function calculateAndDistribute() external {
        calculateReturns();
        distributeTokens();
    }

    /**
     * Claim today's vested tokens for the manager to distribute. Moves tokens from
     * the TreasuryVester to the LiquidityPoolManager. Can only be called if all
     * previously allocated tokens have been distributed. Call distributeTokens() if
     * that is not the case. If any additional PFX tokens have been transferred to this
     * this contract, they will be marked as unallocated and prepared for distribution.
     */
    function vestAllocation() external nonReentrant {
        require(unallocatedPfx == 0, 'LiquidityPoolManager::vestAllocation: Old PFX is unallocated. Call distributeTokens().');
        unallocatedPfx = ITreasuryVester(treasuryVester).claim();
        require(unallocatedPfx > 0, 'LiquidityPoolManager::vestAllocation: No PFX to claim. Try again tomorrow.');

        // Check if we've received extra tokens or didn't receive enough
        uint actualBalance = IPFX(pfx).balanceOf(address(this));
        require(actualBalance >= unallocatedPfx, "LiquidityPoolManager::vestAllocation: Insufficient PFX transferred");
        unallocatedPfx = actualBalance;
    }

    /**
     * Calculate the equivalent of 1e18 of token A denominated in token B for a pair
     * with reserveA and reserveB reserves.
     *
     * Args:
     *   reserveA: reserves of token A
     *   reserveB: reserves of token B
     *
     * Returns: the amount of token B equivalent to 1e18 of token A
     */
    function quote(uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(reserveA > 0 && reserveB > 0, 'PolarfoxLibrary: INSUFFICIENT_LIQUIDITY');
        uint oneToken = 1e18;
        amountB = SafeMath.div(SafeMath.mul(oneToken, reserveB), reserveA);
    }

}

interface ITreasuryVester {
    function claim() external returns (uint);
}

interface IPFX {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}

interface IPolarfoxPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function balanceOf(address owner) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function burn(address to) external returns (uint amount0, uint amount1);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}
