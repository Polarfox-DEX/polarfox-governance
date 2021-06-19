pragma solidity ^0.5.16;

import "./SafeMath.sol";

/**
 * The Polarfox treasury vester contract.
 * This contract's job is to distribute PFX to two multisig wallets over time:
 * 1/ The liquidity mining multisig, which will hold the PFX tokens to be sent for liquidity mining;
 * 2/ The team treasury multisig, which the team will use to fund its work.
 *
 * Four of such contracts will be deployed, each of which will last four years:
 * 1/ Treasury Vester 2021-2025 | 5,400,000 PFX distributed | 3,000,000 PFX to liquidity mining (55.5%) | 2,400,000 PFX to team treasury (44.5%);
 * 2/ Treasury Vester 2025-2029 | 2,800,000 PFX distributed | 1,600,000 PFX to liquidity mining (57.0%) | 1,200,000 PFX to team treasury (43.0%);
 * 3/ Treasury Vester 2029-2033 | 1,400,000 PFX distributed |   800,000 PFX to liquidity mining (57.0%) |   600,000 PFX to team treasury (43.0%);
 * 4/ Treasury Vester 2033-2037 |   700,000 PFX distributed |   400,000 PFX to liquidity mining (57.0%) |   300,000 PFX to team treasury (43.0%).
 * 
 * 200,000 PFX will be set aside for the first round of liquidity mining, hence the difference in percentages between
 * the first treasury vester contract and the others.
 */
contract TreasuryVester {
    using SafeMath for uint;

    address public pfx;
    address public liquidityMiningRecipient;
    address public teamTreasuryRecipient;

    // The percentage of tokens to be sent to liquidity mining.
    // The rest will be sent to the team treasury.
    uint public liquidityMiningWeight;

    uint public vestingAmount;
    uint public vestingBegin;
    uint public vestingCliff;
    uint public vestingEnd;

    uint public lastUpdate;

    constructor(
        address pfx_,
        address liquidityMiningRecipient_,
        address teamTreasuryRecipient_,
        uint liquidityMiningWeight_,
        uint vestingAmount_,
        uint vestingBegin_,
        uint vestingCliff_,
        uint vestingEnd_
    ) public {
        require(vestingBegin_ >= block.timestamp, 'TreasuryVester::constructor: vesting begin too early');
        require(vestingCliff_ >= vestingBegin_, 'TreasuryVester::constructor: cliff is too early');
        require(vestingEnd_ > vestingCliff_, 'TreasuryVester::constructor: end is too early');

        pfx = pfx_;
        liquidityMiningRecipient = liquidityMiningRecipient_;
        teamTreasuryRecipient = teamTreasuryRecipient_;

        liquidityMiningWeight = liquidityMiningWeight_; // Either 555 (55.5%) or 570 (57.0%) 

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin;
    }

    function setLiquidityMiningRecipient(address liquidityMiningRecipient_) public {
        require(msg.sender == liquidityMiningRecipient, 'TreasuryVester::setLiquidityMiningRecipient: unauthorized');
        liquidityMiningRecipient = liquidityMiningRecipient_;
    }

    function setTeamTreasuryRecipient(address teamTreasuryRecipient_) public {
        require(msg.sender == teamTreasuryRecipient, 'TreasuryVester::setTeamTreasuryRecipient: unauthorized');
        teamTreasuryRecipient = teamTreasuryRecipient_;
    }

    function claim() public {
        require(block.timestamp >= vestingCliff, 'TreasuryVester::claim: not time yet');
        
        // Calculate the total amount of PFX to send
        uint amount;
        if (block.timestamp >= vestingEnd) {
            amount = IPfx(pfx).balanceOf(address(this));
        } else {
            amount = vestingAmount.mul(block.timestamp - lastUpdate).div(vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        
        // Cut the total amount of PFX to send in two parts
        uint liquidityMiningAmount = amount.mul(liquidityMiningWeight).div(1000); // 55.5% = 555/1000 | 57.0% = 570/1000
        uint teamTreasuryAmount = amount - liquidityMiningAmount;

        // Send the PFX
        IPfx(pfx).transfer(liquidityMiningRecipient, liquidityMiningAmount);
        IPfx(pfx).transfer(teamTreasuryRecipient, teamTreasuryAmount);
    }
}

interface IPfx {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}