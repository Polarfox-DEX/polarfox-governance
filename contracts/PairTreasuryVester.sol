pragma solidity ^0.5.16;

import "./SafeMath.sol";

/**
 * The Polarfox pair treasury vester contract.
 * The treasury vesters' job is to distribute PFX to three multisig wallets over time:
 * 1/ The liquidity mining multisig, which will hold the PFX tokens to be sent for liquidity mining;
 * 2/ The governance treasury multisig, which will be given to the governance in time;
 * 3/ The team treasury multisig, which the team will use to fund its work.
 *
 * Five of such contracts will be deployed, four of which will last four years:
 * 1/ Pair Treasury Vester 2021-2025 | 5,232,000 PFX distributed | 4,800,000 PFX to liquidity mining (91.7%) | 432,000 PFX to governance treasury (08.3%);
 * 2/ Pair Treasury Vester 2025-2029 | 2,776,000 PFX distributed | 2,560,000 PFX to liquidity mining (92.2%) | 216,000 PFX to governance treasury (07.8%);
 * 3/ Pair Treasury Vester 2029-2033 | 1,388,000 PFX distributed | 1,280,000 PFX to liquidity mining (92.2%) | 108,000 PFX to governance treasury (07.8%);
 * 4/ Pair Treasury Vester 2033-2037 |   694,000 PFX distributed |   640,000 PFX to liquidity mining (92.2%) |  54,000 PFX to governance treasury (07.8%).
 *
 * 320,000 PFX will be set aside for the first round of liquidity mining, hence the difference in percentages between
 * the first treasury vester contract and the others.
 *
 * A fifth contract will be deployed separately for team funding and will last three years:
 * 5/ Treasury Vester 2021-2024 | 1,590,000 PFX distributed | 1,590,000 to team funding (100.0%)
 * 
 * When those contracts are deployed, the Polarfox team will not be using multisigs as there are no good multisig
 * implementations of Avalanche at this time. The team will look into the possibility of creating our own multisig
 * wallets and change the recipients from this contract to the relevant multisig wallets.
 */
contract PairTreasuryVester {
    using SafeMath for uint;

    address public pfx;
    address public liquidityMiningRecipient;
    address public governanceTreasuryRecipient;

    // The percentage of tokens to be sent to liquidity mining.
    // The rest will be sent to the governance treasury.
    uint public liquidityMiningWeight;

    uint public vestingAmount;
    uint public vestingBegin;
    uint public vestingCliff;
    uint public vestingEnd;

    uint public lastUpdate;

    constructor(
        address pfx_,
        address liquidityMiningRecipient_,
        address governanceTreasuryRecipient_,
        uint liquidityMiningWeight_,
        uint vestingAmount_,
        uint vestingBegin_,
        uint vestingCliff_,
        uint vestingEnd_
    ) public {
        require(vestingBegin_ >= block.timestamp, 'PairTreasuryVester::constructor: vesting begin too early');
        require(vestingCliff_ >= vestingBegin_, 'PairTreasuryVester::constructor: cliff is too early');
        require(vestingEnd_ > vestingCliff_, 'PairTreasuryVester::constructor: end is too early');

        pfx = pfx_;
        liquidityMiningRecipient = liquidityMiningRecipient_;
        governanceTreasuryRecipient = governanceTreasuryRecipient_;

        liquidityMiningWeight = liquidityMiningWeight_; // Either 917 (91.7%) or 922 (92.2%) 

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin;
    }

    function setLiquidityMiningRecipient(address liquidityMiningRecipient_) public {
        require(msg.sender == liquidityMiningRecipient, 'PairTreasuryVester::setLiquidityMiningRecipient: unauthorized');
        liquidityMiningRecipient = liquidityMiningRecipient_;
    }

    function setGovernanceTreasuryRecipient(address governanceTreasuryRecipient_) public {
        require(msg.sender == governanceTreasuryRecipient, 'PairTreasuryVester::setGovernanceTreasuryRecipient: unauthorized');
        governanceTreasuryRecipient = governanceTreasuryRecipient_;
    }

    function claim() public {
        require(block.timestamp >= vestingCliff, 'PairTreasuryVester::claim: not time yet');
        
        // Calculate the total amount of PFX to send
        uint amount;
        if (block.timestamp >= vestingEnd) {
            amount = IPfx(pfx).balanceOf(address(this));
        } else {
            amount = vestingAmount.mul(block.timestamp - lastUpdate).div(vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        
        // Cut the total amount of PFX to send in two parts
        uint liquidityMiningAmount = amount.mul(liquidityMiningWeight).div(1000); // 91.7% = 917/1000 | 92.2% = 922/1000
        uint governanceTreasuryAmount = amount - liquidityMiningAmount;

        // Send the PFX
        IPfx(pfx).transfer(liquidityMiningRecipient, liquidityMiningAmount);
        IPfx(pfx).transfer(governanceTreasuryRecipient, governanceTreasuryAmount);
    }
}

interface IPfx {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}