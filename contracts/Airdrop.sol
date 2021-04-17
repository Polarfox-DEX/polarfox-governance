// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 *  Contract for administering the Airdrop of PFX to AKITA holders.
 *  13.45 million PFX will be made available in the airdrop. After the
 *  Airdrop period is over, all unclaimed PFX will be transferred to the
 *  community treasury.
 */
contract Airdrop {
    // token addresses
    address public pfx;
    address public akita;

    address public owner;
    address public remainderDestination;

    // amount of PFX to transfer
    mapping (address => uint96) public withdrawAmount;

    uint public totalAllocated;

    bool public claimingAllowed;

    uint constant public TOTAL_AIRDROP_SUPPLY = 13_450_000e18;

    // Events
    event ClaimingAllowed();
    event ClaimingOver();
    event PfxClaimed(address claimer, uint amount);

    /**
     * Initializes the contract. Sets token addresses, owner, and leftover token
     * destination. Claiming period is not enabled.
     *
     * @param pfx_ the PFX token contract address
     * @param akita_ the AKITA token contract address
     * @param owner_ the privileged contract owner
     * @param remainderDestination_ address to transfer remaining PFX to when
     *     claiming ends. Should be community treasury.
     */
    constructor(address pfx_,
                address akita_,
                address owner_,
                address remainderDestination_) {
        pfx = pfx_;
        akita = akita_;
        owner = owner_;
        remainderDestination = remainderDestination_;
        claimingAllowed = false;
        totalAllocated = 0;
    }

    /**
     * Changes the address that receives the remaining PFX at the end of the
     * claiming period. Can only be set by the contract owner.
     *
     * @param remainderDestination_ address to transfer remaining PFX to when
     *     claiming ends.
     */
    function setRemainderDestination(address remainderDestination_) external {
        require(msg.sender == owner, 'Airdrop::setRemainderDestination: unauthorized');
        remainderDestination = remainderDestination_;
    }

    /**
     * Changes the contract owner. Can only be set by the contract owner.
     *
     * @param owner_ new contract owner address
     */
    function setowner(address owner_) external {
        require(msg.sender == owner, 'Airdrop::setowner: unauthorized');
        owner = owner_;
    }

    /**
     * Enable the claiming period and allow user to claim PFX. Before activation,
     * this contract must have a PFX balance equal to the total airdrop PFX
     * supply of 16.9 million PFX. All claimable PFX tokens must be whitelisted
     * before claiming is enabled. Only callable by the owner.
     */
    function allowClaiming() external {
        require(IPFX(pfx).balanceOf(address(this)) >= TOTAL_AIRDROP_SUPPLY, 'Airdrop::allowClaiming: incorrect PFX supply');
        require(msg.sender == owner, 'Airdrop::allowClaiming: unauthorized');
        claimingAllowed = true;
        emit ClaimingAllowed();
    }

    /**
     * End the claiming period. All unclaimed PFX will be transferred to the address
     * specified by remainderDestination. Can only be called by the owner.
     */
    function endClaiming() external {
        require(msg.sender == owner, 'Airdrop::endClaiming: unauthorized');
        require(claimingAllowed, "Airdrop::endClaiming: Claiming not started");

        claimingAllowed = false;
        emit ClaimingOver();

        // Transfer remainder
        uint amount = IPFX(pfx).balanceOf(address(this));
        require(IPFX(pfx).transfer(remainderDestination, amount), 'Airdrop::endClaiming: Transfer failed');
    }

    /**
     * Withdraw your PFX. In order to qualify for a withdrawl, the caller's address
     * must be whitelisted. In addition, the calling address must have one whole AKITA // TODO: Update this if needed
     * token. All PFX must be claimed at once. Only the full amount can be claimed and 
     * only one claim is allowed per user.
     */
    function claim() external {
        // tradeoff: if you only transfer one but you held both, you can't claim
        require(claimingAllowed, 'Airdrop::claim: Claiming is not allowed');
        require(withdrawAmount[msg.sender] > 0, 'Airdrop::claim: No PFX to claim');

        uint oneToken = 1e18;
        require(IAkita(akita).balanceOf(msg.sender) >= oneToken,
            'Airdrop::claim: Insufficient AKITA balance');

        uint amountToClaim = withdrawAmount[msg.sender];
        withdrawAmount[msg.sender] = 0;

        emit PfxClaimed(msg.sender, amountToClaim);

        require(IPFX(pfx).transfer(msg.sender, amountToClaim), 'Airdrop::claim: Transfer failed');
    }

    /**
     * Whitelist an address to claim PFX. Specify the amount of PFX to be allocated.
     * That address will then be able to claim that amount of PFX during the claiming
     * period if it has sufficient AKITA balance. The transferrable amount of
     * PFX must be nonzero. Total amount allocated must be less than or equal to the
     * total airdrop supply. Whitelisting must occur before the claiming period is
     * enabled. Addresses may only be added one time. Only called by the owner.
     *
     * @param addr address that may claim PFX
     * @param pfxOut the amount of PFX that addr may withdraw
     */
    function whitelistAddress(address addr, uint96 pfxOut) public {
        require(msg.sender == owner, 'Airdrop::whitelistAddress: unauthorized');
        require(!claimingAllowed, 'Airdrop::whitelistAddress: claiming in session');
        require(pfxOut > 0, 'Airdrop::whitelistAddress: No PFX to allocated');
        require(withdrawAmount[addr] == 0, 'Airdrop::whitelistAddress: address already added');

        withdrawAmount[addr] = pfxOut;

        totalAllocated = totalAllocated + pfxOut;
        require(totalAllocated <= TOTAL_AIRDROP_SUPPLY, 'Airdrop::whitelistAddress: Exceeds PFX allocation');
    }

    /**
     * Whitelist multiple addresses in one call. Wrapper around whitelistAddress.
     * All parameters are arrays. Each array must be the same length. Each index
     * corresponds to one (address, pfx) tuple. Only callable by the owner.
     */
    function whitelistAddresses(address[] memory addrs, uint96[] memory pfxOuts) external {
        require(msg.sender == owner, 'Airdrop::whitelistAddresses: unauthorized');
        require(addrs.length == pfxOuts.length,
                'Airdrop::whitelistAddresses: incorrect array length');
        for (uint i = 0; i < addrs.length; i++) {
            whitelistAddress(addrs[i], pfxOuts[i]);
        }
    }
}

interface IPFX {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}

interface IAkita {
    function balanceOf(address account) external view returns (uint);
}