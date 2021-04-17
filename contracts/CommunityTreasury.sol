pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Custodian of community's PFX. Deploy this contract, then change the owner to be a
 * governance protocol. Send community treasury funds to the deployed contract, then
 * spend them through governance proposals.
 */
contract CommunityTreasury is Ownable {
    using SafeERC20 for IERC20;

    // Token to custody
    IERC20 public pfx;

    constructor(address pfx_) {
        pfx = IERC20(pfx_);
    }

    /**
     * Transfer PFX to the destination. Can only be called by the contract owner.
     */
    function transfer(address dest, uint amount) external onlyOwner {
        pfx.safeTransfer(dest, amount);
    }

    /**
     * Return the PFX balance of this contract.
     */
    function balance() view external returns(uint) {
        return pfx.balanceOf(address(this));
    }

}